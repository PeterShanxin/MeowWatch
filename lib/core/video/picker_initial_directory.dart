import 'package:path/path.dart' as p;

import 'video_url.dart';

/// Resolve the folder the native "Load Video" file picker should open in.
///
/// **Why this exists (issue #139).** `file_selector`'s Windows backend shows the
/// dialog with a *synchronous, blocking* `IFileDialog::Show` call that runs on
/// Flutter's platform thread — the UI thread. With no folder set, the dialog
/// opens on the **Quick access / Recent** view, whose aggregate scan of every
/// recent, pinned, and cloud (OneDrive, mapped network drive, …) location can
/// stall. While `Show` is stalled the UI thread is stuck inside it, so the whole
/// app goes "Not Responding" and never recovers (it's not an async wait — no
/// timeout can rescue it). Whether it stalls depends on the machine's shell
/// state, which is why it hits some users and not others.
///
/// Pointing the picker straight at a concrete local folder makes it navigate
/// there instead of building the Quick-access view, sidestepping that scan.
///
/// Returns the first **existing** directory among, in priority order:
/// 1. the folder of the last file loaded this session ([lastLoadedFilePath]),
/// 2. the folder of the most recent watch-history entry ([recentFilePath]),
/// 3. the user's `Videos` folder, then their home folder.
///
/// `http(s)` sources are ignored (a stream URL has no folder). Returns `null`
/// when no candidate exists — the picker then keeps its own default. (The
/// backend's `SetFolder` silently no-ops on a missing path, so guessing a
/// non-existent folder would gain nothing.)
///
/// [directoryExists] is injected so the policy stays unit-testable without a
/// real filesystem; the app passes `Directory(path).existsSync`.
String? resolvePickerInitialDirectory({
  String? lastLoadedFilePath,
  String? recentFilePath,
  required Map<String, String> environment,
  required bool Function(String path) directoryExists,
}) {
  for (final candidate in _candidateDirectories(
    lastLoadedFilePath,
    recentFilePath,
    environment,
  )) {
    if (candidate.isNotEmpty && directoryExists(candidate)) return candidate;
  }
  return null;
}

Iterable<String> _candidateDirectories(
  String? lastLoadedFilePath,
  String? recentFilePath,
  Map<String, String> environment,
) sync* {
  final lastDir = _localFileDir(lastLoadedFilePath);
  if (lastDir != null) yield lastDir;

  final recentDir = _localFileDir(recentFilePath);
  if (recentDir != null) yield recentDir;

  final home = environment['USERPROFILE'] ?? environment['HOME'];
  if (home != null && home.isNotEmpty) {
    yield p.join(home, 'Videos');
    yield home;
  }
}

/// The containing directory of [source] when it is a local file path, or `null`
/// when [source] is null/empty, an `http(s)` URL (no folder), or a bare
/// filename with no directory part.
String? _localFileDir(String? source) {
  if (source == null || source.isEmpty || isHttpUrl(source)) return null;
  final dir = p.dirname(source);
  return (dir.isEmpty || dir == '.') ? null : dir;
}
