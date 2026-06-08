import '../core/sync/peer_state.dart';
import 'connect/history_format.dart';

/// The two strings for a sync activity: an emoji banner over the video and a
/// plain dim line in chat history.
class SyncActivityText {
  const SyncActivityText({required this.banner, required this.chatLine});
  final String banner;
  final String chatLine;
}

/// Build the banner + chat strings for a [SyncActivity]. Pure so the
/// wording/edge cases are unit-testable without a widget pump.
///
/// When [selfUsername] matches the activity's user, the actor is rendered as
/// "You" — our own actions (issue #27) read naturally on our own screen instead
/// of echoing our own name back at us.
SyncActivityText syncActivityText(SyncActivity a, {String? selfUsername}) {
  final at = formatRuntime(a.position.inMilliseconds);
  final user = a.username == selfUsername ? 'You' : a.username;
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
    case SyncActivityKind.driftRewound:
      // Automatic correction (#98). No actor name — this reads as the app
      // keeping both screens together, not a person skipping backward.
      return SyncActivityText(
        banner: '🔄 Sync correction — rewound to $at',
        chatLine: 'Sync correction: rewound to $at to keep both screens together',
      );
  }
}
