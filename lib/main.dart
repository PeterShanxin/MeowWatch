import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_version.dart';
import 'core/data/app_database.dart';
import 'core/data/drift_stores.dart';
import 'core/data/settings_store.dart';
import 'core/debug/app_log.dart';
import 'core/debug/debug_log.dart';
import 'core/debug/error_log.dart';
import 'core/debug/log_archive.dart';
import 'core/debug/log_level.dart';
import 'core/debug/startup_env.dart';
import 'core/theme/meow_theme.dart';
import 'core/update/changelog_file.dart';
import 'core/update/update_service.dart';
import 'core/update/whats_new_gate.dart';
import 'ui/chat/chat_overlay_layout.dart';
import 'ui/gallery/design_gallery.dart';
import 'ui/window_close_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final db = await openAppDatabase();
  final settings = DriftSettingsStore(db);
  final profiles = DriftProfileStore(db);
  final history = DriftHistoryStore(db);

  // Open the process-wide diagnostic log before any UI runs so it captures the
  // whole app run — lobby, every room, video, updates — not just one room's
  // Syncplay traffic (#140). Best-effort: a missing log dir leaves it null and
  // every `appLog` call simply no-ops, so startup is never blocked.
  await _initAppLog(settings);

  // Route framework + async errors that would otherwise only hit stderr (unseen
  // in a Release build) into the session log, so a crash/freeze leaves a trace
  // the exported log can diagnose (#156). Installed right after the log so the
  // rest of startup and the whole UI run are covered.
  _installErrorHandlers();

  final savedTheme = MeowThemeId.fromName(await settings.get(kThemeSettingKey));
  final (cardW, cardH) =
      parseCardSize(await settings.get(kChatCardSizeSettingKey));

  // Stamp the run with its environment (OS, window, locale, log path, settings)
  // so environment-specific reports can be confirmed from the log alone (#156).
  await _logStartupEnv(theme: savedTheme, cardW: cardW, cardH: cardH);

  // One-time post-update "what's new" modal: show when the recorded last-seen
  // version differs from this build (the user updated), or when forced via the
  // MEOWWATCH_WHATS_NEW backdoor (mirrors the gallery door). Record the current
  // version every launch so the modal fires at most once per bump.
  //
  // Backdoor values: '1' forces the modal using the real last-seen version; any
  // other non-empty value (e.g. '0.28.0-alpha') is treated as a pretend
  // last-seen, so the multi-version catch-up can be demoed/tested on any install
  // without an actual update history.
  final storedLastSeen = await settings.get(kLastSeenVersionKey);
  final backdoor = Platform.environment['MEOWWATCH_WHATS_NEW'];
  final forced = backdoor != null && backdoor.isNotEmpty;
  // No recorded version means either a fresh install or an existing user
  // upgrading from a build before this key existed. Only the latter should see
  // the modal that ships the feature, so distinguish them by whether the DB
  // already holds the user's data — saved profiles, watch history, or any
  // changed setting (a settings-only user counts as an existing install too).
  final hasPriorInstall = storedLastSeen == null &&
      (await settings.hasAnySettings() ||
          (await profiles.watchProfiles().first).isNotEmpty ||
          (await history.watchRecent(limit: 1).first).isNotEmpty);
  final effectiveLastSeen =
      (forced && backdoor != '1') ? backdoor : storedLastSeen;
  final showWhatsNew = shouldShowWhatsNew(
        lastSeen: storedLastSeen,
        current: appVersion,
        hasPriorInstall: hasPriorInstall,
      ) ||
      forced;
  if (storedLastSeen != appVersion) {
    unawaited(settings.set(kLastSeenVersionKey, appVersion));
  }
  final whatsNewEntries = showWhatsNew
      ? await _loadWhatsNewEntries(effectiveLastSeen)
      : const <ChangelogEntry>[];

  // Lets the apply-on-close handler show its confirm dialog over the live route.
  final navigatorKey = GlobalKey<NavigatorState>();

  runApp(MeowWatchApp(
    profiles: profiles,
    history: history,
    settings: settings,
    initialTheme: savedTheme,
    initialCardWidthPx: cardW,
    initialCardHeightPx: cardH,
    navigatorKey: navigatorKey,
    showWhatsNew: showWhatsNew,
    whatsNewEntries: whatsNewEntries,
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

/// Load every version installed since [lastSeen] (up to this build) from the
/// bundled `CHANGELOG.md`, so the post-update modal shows the full catch-up
/// instantly and offline — no dependence on R2 having published these notes
/// yet. Returns an empty list on any failure (asset missing, no entries), in
/// which case the modal is simply skipped.
Future<List<ChangelogEntry>> _loadWhatsNewEntries(String? lastSeen) async {
  try {
    final md = await rootBundle.loadString('CHANGELOG.md');
    return entriesForWhatsNew(
      parseChangelogFile(md),
      lastSeen: lastSeen,
      current: appVersion,
    );
  } catch (_) {
    return const <ChangelogEntry>[];
  }
}

/// Build and install the process-wide rotating session log at the persisted
/// level (default verbose), then stamp the run's first line. One file per app
/// run; the level can be changed live from either screen's gear menu. Wrapped so
/// a missing app-support dir or platform plugin can never block startup — on any
/// failure the log stays uninstalled and diagnostics are simply off.
Future<void> _initAppLog(SettingsStore settings) async {
  final level = logLevelFromName(await settings.get(kLogLevelSettingKey));
  try {
    final dir = await resolveAppLogsDir();
    // retain: 8 — one file per app run now covers the whole app (not just one
    // room's sync traffic), so each file is larger; keep a few fewer runs on
    // disk (#140 volume lever).
    final log = DebugLog.inDir(
      dir,
      baseName: 'meowwatch_sync',
      retain: 8,
      level: level,
    )..start();
    installAppLog(log);
    // The run header (version + environment) is stamped by [_logStartupEnv]
    // once the window and settings are available.
  } on Object {
    // No log dir available — diagnostics off, app unaffected.
  }
}

/// Forward otherwise-uncaught errors to the session log. [FlutterError.onError]
/// catches synchronous framework/build errors (still presented to the console
/// for debug runs); [PlatformDispatcher.onError] catches async errors that
/// escape a callback. Both lines are URL-redacted and neat-kept (#156). We do
/// not wrap `runApp` in a guarded zone — these two handlers cover the cases
/// that matter without risking a binding/zone mismatch.
void _installErrorHandlers() {
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    priorOnError?.call(details); // keep the default console presentation
    appLog(errorLogLine('flutter', details.exceptionAsString(), details.stack));
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    appLog(errorLogLine('uncaught', error, stack));
    return true; // logged; keep the app alive rather than tearing down
  };
}

/// Build and log the run's environment header. Best-effort: any failure to read
/// the window size or platform info simply omits the header — it must never
/// block or crash startup.
Future<void> _logStartupEnv({
  required MeowThemeId theme,
  required double? cardW,
  required double? cardH,
}) async {
  try {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final size = await windowManager.getSize();
    for (final line in startupEnvLines(
      version: appVersion,
      os: Platform.operatingSystemVersion,
      logPath: appLogInstance?.path ?? '(none)',
      window: '${size.width.round()}x${size.height.round()}',
      dpr: dispatcher.implicitView?.devicePixelRatio ?? 1.0,
      locale: dispatcher.locale.toString(),
      theme: theme.name,
      cardSize: '${cardW?.round() ?? '?'}x${cardH?.round() ?? '?'}',
      logLevel: appLogInstance?.level.storageName ?? LogLevel.off.storageName,
    )) {
      appLog(line);
    }
  } on Object {
    // Window/platform info unavailable — header skipped, app unaffected.
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
