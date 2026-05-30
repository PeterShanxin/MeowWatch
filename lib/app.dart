import 'package:flutter/material.dart';

import 'core/connect/room_config.dart';
import 'core/data/settings_store.dart';
import 'core/data/stores.dart';
import 'core/theme/meow_context.dart';
import 'core/theme/meow_theme.dart';
import 'ui/connect/connect_screen.dart';
import 'ui/home_screen.dart';

class MeowWatchApp extends StatefulWidget {
  const MeowWatchApp({
    required this.profiles,
    required this.history,
    required this.settings,
    required this.initialTheme,
    this.initialCardWidthFrac,
    this.initialCardHeightFrac,
    super.key,
  });

  final ProfileStore profiles;
  final HistoryStore history;
  final SettingsStore settings;
  final MeowThemeId initialTheme;
  final double? initialCardWidthFrac;
  final double? initialCardHeightFrac;

  @override
  State<MeowWatchApp> createState() => _MeowWatchAppState();
}

class _MeowWatchAppState extends State<MeowWatchApp> {
  late MeowThemeId _theme = widget.initialTheme;

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
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(_theme),
      home: Builder(
        builder: (context) => ConnectScreen(
          profiles: widget.profiles,
          history: widget.history,
          currentTheme: _theme,
          onThemeChanged: _setTheme,
          onConnect: (RoomConfig config) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HomeScreen(
                config: config,
                history: widget.history,
                settings: widget.settings,
                initialWidthFrac: widget.initialCardWidthFrac,
                initialHeightFrac: widget.initialCardHeightFrac,
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
