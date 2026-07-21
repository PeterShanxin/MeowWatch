import 'dart:io';

import 'package:path/path.dart' as p;

/// Which pinned tool versions this app actually installed into a tools dir.
///
/// A version is recorded only *after* its bytes passed the SHA-256 baked into
/// the app, so a recorded version means "these exact bytes were verified
/// against a hash that arrived inside a signed app update". Comparing it to
/// the current pins is how the app notices an update moved the baseline — that
/// comparison is the whole tool-update mechanism (#124), which is why it has
/// to stay a plain file read: it runs on the resolve path, and the earlier
/// design's process spawns cost ~8s per failed resolve.
///
/// A missing or unreadable record reads as "unknown", which callers treat as
/// drifted. That is deliberate: it re-establishes a known-verified binary for
/// anyone whose `yt-dlp.exe` came from somewhere this app cannot vouch for.
class InstalledVersions {
  InstalledVersions(this.toolsDir);

  final Directory toolsDir;

  /// Record key for the resolver binary.
  static const ytDlp = 'ytdlp';

  /// Record key for the JavaScript runtime yt-dlp executes.
  static const deno = 'deno';

  File get _file => File(p.join(toolsDir.path, '.installed-versions'));

  Map<String, String> _read() {
    try {
      final entries = <String, String>{};
      for (final line in _file.readAsLinesSync()) {
        final split = line.indexOf('=');
        if (split <= 0) continue;
        entries[line.substring(0, split).trim()] =
            line.substring(split + 1).trim();
      }
      return entries;
    } on FileSystemException {
      return const {};
    }
  }

  /// The version of [tool] this app installed, or null when unknown.
  String? operator [](String tool) => _read()[tool];

  /// Remember that [version] of [tool] is the copy now on disk. Best-effort:
  /// a failed write only means the next check re-installs a tool that is
  /// already correct, which is wasteful but never wrong.
  void record(String tool, String version) {
    try {
      final entries = Map<String, String>.from(_read())..[tool] = version;
      _file.writeAsStringSync(
        entries.entries.map((e) => '${e.key}=${e.value}').join('\n'),
      );
    } on FileSystemException {
      // Ignored by contract; see above.
    }
  }
}
