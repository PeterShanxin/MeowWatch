// lib/core/platform/open_external.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Signature for the low-level URL launch. Swapped out in tests so the suite
/// never spawns a real browser tab.
typedef UrlLauncher = Future<void> Function(String url);

/// Command used to open [url] in the desktop's default handler.
({String executable, List<String> arguments}) externalUrlProcess(
  String url, {
  required bool isWindows,
}) {
  if (isWindows) {
    return (executable: 'cmd', arguments: ['/c', 'start', '', url]);
  }
  return (executable: 'xdg-open', arguments: [url]);
}

/// Real launcher: `cmd /c start` on Windows, `xdg-open` on Linux.
Future<void> _spawnViaShell(String url) {
  final launch = externalUrlProcess(url, isWindows: Platform.isWindows);
  return Process.start(
    launch.executable,
    launch.arguments,
    mode: ProcessStartMode.detached,
  );
}

/// Test seam. When non-null, [openExternalUrl] calls this instead of really
/// shelling out — so widget/unit tests cannot pop a browser tab. Production
/// leaves it null and uses [_spawnViaShell].
@visibleForTesting
UrlLauncher? debugUrlLauncherOverride;

/// Open [url] in the user's default browser. Best-effort.
/// Any failure (missing shell) is swallowed, so this never throws and never
/// blocks the UI.
Future<void> openExternalUrl(String url) async {
  try {
    await (debugUrlLauncherOverride ?? _spawnViaShell)(url);
  } catch (_) {
    // Best-effort: a dead launcher must never disrupt the changelog view.
  }
}
