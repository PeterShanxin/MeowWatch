import '../core/sync/peer_state.dart';
import 'connect/history_format.dart';

/// The two strings for a sync activity: an emoji banner over the video and a
/// plain dim line in chat history.
class SyncActivityText {
  const SyncActivityText({required this.banner, required this.chatLine});
  final String banner;
  final String chatLine;
}

/// Build the banner + chat strings for a peer [SyncActivity]. Pure so the
/// wording/edge cases are unit-testable without a widget pump.
SyncActivityText syncActivityText(SyncActivity a) {
  final at = formatRuntime(a.position.inMilliseconds);
  final user = a.username;
  switch (a.kind) {
    case SyncActivityKind.paused:
      return SyncActivityText(
        banner: '⏸ $user paused at $at',
        chatLine: '$user paused at $at',
      );
    case SyncActivityKind.played:
      return SyncActivityText(
        banner: '▶ $user resumed',
        chatLine: '$user resumed',
      );
    case SyncActivityKind.seekedForward:
      return SyncActivityText(
        banner: '⏩ $user skipped to $at',
        chatLine: '$user skipped to $at',
      );
    case SyncActivityKind.seekedBack:
      return SyncActivityText(
        banner: '⏪ $user jumped back to $at',
        chatLine: '$user jumped back to $at',
      );
  }
}
