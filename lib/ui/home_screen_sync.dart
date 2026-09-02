part of 'home_screen.dart';

/// The connection/presence seam of [_HomeScreenState] (#182): sync status,
/// peer + own-ghost bookkeeping, announced peer files, sync health with the
/// auto-pause debounce, transient notices, and the over-video banner text.
mixin _HomeSyncState on _HomeScreenStateBase, _HomeIdleState {
  // Implemented by [_HomeMediaState]: the connect/join handlers re-announce
  // the confirmed-open source, and the banner logic reads the leave/load
  // state, so the media seam supplies these.
  bool get _leavingRoom;
  String? get _loadedSource;
  bool _shouldReannounceOnConnect();
  // Narrower than the media seam's implementation (which also takes a named
  // `sizeBytes`) — the sync-side callers only ever pass the path.
  void _announceLoadedFile(String? path);

  /// Implemented by [_HomeMediaState]: a join that never logged in returns
  /// to the start screen with [message] so the named error is on the lobby.
  void _abortFailedJoin(String? message);

  // Start as "connecting": Local Start and Continue Watching dial from
  // this screen. A lobby join that already completed login flips these
  // to connected in initState before the first frame.
  SyncConnectionStatus _syncStatus = SyncConnectionStatus.connecting;
  String? _syncError;
  final Set<String> _peers = <String>{};
  StreamSubscription<SyncConnectionState>? _connSub;
  StreamSubscription<PresenceEvent>? _presenceSub;
  StreamSubscription<PlaybackState>? _noticeSub;
  StreamSubscription<PeerFile>? _peerFileSub;
  StreamSubscription<SyncActivity>? _activitySub;
  StreamSubscription<List<String>>? _rosterSub;
  StreamSubscription<String>? _leavingSub;

  /// Previous connection status — used to detect the drop edge.
  SyncConnectionStatus _prevSyncStatus = SyncConnectionStatus.disconnected;

  /// Latched the first time this room session reaches `connected`. A later
  /// kick or drop stays on the watch UI; only a join that never logged in
  /// returns to the start screen with the named error. Lobby joins that
  /// already completed Hello set this true in initState.
  bool _everRoomConnected = false;

  /// Latched true on a local drop (connected → reconnecting) and cleared when we
  /// reconnect or stop trying. Needed because the reconnect path passes through
  /// an intermediate `handshaking` state, so the "Reconnected to room." line
  /// can't be detected from `prev` alone (issue #92).
  bool _wasReconnecting = false;

  /// Our own dropped sessions' names → when each was latched. A reconnect that
  /// comes back under a different wire identity ("meowPEOW" → "meowPEOW_") means
  /// the server wouldn't hand our prior name back, because that just-dropped
  /// session still holds it as a ghost. Each such ghost is recorded here and
  /// consumed on its [PresenceKind.left] so the departure isn't announced as a
  /// peer "lost connection" — the name was ours (#93 field report).
  ///
  /// A map, not a single slot: a burst of chained reconnects (drop → reconnect →
  /// drop → reconnect before the first ghost is reaped) can leave several of our
  /// own names lingering at once, and each must be silenced. Entries are pruned
  /// by the reconnect window — a ghost's `left` is only silenced if it lands
  /// within that window of being latched, bounding the residual case where a
  /// real peer grabbed our just-freed name during the blip (#93 ambiguity).
  final Map<String, DateTime> _pendingGhosts = <String, DateTime>{};

  /// The server-assigned wire name from our most recent *connected* state. Lets
  /// the next reconnect tell whether the server handed our prior name back (no
  /// ghost) or moved us off it because our own dropped session still holds it.
  String? _lastConnectedUsername;

  /// Peers who sent a [LeavingSignal] before their [PresenceKind.left] event;
  /// consumed once on departure to determine clean vs. connection-drop wording.
  final Set<String> _cleanlyLeaving = <String>{};

  /// When each peer last departed, so a quick rejoin reads as "reconnected"
  /// rather than "joined the room" (issue #92).
  final Map<String, DateTime> _departedAt = <String, DateTime>{};

  /// Files announced by peers, keyed by username, plus our own loaded file's
  /// byte size — together they drive the file-mismatch warning. Keying by user
  /// (rather than a single slot) means a transient ghost of our own dropped
  /// session can't wipe a real friend's file when it departs (#93). [_peerFile]
  /// surfaces only a currently-present peer's file.
  PeerFiles _peerFiles = const PeerFiles();
  int? _localFileSizeBytes;

  /// The file of the peer we're currently watching with, or null if no present
  /// peer has announced one. Derived from [_peerFiles] restricted to [_peers].
  PeerFile? get _peerFile => _peerFiles.currentAmong(_peers);

  /// Was the session in sync (connected + a peer present) at the last check?
  /// Used to detect the healthy -> unhealthy edge that triggers auto-pause.
  bool _syncHealthy = false;

  /// True while we've auto-paused because sync dropped; drives the banner.
  bool _autoPausedNotice = false;

  /// The reason text for the current auto-pause (peer left vs. connection lost),
  /// snapshotted at pause time so the banner can't later show a stale cause.
  String? _autoPausedReason;

  /// Transient banner when a friend joins/rejoins the room (auto-clears).
  /// A notifier, not a plain field: activity/presence notices are hot events
  /// and must dirty only the banner subtree, not the whole room Stack (#196).
  final ValueNotifier<String?> _presenceNotice = ValueNotifier<String?>(null);
  Timer? _presenceTimer;

  /// The name of the last peer who left the room.
  String? _lastPeerLeft;

  /// Persistent "your friend started playback — load a video to join" prompt
  /// shown on the empty (no-video) screen when a peer controls playback before
  /// we've loaded anything (#60). Cleared once we load a video or the peer
  /// leaves. The reverse direction is handled by the same code running on the
  /// friend's machine. Carries a one-click [JoinPrompt.url] when the peer's
  /// announced media is a direct link (#121), so the empty screen can offer a
  /// "Watch this too" button in addition to the text.
  JoinPrompt? _joinPrompt;

  /// Debounce before auto-pausing: a brief blip (e.g. a heartbeat timeout that
  /// recovers a second later, common when two instances share one PC) should
  /// NOT pause — only a sustained loss of sync.
  Timer? _autoPauseTimer;
  static const _autoPauseDelay = Duration(seconds: 2);

  /// Collapses bursts of seek notifications into a single line/banner (#26).
  final SyncActivityThrottle _activityThrottle = SyncActivityThrottle();
  StreamSubscription<SyncActivity>? _activityThrottleSub;

  /// Wires collaboration streams: connection, leave, presence, peer files,
  /// throttled activity, and the initial roster. Playback-stop idle wake
  /// lives in [_initPlaybackWakeSubscription] so local sessions keep it.
  void _initSyncSubscriptions() {
    final sync = _sync;
    final chat = _chat;
    if (sync == null || chat == null) return;
    final last = sync.lastConnectionState;
    if (last != null && last.status == SyncConnectionStatus.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abortFailedJoin(last.message);
      });
      return;
    }
    _connSub = sync.connectionState.listen((s) {
      if (s.status == SyncConnectionStatus.connected) {
        _everRoomConnected = true;
      }
      if (isFailedInitialJoin(
        status: s.status,
        everConnected: _everRoomConnected,
      )) {
        _abortFailedJoin(s.message);
        return;
      }
      if (mounted) {
        setState(() {
          _syncStatus = s.status;
          _syncError = s.message;
          // Adopt the server-assigned wire identity so chat ownership, typing
          // attribution and self-notifications all match the name peers (and the
          // chat echo) actually use for us (#40). This is the WIRE name only — it
          // can carry a transient dedupe suffix after a reconnect, so the gear
          // member list shows widget.config.username (our chosen name) instead (#107).
          if (s.username != null && s.username!.isNotEmpty) {
            _username = s.username!;
          }
          if (s.status != SyncConnectionStatus.connected) {
            // Our own connection changed — peer membership and the per-peer
            // departure/leaving bookkeeping are no longer valid. Clearing here
            // also bounds these maps across repeated local reconnect cycles.
            _peers.clear();
            _departedAt.clear();
            _cleanlyLeaving.clear();
            // NB: do NOT clear _pendingGhosts here. A fresh drop is exactly when
            // a chained reconnect adds another of our own ghosts; discarding the
            // earlier ones would leak their `left` as a peer "lost connection".
            // They are pruned by the reconnect-window expiry instead (#93).
            // Drop the cached peer files too, so they are rebuilt
            // deterministically from the post-reconnect roster rather than
            // masking a stale value (#93). _peerNoVideoHint is gated on
            // _syncHealthyNow, so this can't flash "hasn't loaded" while
            // we're disconnected.
            _peerFiles = const PeerFiles();
            // The empty-screen join prompt is pinned imperatively from peer
            // file/playback events, so it isn't gated on sync health like the
            // banner is. Clear it here too, or a "<peer> loaded …" / "started
            // playback …" nudge stays on the load screen with no peer present
            // while we reconnect or disconnect (#116 review).
            _joinPrompt = null;
          }
          _evaluateSyncHealth();
        });
      }
      // Local connection transition chat lines (issue #92). Run after setState
      // so _syncStatus is already updated; addSystem pushes its own emission.
      if (isConnectionDrop(prev: _prevSyncStatus, next: s.status)) {
        _wasReconnecting = true;
        chat.addSystem(connectionLostMessage);
      } else if (isReconnectSuccess(
        wasReconnecting: _wasReconnecting,
        next: s.status,
      )) {
        _wasReconnecting = false;
        chat.addSystem(reconnectedToRoomMessage);
        // If the server wouldn't hand our prior wire name back on this
        // reconnect, our just-dropped session is lingering as a ghost on it and
        // will shortly be reaped — record it so its departure is silenced, not
        // read as a peer "lost connection" (#93 field report). Uses the prior
        // assigned name (_lastConnectedUsername), set below for the next pass.
        final now = DateTime.now();
        // Prune expired ghosts first so the map can't grow without bound when a
        // ghost is never reaped (no `left` ever arrives).
        _pendingGhosts.removeWhere(
          (_, at) => !isPeerReconnect(departedAt: at, now: now),
        );
        final ghost = ownGhostNameOnReconnect(
          reconnected: true,
          previousAssignedName: _lastConnectedUsername,
          assignedName: s.username,
        );
        if (ghost != null) _pendingGhosts[ghost] = now;
      }
      // A deliberate leave or fatal error ends the reconnect attempt — drop the
      // latch so a later fresh connect isn't mistaken for a reconnect, and clear
      // pending ghosts (we're leaving this room; they're moot).
      if (s.status == SyncConnectionStatus.disconnected ||
          s.status == SyncConnectionStatus.error) {
        _wasReconnecting = false;
        _pendingGhosts.clear();
      }
      // Remember the wire name we connected under, so the next reconnect can
      // tell a server-forced rename (our ghost holds the old name) from getting
      // the same name back. Updated after the arm above, which reads the prior.
      if (s.status == SyncConnectionStatus.connected) {
        _lastConnectedUsername = s.username;
      }
      _prevSyncStatus = s.status;
      if (s.status == SyncConnectionStatus.connected &&
          _shouldReannounceOnConnect()) {
        _announceLoadedFile(_loadedSource);
      }
    });
    // Track peers who announced a deliberate leave so the presence listener can
    // distinguish "left the room" from "lost connection" (issue #92).
    _leavingSub = chat.leaving.listen((name) => _cleanlyLeaving.add(name));
    _presenceSub = sync.presence.listen((e) {
      if (!mounted) return;
      // Our own lingering ghost (a post-reconnect roster entry under a name the
      // server renamed us off) must never be treated as a peer — otherwise it
      // enters _peers and its eventual `left` flips sync health, auto-pausing us
      // for our own old session (#93). Skip its *join* outright; its `left` is
      // consumed silently in the departure handler below to clear the latch.
      if (e.kind == PresenceKind.joined && _isOwnGhost(e.username)) return;
      setState(() {
        if (e.kind == PresenceKind.joined) {
          final isNew = _peers.add(e.username);
          // Roster entries (people already here when we arrived) update
          // membership silently; only a live join gets a banner + event line.
          if (isNew && !e.fromRoster) {
            final reconnected = isPeerReconnect(
              departedAt: _departedAt[e.username],
              now: DateTime.now(),
            );
            _departedAt.remove(e.username);
            final banner = reconnected
                ? '🐾 ${e.username} reconnected'
                : '🐾 ${e.username} joined';
            _showTransientNotice(banner);
            chat.addSystem(
              peerJoinMessage(username: e.username, reconnected: reconnected),
            );
            if (_shouldReannounceOnConnect()) {
              _announceLoadedFile(_loadedSource);
            }
          }
        } else {
          _peers.remove(e.username);
          _peerFiles = _peerFiles.remove(e.username);
          // The "load a video to join" prompt is stale once they've left (#60).
          _joinPrompt = null;
          // Our own lingering ghost from a server-forced rename, but only if its
          // `left` lands within the reconnect window — a much later departure of
          // the same name is a real peer that grabbed it, not our ghost (#93).
          final isOwnGhost = _isOwnGhost(e.username);
          // Consume the latch (whether or not in-window) so a stale ghost can't
          // keep shadowing this name.
          _pendingGhosts.remove(e.username);
          if (isOwnGhost) {
            // The ghost was skipped at join, so it was never in _peers and the
            // _evaluateSyncHealth() below sees no change. Just clear its
            // bookkeeping and stay silent — the name was ours (#93).
            _departedAt.remove(e.username);
            _cleanlyLeaving.remove(e.username);
          } else {
            _lastPeerLeft = e.username;
            final clean = _cleanlyLeaving.remove(e.username);
            // Only a *drop* makes a quick return read as "reconnected"; a
            // deliberate leave that comes back is a fresh "joined", not a network
            // blip recovering (#92 follow-up).
            if (clean) {
              _departedAt.remove(e.username);
            } else {
              _departedAt[e.username] = DateTime.now();
            }
            final banner = clean
                ? '👋 ${e.username} left'
                : '📵 ${e.username} lost connection';
            _showTransientNotice(banner);
            chat.addSystem(
              peerDepartureMessage(username: e.username, clean: clean),
            );
          }
        }
        _evaluateSyncHealth();
      });
    });
    _peerFileSub = sync.peerFile.listen((f) {
      if (!mounted) return;
      setState(() {
        _peerFiles = _peerFiles.set(f);
        // A peer announced a loaded file while we have nothing loaded: pin the
        // "load the same video to join" prompt on the empty screen so the side
        // still picking a file knows which one — the mirror of the loader's
        // "hasn't loaded a video yet" heads-up (#116). The play-triggered prompt
        // below takes over if/when they actually start playback. When the
        // peer's media is a direct link, offer a one-click "Watch this too"
        // load instead of the plain text — same trigger, richer action (#121).
        final localHasFile = _core.state.fileName != null;
        JoinPrompt? prompt;
        if (isHttpUrl(f.name)) {
          prompt = peerLoadedUrlJoinPrompt(
            localHasFile: localHasFile,
            localUsername: _username,
            peerUsername: f.username,
            peerFileUrl: f.name,
          );
        } else {
          final message = peerLoadedJoinPrompt(
            localHasFile: localHasFile,
            localUsername: _username,
            peerUsername: f.username,
            // Show the short/redacted label — a peer's raw URL (with any
            // signed token) must never render verbatim in our join prompt.
            peerFileName: mediaDisplayName(f.name),
          );
          if (message != null) prompt = JoinPrompt(message);
        }
        if (prompt != null) _joinPrompt = prompt;
      });
    });
    // Sync activities (peer + our own) flow through the throttle so a scrub
    // burst collapses to one line/banner (#26); the throttled output drives the
    // banner + chat history. We gate on sync health at BOTH ends: at intake to
    // avoid buffering lonely activity, and again at output because the throttle
    // debounce can outlast a peer leaving — without the second gate, an activity
    // queued while healthy would still surface after sync is gone (#41).
    _activitySub = sync.activity.listen((a) {
      if (!_syncHealthyNow) return;
      _activityThrottle.add(a);
    });
    _activityThrottleSub = _activityThrottle.stream.listen((a) {
      if (!mounted || !_syncHealthyNow) return;
      final t = syncActivityText(a, selfUsername: _username);
      // The banner is a notifier write — a scrub burst must not rebuild the
      // whole Stack (#196). Only the (usually absent) join prompt, which the
      // empty screen consumes, still needs a setState.
      _showTransientNotice(t.banner);
      // A peer drove playback while we have no video loaded: the transient
      // banner is easy to miss on the empty screen, so also pin a persistent
      // "load a video to join" prompt there (#60).
      // Carry an active one-click URL offer through the play-start prompt:
      // the peer pressing play on the link they announced must not downgrade
      // the "Watch this too" button to plain text (#121 follow-up). The
      // function only carries it when the offer came from this same peer
      // (#214 review).
      final prompt = peerStartedPlaybackPrompt(
        localHasFile: _core.state.fileName != null,
        localUsername: _username,
        peerUsername: a.username,
        activeOffer: _joinPrompt,
      );
      if (prompt != null) {
        setState(() => _joinPrompt = prompt);
      }
      chat.addSystem(t.chatLine);
    });
    _rosterSub = sync.initialRoster.listen((members) {
      if (!mounted) return;
      chat.addSystem(roomGreeting(members));
      // Friends already in the room when you arrive get a banner too, not just
      // the chat greeting (easy to miss on the video). Live joins after this are
      // handled by the presence handler above.
      final banner = rosterPresenceBanner(members);
      if (banner != null) _showTransientNotice(banner);
    });
    _noticeSub = _core.stateStream.listen((s) {
      if (!mounted) return;
      if (_autoPausedNotice && s.status == PlaybackStatus.playing) {
        setState(() => _autoPausedNotice = false);
      }
    });
    // The lobby join completes Hello before this route mounts, so the
    // one-shot roster greeting would otherwise miss the watch UI.
    sync.requestList();
  }

  /// Show a transient banner (friend joined/left, or a sync action); auto-clears
  /// after a few seconds. Writes the notifier directly — no setState needed;
  /// only the banner subtree rebuilds (#196).
  void _showTransientNotice(String text) {
    _presenceNotice.value = text;
    _presenceTimer?.cancel();
    _presenceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _presenceNotice.value = null;
    });
  }

  bool get _syncHealthyNow => SyncHealth(
    connected: _syncStatus == SyncConnectionStatus.connected,
    hasPeer: _peers.isNotEmpty,
  ).healthy;

  /// True when [name] is one of our own pending ghosts still inside the
  /// reconnect window — a post-reconnect roster/`left` event for our just-renamed
  /// prior session, not a real peer (#93). Non-consuming; the departure handler
  /// removes the entry from [_pendingGhosts] when the `left` actually fires.
  bool _isOwnGhost(String name) {
    final at = _pendingGhosts[name];
    return at != null && isPeerReconnect(departedAt: at, now: DateTime.now());
  }

  /// Recompute sync health and (after a debounce) auto-pause on a sustained
  /// healthy -> unhealthy drop. Call inside setState after [_syncStatus] /
  /// [_peers] change.
  void _evaluateSyncHealth() {
    final nowHealthy = _syncHealthyNow;
    final isPlaying = _core.state.status == PlaybackStatus.playing;

    if (nowHealthy) {
      // Recovered (or never lost) — cancel any pending pause, clear banner.
      // Also forget who last left: keeping it would let a later *connection*
      // drop wrongly blame a friend who left a different session ago.
      _autoPauseTimer?.cancel();
      _autoPauseTimer = null;
      _autoPausedNotice = false;
      _lastPeerLeft = null;
    } else if (decideAutoPause(
          wasHealthy: _syncHealthy,
          nowHealthy: nowHealthy,
          isPlaying: isPlaying,
        ) &&
        _autoPauseTimer == null) {
      // Edge into unhealthy while playing — arm the debounce, confirm later.
      _autoPauseTimer = Timer(_autoPauseDelay, _confirmAutoPause);
    }
    _syncHealthy = nowHealthy;
  }

  /// Fires after the debounce: pause only if sync is STILL down and we're
  /// still playing. A blip that already recovered cancelled this timer.
  void _confirmAutoPause() {
    _autoPauseTimer = null;
    if (!mounted) return;
    final stillDown = !_syncHealthyNow;
    final playing = _core.state.status == PlaybackStatus.playing;
    if (stillDown && playing) {
      // Phrase the reason by actual cause: a friend leaving (still connected,
      // empty room) names them; any other drop is a connection loss and must
      // not claim someone left (#41 follow-up).
      final reason = autoPauseMessage(
        cause: autoPauseCause(
          connected: _syncStatus == SyncConnectionStatus.connected,
          hasPeer: _peers.isNotEmpty,
        ),
        peerName: _lastPeerLeft,
      );
      unawaited(_core.pause());
      setState(() {
        _autoPausedNotice = true;
        _autoPausedReason = reason;
      });
      _chat?.addSystem(reason);
    }
  }

  /// Banner text derived from setState-managed state, or null when nothing to
  /// say — everything below the transient [_presenceNotice], which is a
  /// notifier and layered on top in [build] (#196). Priority: a file-mismatch
  /// warning, then the auto-pause reason, then a "friend hasn't loaded a
  /// video" heads-up, then the plain waiting/connect hint.
  String? get _banner {
    if (!_isSynced) return null;
    // Once leaving is committed, suppress every hint — the socket teardown can
    // briefly flip status to "Connecting…/Disconnected" and we don't want that
    // flashing over the video during the leave + route-exit animation.
    if (_leavingRoom) return null;
    final mismatch = _fileMismatchBanner;
    if (mismatch != null) return mismatch;
    if (_autoPausedNotice) {
      return '⏸ ${_autoPausedReason ?? 'Paused — lost sync with your friend'}';
    }
    final waitingForPeerVideo = _peerNoVideoHint;
    if (waitingForPeerVideo != null) return waitingForPeerVideo;
    return _syncHint;
  }

  /// The flip side of the empty-screen join prompt (#60): once WE have a video
  /// loaded and a friend is in the room but hasn't loaded one yet (no announced
  /// peer file), tell us they can't follow along until they load it — so a
  /// one-sided session isn't silent on our end either.
  String? get _peerNoVideoHint {
    if (_core.state.fileName == null) return null; // their concern, not ours
    if (!_syncHealthyNow) return null; // need a connected friend present
    if (_peerFile != null) return null; // they've announced a file
    final peer = _peers.isNotEmpty ? _peers.first : null;
    if (peer == null) return null;
    return '⏳ $peer hasn\'t loaded a video yet';
  }

  /// Warn when the peer's loaded file clearly differs from ours.
  String? get _fileMismatchBanner {
    final peer = _peerFile;
    if (peer == null) return null;
    final result = compareFiles(
      localName: _core.state.fileName,
      localSize: _localFileSizeBytes,
      peerName: peer.name,
      peerSize: peer.sizeBytes,
    );
    if (result != FileMatch.mismatch) return null;
    // Match on the raw name above; show the short/redacted label in the banner.
    return '⚠ Different file — ${peer.username} has "${mediaDisplayName(peer.name)}"';
  }

  /// Advisory hint shown over the video, or null when everything is ready.
  /// Reflects the live connection status (so the user sees "Connecting to room
  /// X…" instead of a generic prompt while the socket is still negotiating).
  String? get _syncHint {
    final room = widget.config.room;
    switch (_syncStatus) {
      case SyncConnectionStatus.connecting:
      case SyncConnectionStatus.handshaking:
        return 'Connecting to room $room…';
      case SyncConnectionStatus.reconnecting:
        // Surface the concrete failure reason when we have one (e.g. "Could not
        // reach server…" from a failed dial); otherwise the generic line.
        return _syncError != null
            ? '${_syncError!} — reconnecting…'
            : 'Connection lost — reconnecting to room $room…';
      case SyncConnectionStatus.error:
        return _syncError ?? 'Couldn\'t connect to room $room';
      case SyncConnectionStatus.disconnected:
        return 'Disconnected from room $room';
      case SyncConnectionStatus.connected:
        if (_peers.isEmpty) return 'Waiting for a friend to join…';
        return null;
    }
  }
}
