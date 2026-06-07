import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/data/app_database.dart';
import 'core/data/drift_stores.dart';
import 'core/data/settings_store.dart';
import 'core/theme/meow_theme.dart';
import 'ui/chat/chat_overlay_layout.dart';
import 'ui/gallery/design_gallery.dart';
import 'ui/window_close_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final db = await openAppDatabase();
  final settings = DriftSettingsStore(db);
  final savedTheme = MeowThemeId.fromName(await settings.get(kThemeSettingKey));
  final (cardW, cardH) =
      parseCardSize(await settings.get(kChatCardSizeSettingKey));

  // Lets the apply-on-close handler show its confirm dialog over the live route.
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(MeowWatchApp(
    profiles: DriftProfileStore(db),
    history: DriftHistoryStore(db),
    settings: settings,
    initialTheme: savedTheme,
    initialCardWidthPx: cardW,
    initialCardHeightPx: cardH,
    navigatorKey: navigatorKey,
  ));

  // Intercept the window-close button so a downloaded update can be applied on
  // the way out instead of re-prompting next launch (#62).
  WindowCloseHandler(navigatorKey: navigatorKey).register();

  // Raise our window on launch. The auto-updater relaunches us from a hidden
  // PowerShell process, and Windows' foreground-lock then blocks the new window
  // from raising itself, so it lands behind other windows. Run after the first
  // frame so the native window exists.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(bringToFront()));

  // Backup door to the hidden design gallery (the primary entry is a long-press
  // on the version badge). Lets us open it on a real install without the badge.
  if (Platform.environment['MEOWWATCH_GALLERY'] == '1') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const DesignGallery()),
      );
    });
  }
}

/// Bring the window to the foreground without needing foreground rights.
///
/// The `alwaysOnTop` true→false bump raises via `HWND_TOPMOST` (`SetWindowPos`),
/// which lifts a window above others even when the OS would refuse a plain
/// `focus()` (the updater relaunches us from a background process, so Windows'
/// foreground-lock applies). Releasing topmost immediately means we don't pin
/// over the user's other apps. Invisible on a normal launch (already in front),
/// decisive on an updater relaunch.
Future<void> bringToFront() async {
  await windowManager.show();
  await windowManager.setAlwaysOnTop(true);
  await windowManager.focus();
  await windowManager.setAlwaysOnTop(false);
}
