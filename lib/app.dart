import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/settings_store.dart';
import 'core/data/stores.dart';
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

  @override
  Widget build(BuildContext context) {
    // OS "reduce animations" makes the app-level theme melt instant, matching
    // every other motion primitive (and the gallery's AnimatedTheme). Read it
    // non-throwing: this context sits above MaterialApp, so a MediaQuery may be
    // absent (`context.reduceMotion` would assert). Mirrors that getter's logic.
    final reduceMotion = ReduceMotionScope.of(context) ||
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
            onConnect: (RoomConfig config) => Navigator.of(context).push<String>(
              fadeUpRoute<String>(
                reduceMotion: context.reduceMotion,
                // A builder, not a captured widget, so the room page rebuilds
                // with the latest [_theme] when the in-room gear switches theme
                // (the swatch highlight tracks it) — see [fadeUpRoute].
                builder: (_) => HomeScreen(
                  config: config,
                  history: widget.history,
                  settings: widget.settings,
                  initialWidthPx: widget.initialCardWidthPx,
                  initialHeightPx: widget.initialCardHeightPx,
                  initialCorner: widget.initialChatCorner,
                  currentTheme: _theme,
                  onThemeChanged: _setTheme,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
