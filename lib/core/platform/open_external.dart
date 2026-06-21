// lib/core/platform/open_external.dart
import 'dart:io';

/// Open [url] in the user's default browser. Best-effort and Windows-targeted:
/// reuses the same `cmd /c start` detach trick the updater uses to launch a
/// process that outlives nothing here — we just need the shell to resolve the
/// default handler. Any failure (non-Windows host, missing shell) is swallowed,
/// so this never throws and never blocks the UI.
Future<void> openExternalUrl(String url) async {
  try {
    await Process.start(
      'cmd',
      ['/c', 'start', '', url],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    // Best-effort: a dead launcher must never disrupt the changelog view.
  }
}
