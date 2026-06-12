import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stable per-user directory the rotating diagnostic logs live in
/// (`<app-support>/logs`). Both the in-room logger and the lobby export resolve
/// it through here, so the path is defined in exactly one place.
Future<Directory> resolveAppLogsDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'logs'));
}

/// Bundle every `*.log` file in [dir] into a single in-memory zip.
///
/// Returns the zip bytes, or `null` when there is nothing to export — the
/// directory is missing or holds no logs. A log that can't be read (e.g. locked
/// by another process) is skipped rather than aborting the whole archive.
List<int>? zipLogFiles(Directory dir) {
  if (!dir.existsSync()) return null;
  final archive = Archive();
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.log')) continue;
    try {
      final bytes = f.readAsBytesSync();
      archive.addFile(ArchiveFile(p.basename(f.path), bytes.length, bytes));
    } on FileSystemException {
      // Skip a locked/unreadable log rather than abort the whole export.
    }
  }
  if (archive.isEmpty) return null;
  return ZipEncoder().encode(archive);
}
