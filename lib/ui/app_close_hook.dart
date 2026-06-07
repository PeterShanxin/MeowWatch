import 'package:flutter/foundation.dart';

/// Async action run on window close *before* the window is destroyed — used to
/// announce a deliberate leave to the room so peers see "left the room" instead
/// of "lost connection" (#92 follow-up). Null when not in a room.
///
/// A normal window-close (X) takes the OS fast-path and never runs Dart cleanup,
/// so `dispose()` can't be relied on to send the leave signal. The close handler
/// invokes this hook explicitly. It's a [ValueNotifier] so the handler can flip
/// `preventClose` on whenever a hook is registered (otherwise the OS would close
/// the window before the hook could run).
final ValueNotifier<Future<void> Function()?> appCloseHook =
    ValueNotifier<Future<void> Function()?>(null);

/// Run the registered close hook (if any), bounded by [timeout] so a wedged or
/// half-open socket can never trap the quit. Safe to call with no hook set; a
/// hook that throws or times out is swallowed — closing must always proceed.
Future<void> runAppCloseHook({
  Duration timeout = const Duration(seconds: 1),
}) async {
  final hook = appCloseHook.value;
  if (hook == null) return;
  try {
    await hook().timeout(timeout);
  } catch (_) {}
}
