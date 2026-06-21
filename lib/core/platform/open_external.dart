// lib/core/platform/open_external.dart
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Signature for the low-level URL launch. Swapped out in tests so the suite
/// never spawns a real browser tab.
typedef UrlLauncher = Future<void> Function(String url);

/// Real launcher: the `cmd /c start` detach trick the updater uses — we just
/// need the shell to resolve the default handler for [url].
Future<void> _spawnViaShell(String url) => Process.start(
      'cmd',
      ['/c', 'start', '', url],
      mode: ProcessStartMode.detached,
    );

/// Test seam. When non-null, [openExternalUrl] calls this instead of really
/// shelling out — so widget/unit tests cannot pop a browser tab. Production
/// leaves it null and uses [_spawnViaShell].
@visibleForTesting
UrlLauncher? debugUrlLauncherOverride;

/// Open [url] in the user's default browser. Best-effort and Windows-targeted.
/// Any failure (non-Windows host, missing shell) is swallowed, so this never
/// throws and never blocks the UI.
Future<void> openExternalUrl(String url) async {
  try {
    await (debugUrlLauncherOverride ?? _spawnViaShell)(url);
  } catch (_) {
    // Best-effort: a dead launcher must never disrupt the changelog view.
  }
}
