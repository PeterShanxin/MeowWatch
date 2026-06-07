import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/update/update_service.dart';
import 'app_close_hook.dart';

/// What the user chose when prompted on close with a downloaded update ready.
enum UpdateCloseChoice { installAndQuit, justQuit, cancel }

/// Intercepts the window-close (X) button when either a downloaded-but-not-
/// installed update is waiting (#62) or a room is active (#92) — the former so
/// the update can be applied on the way out, the latter so we can announce a
/// deliberate leave before the socket dies (otherwise peers see "lost
/// connection" instead of "left the room").
///
/// `preventClose` is toggled on *only* while one of those holds and off
/// otherwise — so an idle quit still closes instantly through the OS path with
/// no Dart in it (an earlier always-on version made every close slow and could
/// wedge a playing window). The in-room leave-announce is bounded (see
/// [runAppCloseHook]) so it can't wedge the quit. Registered once from `main()`,
/// not the widget tree, so tests that pump the app never touch window plumbing.
class WindowCloseHandler with WindowListener {
  WindowCloseHandler({
    required this.navigatorKey,
    UpdateService? service,
    Future<void> Function()? destroyWindow,
  })  : _service = service ?? UpdateService.instance,
        _destroyWindow = destroyWindow ?? windowManager.destroy;

  final GlobalKey<NavigatorState> navigatorKey;
  final UpdateService _service;

  /// How the window is torn down — `windowManager.destroy` in production,
  /// injectable in tests (the real call hangs without platform plumbing).
  final Future<void> Function() _destroyWindow;

  bool _preventing = false;

  /// Start watching for a ready update / active room and intercepting close
  /// while either waits.
  void register() {
    windowManager.addListener(this);
    _service.addListener(_syncPreventClose);
    appCloseHook.addListener(_syncPreventClose);
    _syncPreventClose();
  }

  bool get _updateReady =>
      _service.phase == UpdatePhase.readyToInstall &&
      _service.downloadedZipPath != null;

  /// Prevent close only while an update is ready or a room is active; otherwise
  /// let the OS close the window normally (fast, no Dart in the path).
  void _syncPreventClose() {
    final shouldPrevent = _updateReady || appCloseHook.value != null;
    if (shouldPrevent == _preventing) return;
    _preventing = shouldPrevent;
    unawaited(windowManager.setPreventClose(shouldPrevent));
  }

  @override
  void onWindowClose() => unawaited(handleClose());

  /// Reached only while close is prevented (an update is ready, or a room is
  /// active). Offers to install a waiting update on the way out, then announces a
  /// deliberate leave to the room before exiting; always ends by applying the
  /// update (which exits the process) or destroying the window — never traps the
  /// user, except the deliberate "cancel" path.
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
          // Tell the room we're leaving before the process exits (#92).
          await runAppCloseHook();
          await _service.applyUpdate(zip, restartAfter: false); // exits
          return;
        } catch (e, st) {
          // Any failure (bad zip, checksum, IO) — log it for diagnosis, then
          // fall through to a plain quit rather than trapping the user in an
          // un-closable window.
          debugPrint('apply-on-close failed: $e\n$st');
        }
      }
    }

    // Announce a deliberate leave (if in a room) before tearing the window down,
    // so peers see "left the room" rather than "lost connection" (#92).
    await runAppCloseHook();
    await _destroyWindow();
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
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: m.border),
        ),
        title: Row(
          children: [
            Icon(Icons.system_update, color: m.accent, size: IconSizes.md),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Install update before closing?',
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: TypeScale.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'An update is downloaded and ready. Install it now so you start up '
          'on the new version next time?',
          style: TextStyle(color: m.textDim, fontSize: TypeScale.body),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
            Spacing.lg, 0, Spacing.lg, Spacing.md),
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
            borderRadius: BorderRadius.circular(Radii.lg),
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
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Text(
                  'Installing update…\nThe app will close in a moment.',
                  style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
