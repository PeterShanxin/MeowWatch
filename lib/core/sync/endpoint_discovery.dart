import 'dart:async';
import 'dart:math';

import '../data/settings_store.dart';
import 'peer_state.dart';
import 'sync_core.dart';
import 'syncplay_client.dart';
import 'syncplay_endpoints.dart';

/// Shown when no public candidate completed the handshake. Deliberately does
/// not ask the user to name a server: the people who hit this are the ones with
/// no way to answer that question (#234).
const String kNoSyncplayServerMessage =
    'MeowWatch could not reach any Syncplay server right now. Check your '
    'internet connection and try again in a moment.';

/// How long one candidate gets to complete the handshake before it counts as
/// dead. Generous against a slow link, small enough that walking the whole
/// curated list stays bounded.
const Duration kEndpointProbeTimeout = Duration(seconds: 5);

/// Finds a working public endpoint, or null when none answered. [preferred] is
/// the endpoint a room already lives on; omit it for a brand-new room.
typedef ResolveSyncplayEndpoint =
    Future<SyncplayEndpoint?> Function({SyncplayEndpoint? preferred});

/// Answers whether [endpoint] completed the full handshake MeowWatch needs.
typedef SyncplayEndpointProbe =
    Future<bool> Function(
      SyncplayEndpoint endpoint, {
      required Duration timeout,
    });

/// Builds the client one probe drives. Injectable so tests never dial the
/// public internet.
typedef ProbeClientFactory =
    SyncCore Function({required Duration livenessTimeout});

/// Dials one endpoint with a real [SyncplayClient] and reports whether it
/// reached [SyncConnectionStatus.connected] — which the client emits only on
/// the server's Hello, and only ever over the socket a completed TLS upgrade
/// produced.
///
/// Reusing the real client is the point. An open TCP socket proves nothing (a
/// dead or non-Syncplay listener accepts one just as happily), and a
/// hand-rolled handshake here would be a second copy of the STARTTLS state
/// machine to keep hardened. A candidate counts as working exactly when the
/// thing the app actually does works.
///
/// The probe joins a throwaway room under a throwaway name and drops the
/// connection as soon as the server answers, so it never puts the user in a
/// room on a server they end up not using, and never races the real connect for
/// their own username.
class SyncplayHandshakeProbe {
  SyncplayHandshakeProbe({ProbeClientFactory? createClient, this.onLog})
    : _createClient = createClient ?? _liveClient;

  final ProbeClientFactory _createClient;
  final void Function(String line)? onLog;

  static final Random _random = Random();

  static SyncCore _liveClient({required Duration livenessTimeout}) =>
      SyncplayClient(livenessTimeout: livenessTimeout);

  Future<bool> call(
    SyncplayEndpoint endpoint, {
    required Duration timeout,
  }) async {
    // The client's own silence watchdog is the inner bound and [timeout] the
    // outer one. Sharing the budget stops a server that opens a socket and then
    // says nothing from holding up the whole scan.
    final client = _createClient(livenessTimeout: timeout);
    final outcome = Completer<bool>();
    void settle(bool reachable) {
      if (!outcome.isCompleted) outcome.complete(reachable);
    }

    final subscription = client.connectionState.listen((state) {
      if (state.status == SyncConnectionStatus.connected) {
        settle(true);
      } else if (state.status == SyncConnectionStatus.error) {
        settle(false);
      }
    }, onError: (Object _) => settle(false));
    // Never a room or a name the user is about to use, and different every
    // probe so two of them never meet in the same throwaway room. No password
    // either: candidates are public servers that ignore one, and a probe must
    // not hand the user's server password to an endpoint they may never use.
    final id = _random.nextInt(1 << 32).toRadixString(16);
    try {
      unawaited(
        client
            .connect(
              server: endpoint.host,
              port: endpoint.port,
              username: 'meowwatch-probe-$id',
              room: 'meowwatch-probe-$id',
            )
            .then((_) {}, onError: (Object _) => settle(false)),
      );
      return await outcome.future.timeout(timeout, onTimeout: () => false);
    } finally {
      // Cancel before dispose so a teardown state change cannot land on a
      // closed controller, then dispose: it stops the watchdog and any pending
      // reconnect, destroys the socket, and closes the streams.
      await subscription.cancel();
      await client.dispose();
    }
  }
}

/// Picks the public Syncplay endpoint a default session should use, and
/// remembers the one that worked.
///
/// Candidates are walked **sequentially, in the curated order**. Racing them
/// would be faster and wrong: the winner would be whichever answered first from
/// *this* machine, so two friends resolving independently could land on
/// different servers and each see an empty room. A fixed order means the same
/// starting point yields the same answer on both sides.
class SyncplayEndpointDiscovery {
  SyncplayEndpointDiscovery({
    required this.settings,
    SyncplayEndpointProbe? probe,
    this.candidates = kPublicSyncplayEndpoints,
    this.perCandidateTimeout = kEndpointProbeTimeout,
    this.onLog,
  }) : _probe = probe ?? SyncplayHandshakeProbe(onLog: onLog).call;

  final SettingsStore settings;
  final SyncplayEndpointProbe _probe;
  final List<SyncplayEndpoint> candidates;
  final Duration perCandidateTimeout;
  final void Function(String line)? onLog;

  /// Returns a working endpoint, or null when none answered.
  ///
  /// [preferred] is the endpoint a room already lives on (a saved room, a
  /// resumed history entry). It is tried first and, when it answers, is the
  /// only thing dialled. Endpoints outside [candidates] are never dialled here
  /// — a server the user named is the caller's to use as-is, not discovery's to
  /// second-guess.
  Future<SyncplayEndpoint?> resolve({SyncplayEndpoint? preferred}) async {
    for (final endpoint in await _searchOrder(preferred)) {
      if (await _probe(endpoint, timeout: perCandidateTimeout)) {
        await _remember(endpoint);
        return endpoint;
      }
      onLog?.call('endpoint discovery: $endpoint did not answer');
    }
    onLog?.call('endpoint discovery: no public server answered');
    return null;
  }

  Future<List<SyncplayEndpoint>> _searchOrder(
    SyncplayEndpoint? preferred,
  ) async {
    final ordered = <SyncplayEndpoint>[];
    void add(SyncplayEndpoint? endpoint) {
      if (endpoint == null) return;
      if (!candidates.contains(endpoint)) return;
      if (ordered.contains(endpoint)) return;
      ordered.add(endpoint);
    }

    add(preferred);
    // The remembered winner is a preference for a *new* room. A room that
    // already has an address skips it: two peers whose remembered winners
    // differ would otherwise fall back to different servers and lose each
    // other, which costs more than one extra probe.
    if (preferred == null) add(await _remembered());
    candidates.forEach(add);
    return ordered;
  }

  Future<SyncplayEndpoint?> _remembered() async {
    final stored = await settings.get(kSyncplayEndpointSettingKey);
    if (stored == null || stored.isEmpty) return null;
    return SyncplayEndpoint.tryParse(stored);
  }

  Future<void> _remember(SyncplayEndpoint endpoint) async {
    try {
      await settings.set(kSyncplayEndpointSettingKey, endpoint.toString());
    } on Object catch (error) {
      // The stored endpoint is a cache — losing it costs one extra probe next
      // launch. Failing the user's connect over it would cost the session.
      onLog?.call('endpoint discovery: could not remember $endpoint — $error');
    }
  }
}
