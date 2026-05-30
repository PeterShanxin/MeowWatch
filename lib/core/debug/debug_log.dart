import 'dart:io';

/// A tiny append-only text logger used to capture the Syncplay protocol trace
/// (raw `<<`/`>>` lines and FOLLOW decisions) so the intermittent
/// "A plays but B doesn't follow" can be root-caused from real evidence rather
/// than guessed at. Truncates on [start] so each launch writes a fresh file;
/// all I/O is guarded so logging can never crash playback.
class DebugLog {
  DebugLog(this.file);

  /// Log file living in the OS temp dir, named per the given [name].
  factory DebugLog.temp(String name) =>
      DebugLog(File('${Directory.systemTemp.path}${Platform.pathSeparator}$name'));

  final File file;
  IOSink? _sink;

  /// Absolute path of the log file (handy to surface to the user).
  String get path => file.path;

  /// Open the file for appending, truncating any previous run's contents.
  void start() {
    try {
      file.writeAsStringSync(''); // truncate
      _sink = file.openWrite(mode: FileMode.append);
      _sink!.writeln('${DateTime.now().toIso8601String()} === log started ===');
    } on FileSystemException {
      _sink = null;
    }
  }

  /// Append one timestamped line. No-op if the file could not be opened.
  void call(String line) {
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln('${DateTime.now().toIso8601String()} $line');
    } on FileSystemException {
      // Drop the line rather than disrupt playback.
    }
  }

  Future<void> close() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } on FileSystemException {
      // Already closing down; nothing to recover.
    }
  }
}
