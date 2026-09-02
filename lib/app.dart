import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/connect/room_config.dart';
import 'core/connect/room_share.dart';
import 'core/data/settings_store.dart';
import 'core/data/stores.dart';
import 'core/debug/app_log.dart';
import 'core/debug/log_level.dart';
import 'core/sync/endpoint_discovery.dart';
import 'core/sync/peer_state.dart';
import 'core/sync/syncplay_client.dart';
import 'core/sync/syncplay_endpoints.dart';
import 'core/theme/meow_context.dart';
import 'core/theme/meow_theme.dart';
import 'core/theme/reduce_motion.dart';
import 'core/theme/tokens/motion.dart';
import 'core/update/update_service.dart';
import 'ui/chat/chat_corner.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';
import 'ui/launch/launch_reveal.dart';
import 'ui/motion/fade_up_route.dart';
import 'ui/whats_new_dialog.dart';

class MeowWatchApp extends StatefulWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    required this.settings,
    required this.initialTheme,
    this.initialCardWidthPx,
    this.initialCardHeightPx,
    this.initialChatCorner,
    this.navigatorKey,
    this.showWhatsNew = false,
    this.whatsNewEntries = const <ChangelogEntry>[],
    this.showLaunchReveal = true,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final SettingsStore settings;
  final MeowThemeId initialTheme;
  final double? initialCardWidthPx;
  final double? initialCardHeightPx;

  /// The chat card's persisted docked corner; null falls back to the default.
  final ChatCorner? initialChatCorner;

  /// Optional navigator key so the apply-on-close handler can show its confirm
  /// dialog over the live route (#62). Null in tests.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// When true (and [whatsNewEntries] is non-empty), the post-update "what's
  /// new" modal is shown once after the first frame. Decided in `main` from the
  /// persisted last-seen version (see [shouldShowWhatsNew]).
  final bool showWhatsNew;

  /// Every version installed since the user last opened the app, newest first,
  /// to show in that modal (hero + collapsible "Earlier updates").
  final List<ChangelogEntry> whatsNewEntries;

  /// Whether to play the cold-start launch reveal over the lobby. True in
  /// production; false in tests that drive the lobby / What's-new directly.
  final bool showLaunchReveal;

  @override
  State<MeowWatchApp> createState() => _MeowWatchAppState();
}

class _MeowWatchAppState extends State<MeowWatchApp> {
  late MeowThemeId _theme = widget.initialTheme;

  /// Reuse the caller's navigator key when given (so the close handler shares
  /// it); otherwise make our own so the post-update modal still has a navigator
  /// context to show over (e.g. in tests).
  late final GlobalKey<NavigatorState> _navKey =
      widget.navigatorKey ?? GlobalKey<NavigatorState>();

  bool _whatsNewShown = false;
  bool _revealSettled = false;

  /// Show the post-update "What's new" modal — but only once the launch reveal
  /// has settled, so it no longer pops over the animation (it used to fire from
  /// initState, on top of the splash). Called by [LaunchReveal.onComplete],
  /// which fires after the reveal (or, when the reveal is disabled / reduce
  /// motion is on, after the first frame).
  void _onRevealComplete() {
    if (!_revealSettled) setState(() => _revealSettled = true);
    if (_whatsNewShown) return;
    _whatsNewShown = true;
    final entries = widget.whatsNewEntries;
    if (!widget.showWhatsNew || entries.isEmpty) return;
    final context = _navKey.currentContext;
    if (context != null) WhatsNewDialog.show(context, entries);
  }

  void _setTheme(MeowThemeId id) {
    if (id == _theme) return;
    setState(() => _theme = id);
    // Fire-and-forget persistence; UI already updated.
    widget.settings.set(kThemeSettingKey, id.name);
  }

  /// Stay on the lobby until a synced Start/Join login completes. A refused
  /// join returns the named error; the watch route is only pushed after a
  /// completed Hello (#265). Local Start skips Syncplay. Continue Watching
  /// restores the saved position before HomeScreen dials so the room cannot
  /// be overwritten with 0:00 (#254).
  /// [connectUntilJoin] keeps listening through this handoff so a Hello-then-
  /// Error is not dropped by the broadcast stream before [HomeScreen] attaches.
  Future<String?> _joinAndOpenRoom(RoomConfig config) async {
    BuildContext? navContext() {
      final context = _navKey.currentContext;
      return (context != null && context.mounted) ? context : null;
    }

    Future<String?> pushWatch({SyncplayClient? sync, RoomConfig? joined}) {
      final context = navContext();
      if (context == null) {
        return Future<String?>.value(null);
      }
      return Navigator.of(context).push<String>(
        fadeUpRoute<String>(
          reduceMotion: context.reduceMotion,
          // A builder, not a captured widget, so the room page rebuilds
          // with the latest [_theme] when the in-room gear switches theme
          // (the swatch highlight tracks it) — see [fadeUpRoute].
          builder: (_) => HomeScreen(
            config: joined ?? config,
            sync: sync,
            history: widget.history,
            settings: widget.settings,
            initialWidthPx: widget.initialCardWidthPx,
            initialHeightPx: widget.initialCardHeightPx,
            initialCorner: widget.initialChatCorner,
            currentTheme: _theme,
            onThemeChanged: _setTheme,
          ),
        ),
      );
    }

    if (config.sessionMode.isLocal || config.resumeFilePath != null) {
      return pushWatch();
    }

    final pinned =
        config.endpointPolicy == SyncplayEndpointPolicy.pinned ||
        !isPublicSyncplayCandidate(
          SyncplayEndpoint(host: config.server, port: config.port),
        );
    if (pinned) {
      return _joinPinned(
        config: config,
        pushWatch: pushWatch,
        navContext: navContext,
      );
    }
    return _joinDiscovering(
      config: config,
      pushWatch: pushWatch,
      navContext: navContext,
    );
  }

