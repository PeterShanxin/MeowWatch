import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/settings_store.dart';
import 'core/data/stores.dart';
import 'core/theme/meow_context.dart';
import 'core/theme/meow_theme.dart';
import 'core/update/update_service.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';
import 'ui/whats_new_dialog.dart';

class MeowWatchApp extends StatefulWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    required this.settings,
    required this.initialTheme,
    this.initialCardWidthPx,
    this.initialCardHeightPx,
    this.navigatorKey,
    this.showWhatsNew = false,
    this.whatsNewEntries = const <ChangelogEntry>[],
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final SettingsStore settings;
  final MeowThemeId initialTheme;
  final double? initialCardWidthPx;
  final double? initialCardHeightPx;

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

  @override
  void initState() {
    super.initState();
    final entries = widget.whatsNewEntries;
    if (widget.showWhatsNew && entries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navKey.currentContext;
        if (context != null) WhatsNewDialog.show(context, entries);
      });
    }
  }

  void _setTheme(MeowThemeId id) {
    if (id == _theme) return;
    setState(() => _theme = id);
    // Fire-and-forget persistence; UI already updated.
    widget.settings.set(kThemeSettingKey, id.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeowWatch',
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(_theme),
      home: Builder(
        builder: (context) => ConnectScreen(
          profiles: widget.profiles,
          history: widget.history,
          settings: widget.settings,
          currentTheme: _theme,
          onThemeChanged: _setTheme,
          onConnect: (RoomConfig config) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeScreen(
                config: config,
                history: widget.history,
                settings: widget.settings,
                initialWidthPx: widget.initialCardWidthPx,
                initialHeightPx: widget.initialCardHeightPx,
                currentTheme: _theme,
                onThemeChanged: _setTheme,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
