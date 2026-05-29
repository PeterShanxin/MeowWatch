import 'video_core.dart';

/// Seek [core] to [target] once the media is open and its duration is known.
///
/// media_kit drops a seek issued before the media is open and its duration is
/// known — the file would just start at 0. So we wait (bounded by [timeout])
/// for the first non-zero duration, then seek. A non-positive [target] is a
/// no-op (nothing to resume to).
Future<void> seekWhenReady(
  VideoCore core,
  Duration target, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (target <= Duration.zero) return;
  if (core.state.duration <= Duration.zero) {
    await core.stateStream
        .firstWhere((s) => s.duration > Duration.zero)
        .timeout(timeout, onTimeout: () => core.state);
  }
  await core.seek(target);
}