  SyncplayClient _newSyncplayClient() {
    return SyncplayClient(
      onLog: appLog,
      shouldLog: ({required bool verboseOnly}) {
        final level = appLogInstance?.level;
        return level == LogLevel.verbose ||
            (!verboseOnly && level == LogLevel.neat);
      },
    );
  }

  Future<String?> _joinPinned({
    required RoomConfig config,
    required Future<String?> Function({
      SyncplayClient? sync,
      RoomConfig? joined,
    })
    pushWatch,
    required BuildContext? Function() navContext,
  }) async {
    final client = _newSyncplayClient();
    Future<String?>? watchRoute;
    final error = await client.connectUntilJoin(
      server: config.server,
      port: config.port,
      username: config.username,
      room: config.room,
      password: config.password,
      onHandoff: () => _handoffJoined(
        client: client,
        config: config,
        pushWatch: pushWatch,
        navContext: navContext,
        setWatchRoute: (route) => watchRoute = route,
      ),
    );
    return _finishJoin(client: client, error: error, watchRoute: watchRoute);
  }

  Future<String?> _joinDiscovering({
    required RoomConfig config,
    required Future<String?> Function({
      SyncplayClient? sync,
      RoomConfig? joined,
    })
    pushWatch,
    required BuildContext? Function() navContext,
  }) async {
    Future<String?>? watchRoute;
    final outcome = await joinFirstWorkingEndpoint(
      config: config,
      settings: widget.settings,
      createClient: _newSyncplayClient,
      onLog: appLog,
      connectUntilJoin: (client, endpoint) {
        return client.connectUntilJoin(
          server: endpoint.host,
          port: endpoint.port,
          username: config.username,
          room: config.room,
          password: config.password,
          onHandoff: () => _handoffJoined(
            client: client,
            config: config.copyWith(server: endpoint.host, port: endpoint.port),
            pushWatch: pushWatch,
            navContext: navContext,
            setWatchRoute: (route) => watchRoute = route,
          ),
        );
      },
    );
    if (outcome.join != null) {
      return _finishJoin(
        client: outcome.join!.client,
        error: null,
        watchRoute: watchRoute,
      );
    }
    if (outcome.retainedClient != null) {
      return _finishJoin(
        client: outcome.retainedClient!,
        error: outcome.error,
        watchRoute: watchRoute,
      );
    }
    return outcome.error;
  }

  Future<void> _handoffJoined({
    required SyncplayClient client,
    required RoomConfig config,
    required Future<String?> Function({
      SyncplayClient? sync,
      RoomConfig? joined,
    })
    pushWatch,
    required BuildContext? Function() navContext,
    required void Function(Future<String?> route) setWatchRoute,
  }) async {
    // Use the navigator key, not a Builder context captured at lobby
    // build: a theme change (or any MeowWatchApp setState) replaces
    // that Builder while the join is still in flight.
    final context = navContext();
    if (context == null) {
      await client.dispose();
      return;
    }
    await widget.profiles.saveUsed(
      name: config.room,
      server: config.server,
      port: config.port,
      room: config.room,
      username: config.username,
      password: config.password,
    );
    if (config.copyShareCode) {
      final share = encodeShareCode(
        room: config.room,
        server: config.server,
        port: config.port,
      );
      Clipboard.setData(ClipboardData(text: share)).ignore();
      if (context.mounted) showCopiedRoomCodeSnack(context, share);
    }
    // Don't await the route here: connectUntilJoin must keep listening
    // only until HomeScreen's subscriptions exist, not until Leave.
    setWatchRoute(pushWatch(sync: client, joined: config));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<String?> _finishJoin({
    required SyncplayClient client,
    required String? error,
    required Future<String?>? watchRoute,
  }) async {
    final terminal =
        error ??
        (client.lastConnectionState?.status == SyncConnectionStatus.error
            ? client.lastConnectionState?.message
            : null);
    if (terminal != null) {
      final context = _navKey.currentContext;
      if (watchRoute != null &&
          context != null &&
          context.mounted &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop(terminal);
      } else {
        await client.dispose();
      }
      return terminal;
    }
    if (watchRoute == null) {
      await client.dispose();
      return null;
    }
    return watchRoute;
  }

  @override
  Widget build(BuildContext context) {
    // OS "reduce animations" makes the app-level theme melt instant, matching
    // every other motion primitive (and the gallery's AnimatedTheme). Read it
    // non-throwing: this context sits above MaterialApp, so a MediaQuery may be
    // absent (`context.reduceMotion` would assert). Mirrors that getter's logic.
    final reduceMotion =
        ReduceMotionScope.of(context) ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    return MaterialApp(
      title: 'MeowWatch',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(_theme),
      themeAnimationDuration: reduceMotion ? Duration.zero : Motion.slow,
      themeAnimationCurve: Motion.emphasized,
      home: Builder(
        builder: (context) => LaunchReveal(
          enabled: widget.showLaunchReveal,
          onComplete: _onRevealComplete,
          child: ConnectScreen(
            profiles: widget.profiles,
            history: widget.history,
            settings: widget.settings,
            currentTheme: _theme,
            onThemeChanged: _setTheme,
            playLobbyEntrance: widget.showLaunchReveal && _revealSettled,
            holdLobbyHidden: widget.showLaunchReveal && !_revealSettled,
            onConnect: (RoomConfig config) => _joinAndOpenRoom(config),
          ),
        ),
      ),
    );
  }
}
