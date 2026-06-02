import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/meow_context.dart';
import '../core/update/update_service.dart';

/// What the user chose when prompted on close with a downloaded update ready.
enum UpdateCloseChoice { installAndQuit, justQuit, cancel }

/// Intercepts the window-close (X) button **only when a downloaded-but-not-
/// installed update is waiting** (#62), so it can be applied on the way out
/// instead of re-nagging next launch.
///
/// Crucially, `preventClose` is toggled on *only* while an update is ready and
/// off otherwise — so a normal quit closes instantly through the OS path and is
/// never routed through Dart (an earlier always-on version made every close slow
/// and could wedge a playing window). Registered once from `main()`, not the
/// widget tree, so tests that pump the app never touch window plumbing.
class WindowCloseHandler with WindowListener {
  WindowCloseHandler({
    required this.navigatorKey,
    UpdateService? service,
  }) : _service = service ?? UpdateService.instance;

  final GlobalKey<NavigatorState> navigatorKey;
  final UpdateService _service;

  bool _preventing = false;

  /// Start watching for a ready update and intercepting close while one waits.
  void register() {
    windowManager.addListener(this);
    _service.addListener(_syncPreventClose);
    _syncPreventClose();
  }

  bool get _updateReady =>
      _service.phase == UpdatePhase.readyToInstall &&
      _service.downloadedZipPath != null;

  /// Prevent close only while an update is ready; otherwise let the OS close the
  /// window normally (fast, no Dart in the path).
  void _syncPreventClose() {
    final shouldPrevent = _updateReady;
    if (shouldPrevent == _preventing) return;
    _preventing = shouldPrevent;
    unawaited(windowManager.setPreventClose(shouldPrevent));
  }

  @override
  void onWindowClose() => unawaited(handleClose());

  /// Reached only while close is prevented (an update is ready). Offers to
  /// install on the way out; always ends by applying the update (which exits the
  /// process) or destroying the window — never traps the user, except the
  /// deliberate "cancel" path.
  @visibleForTesting
  Future<void> handleClose() async {
    final zip = _service.downloadedZipPath;
    if (_updateReady && zip != null) {
      final ctx = navigatorKey.currentContext;
      final choice = ctx != null && ctx.mounted
          ? await showUpdateOnCloseDialog(ctx)
          : UpdateCloseChoice.justQuit;

      if (choice == UpdateCloseChoice.cancel) return; // keep the app open

      if (choice == UpdateCloseChoice.installAndQuit) {
        try {
          // Show a blocking "installing…" modal so the file swap (a few seconds
          // of sync I/O before the process exits) doesn't read as a frozen
          // window. Don't await it — it never pops; applyUpdate exits under it.
          final modalCtx = navigatorKey.currentContext;
          if (modalCtx != null && modalCtx.mounted) {
            unawaited(showInstallingUpdateDialog(modalCtx));
            // Let the modal paint a frame before the synchronous unzip blocks
            // the UI isolate.
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          await _service.applyUpdate(zip, restartAfter: false); // exits
          return;
        } catch (_) {
          // Any failure (bad zip, checksum, IO) — fall through to a plain quit
          // rather than trapping the user in an un-closable window.
        }
      }
    }

    await windowManager.destroy();
  }
}

/// Modal shown on close when an update is downloaded and ready. Returns the
/// user's [UpdateCloseChoice]; a barrier/esc dismissal counts as
/// [UpdateCloseChoice.cancel] (stay open).
Future<UpdateCloseChoice> showUpdateOnCloseDialog(BuildContext context) async {
  final result = await showDialog<UpdateCloseChoice>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final m = context.meow;
      return AlertDialog(
        backgroundColor: m.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: m.border),
        ),
        title: Row(
          children: [
            Icon(Icons.system_update, color: m.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Install update before closing?',
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'An update is downloaded and ready. Install it now so you start up '
          'on the new version next time?',
          style: TextStyle(color: m.textDim, fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UpdateCloseChoice.justQuit),
            child: Text('Just quit', style: TextStyle(color: m.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: m.accent,
              foregroundColor: m.background,
            ),
            onPressed: () =>
                Navigator.of(context).pop(UpdateCloseChoice.installAndQuit),
            child: const Text('Install & quit'),
          ),
        ],
      );
    },
  );
  return result ?? UpdateCloseChoice.cancel;
}

/// Non-dismissible "installing the update…" modal shown while the files are
/// swapped on close, so the brief pause before the app exits doesn't look like
/// a hang. It is never dismissed in code — the process exits under it.
Future<void> showInstallingUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final m = context.meow;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: m.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: m.border),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: m.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Installing update…\nThe app will close in a moment.',
                  style: TextStyle(color: m.textPrimary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
