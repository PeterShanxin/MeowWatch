import 'history_entry.dart';
import 'history_mode.dart';

/// Apply the continue-watching [mode] to a newest-first [entries] list.
///
/// [HistoryMode.everyVideo] returns every context record (same media in
/// Local and in room A both stay). [HistoryMode.latestPerRoom] keeps the
/// newest row per context key — Local is one bucket, each synced
/// server/port/room is its own. Hide-not-delete: view filter only.
List<HistoryEntry> collapseHistory(
  List<HistoryEntry> entries,
  HistoryMode mode,
) {
  if (mode == HistoryMode.everyVideo) {
    return List<HistoryEntry>.of(entries);
  }
  final seen = <String>{};
  final out = <HistoryEntry>[];
  for (final entry in entries) {
    if (seen.add(entry.contextKey)) out.add(entry);
  }
  return out;
}
