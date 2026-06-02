import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/meow_context.dart';
import '../core/update/update_service.dart';

/// What the user chose when prompted on close with a downloaded update ready.
enum UpdateCloseChoice { installAndQuit, justQuit, cancel }

/// Intercepts the window-close (X) button so a *downloaded-but-not-installed*
/// update can be applied on the way out instead of re-nagging on next launch
/// (#62). With nothing downloaded, close behaves normally.
///
/// Registered once from `main()` (not the widget tree) so tests that pump the
/// app never touch window plumbing. Holds the app's [navigatorKey] so it can
/// show the confirm dialog over whatever screen is up.
class WindowCloseHandler with WindowListener {
  WindowCloseHandler({
    required this.navigatorKey,
    UpdateService? service,
  }) : _service = service ?? UpdateService.instance;

  final GlobalKey<NavigatorState> navigatorKey;
  final UpdateService _service;

  /// Start intercepting close. Safe to call once after `windowManager`
  /// is initialized.
  Future<void> register() async {
    windowManager.addListener(this);
    // From here EVERY close routes through [onWindowClose]; we must explicitly
    // destroy the window ourselves for a normal quit.
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() => unawaited(handleClose());

  /// The close decision, separated from the listener callback so it can be
  /// awaited/tested. Always ends by either applying the update (which exits the
  /// process) or destroying the window — never leaves the app un-closable,
  /// except the deliberate "cancel" path.
  @visibleForTesting
  Future<void> handleClose() async {
    final zip = _service.downloadedZipPath;
    final ready =
        _service.phase == UpdatePhase.readyToInstall && zip != null;

    if (ready) {
      final ctx = navigatorKey.currentContext;
      // No context to ask in (shouldn't happen in practice) → just quit.
      final choice = ctx != null && ctx.mounted
          ? await showUpdateOnCloseDialog(ctx)
          : UpdateCloseChoice.justQuit;

      if (choice == UpdateCloseChoice.cancel) return; // keep the app open

      if (choice == UpdateCloseChoice.installAndQuit) {
        try {
          // Swaps files and exits the process (no relaunch — we're quitting).
          await _service.applyUpdate(zip, restartAfter: false);
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

/// Modal shown on close when an update is downloaded and ready. Themed to match
/// the app. Returns the user's [UpdateCloseChoice]; a barrier/esc dismissal
/// counts as [UpdateCloseChoice.cancel] (stay open).
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
