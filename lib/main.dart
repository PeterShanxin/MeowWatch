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
