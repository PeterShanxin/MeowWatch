import 'history_entry.dart';
import 'history_mode.dart';

/// Apply the continue-watching [mode] to a newest-first [entries] list.
///
/// [HistoryMode.everyVideo] returns the list unchanged. [HistoryMode.latestPerRoom]
/// keeps an entry when its room is null/empty (a solo or pre-schema watch is not
/// "in a room") OR when that room's bare code has not been seen yet — because the
/// list is newest-first, the first sighting of a room is its latest entry, so
/// later same-room entries are dropped. Hide-not-delete: this filters the view
/// only; nothing is removed from storage. The input is never mutated.
List<HistoryEntry> collapseHistory(List<HistoryEntry> entries, HistoryMode mode) {
  if (mode == HistoryMode.everyVideo) {
    return List<HistoryEntry>.of(entries);
  }
  final seenRooms = <String>{};
  final out = <HistoryEntry>[];
  for (final entry in entries) {
    final room = entry.room?.trim() ?? '';
    if (room.isEmpty) {
      out.add(entry);
      continue;
    }
    if (seenRooms.add(room)) out.add(entry);
  }
  return out;
}
