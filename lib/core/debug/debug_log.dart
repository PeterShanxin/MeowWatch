import 'dart:io';

import 'log_level.dart';

/// True for lines that are only useful at [LogLevel.verbose]: the raw
/// per-heartbeat protocol traffic (`<<` / `>>`) and FOLLOW decisions that
/// resolved to no action (`apply=false`). Everything else — applied follows,
/// reconnects/drops, errors, log markers — is a meaningful event kept at
/// [LogLevel.neat]. Pure so it can be unit-tested without any I/O.
bool isVerboseOnly(String line) {
  final trimmed = line.trimLeft();
  final isRawTraffic = trimmed.startsWith('<<') || trimmed.startsWith('>>');
  if (isRawTraffic) {
    // A server `Error` (bad password, room full, kicked) only ever appears as a
    // raw `<<` line, and it's exactly the rejection detail Neat is meant to
    // keep — so don't treat an Error-bearing raw line as verbose-only spam.
    return !trimmed.contains('"Error"');
  }
  return trimmed.contains('apply=false');
}

/// A tiny append-only text logger that captures the Syncplay protocol trace
/// (raw `<<`/`>>` lines and FOLLOW decisions) so the intermittent co-watch
/// A/V lag can be root-caused from real evidence rather than guessed at.
///
/// Two shapes:
/// - [DebugLog.new] — a single fixed file that truncates on [start].
/// - [DebugLog.inDir] — a rotating logger: each [start] opens a fresh
///   timestamped file and prunes the directory to the newest `retain` logs,
///   so the evidence is already on disk when the bug next strikes.
///
/// A live [level] gates how much is written. All I/O is guarded so logging can
/// never crash playback.
class DebugLog {
  /// Fixed single-file logger. [start] truncates any previous contents.
  DebugLog(File file, {LogLevel level = LogLevel.verbose})
    : _fixedFile = file,
      _dir = null,
      _baseName = null,
      _retain = 0,
      _level = level,
      _clock = DateTime.now;
  // ignore_for_file: prefer_initializing_formals
  //
  // The named constructor params below feed private final fields. Dart forbids
  // private named parameters, so `this._field` form is unavailable here and the
  // plain assignments are the idiomatic shape.

  /// Rotating logger. Each [start] opens a NEW `<baseName>-<stamp>.log` under
  /// [dir] and deletes oldest logs until at most [retain] remain. [clock] is
  /// injectable for deterministic tests; production uses the wall clock.
  DebugLog.inDir(
    Directory dir, {
    required String baseName,
    int retain = 10,
    LogLevel level = LogLevel.verbose,
    DateTime Function() clock = DateTime.now,
  }) : _fixedFile = null,
       _dir = dir,
       _baseName = baseName,
       _retain = retain,
       _level = level,
       _clock = clock;

  final File? _fixedFile;
  final Directory? _dir;
  final String? _baseName;
  final int _retain;
  final DateTime Function() _clock;

  LogLevel _level;
  File? _file;
  IOSink? _sink;

  /// The in-flight flush+close started when logging is switched off. Tracked so
  /// [flush] / [close] can await it — otherwise an Export fired right after
  /// "Off" would read the file before the last buffered lines land.
  Future<void>? _closing;

  /// Directory holding the rotating logs (null for a fixed-file logger).
  /// Handy for the Export-logs feature.
  Directory? get dir => _dir;

  /// Path of the currently-open (or configured) log file. Empty before a
  /// fixed-file logger has been pointed anywhere.
  String get path => _file?.path ?? _fixedFile?.path ?? _dir?.path ?? '';

  /// Current verbosity. Honoured live by [call].
  LogLevel get level => _level;

  /// Change verbosity mid-session. Turning logging off flushes and closes the
  /// current file; turning it back on (from off) opens a fresh rotating file.
  /// Switching between neat/verbose keeps the same file.
  set level(LogLevel value) {
    if (value == _level) return;
    final wasOff = _level == LogLevel.off;
    _level = value;
    if (value == LogLevel.off) {
      final sink = _sink;
      _sink = null;
      if (sink != null) {
        // Best-effort; never block the UI thread. Tracked in [_closing] so a
        // following [flush]/[close] can wait for the last lines to land.
        _closing = () async {
          try {
            await sink.flush();
            await sink.close();
          } on FileSystemException {
            // Nothing to recover; the file just stops where it was.
          }
        }();
      }
    } else if (wasOff && _sink == null) {
      _open();
    }
  }

  /// Open a log file for this session. No-op when [level] is [LogLevel.off].
  void start() {
    if (_level == LogLevel.off) return;
    _open();
  }

  /// Append one timestamped line, subject to [level]. No-op when off, when the
  /// file could not be opened, or when the line is verbose-only and we are in
  /// neat mode.
  void call(String line) {
    if (_level == LogLevel.off) return;
    if (_level == LogLevel.neat && isVerboseOnly(line)) return;
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln('${_clock().toIso8601String()} $line');
    } on FileSystemException {
      // Drop the line rather than disrupt playback.
    }
  }

  /// Push buffered lines to disk without closing the file, so an in-session
  /// read (e.g. the Export-logs bundle) sees the latest protocol/FOLLOW lines
  /// rather than whatever happened to be flushed already.
  Future<void> flush() async {
    // If logging was just switched off, the lines are draining through the
    // close started in the level setter — wait for it before reading the file.
    await _closing;
    final sink = _sink;
    if (sink == null) return;
    try {
      await sink.flush();
    } on FileSystemException {
      // Best-effort; a failed flush just means the export is slightly behind.
    }
  }

  Future<void> close() async {
    await _closing;
    _closing = null;
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

  void _open() {
    try {
      final dir = _dir;
      final base = _baseName;
      if (dir != null && base != null) {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final f = File(
          '${dir.path}${Platform.pathSeparator}$base-${_stamp(_clock())}.log',
        );
        // Create the file on disk up front so the prune scan below counts it
        // (openWrite alone defers file creation until the first write).
        f.createSync();
        _file = f;
        _sink = f.openWrite(mode: FileMode.write);
        _prune(dir, base);
      } else {
        final f = _fixedFile!;
        _file = f;
        f.writeAsStringSync(''); // truncate
        _sink = f.openWrite(mode: FileMode.append);
      }
      _sink!.writeln(
        '${_clock().toIso8601String()} === log started (level=${_level.storageName}) ===',
      );
    } on FileSystemException {
      _sink = null;
    }
  }

  /// Delete oldest `<base>-*.log` files in [dir] until at most [_retain]
  /// remain. Filenames sort lexicographically in chronological order (the
  /// stamp is zero-padded), so an ascending sort puts the oldest first.
  void _prune(Directory dir, String base) {
    if (_retain <= 0) return;
    try {
      final logs =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => _isOurLog(f.path, base))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final excess = logs.length - _retain;
      for (var i = 0; i < excess; i++) {
        try {
          logs[i].deleteSync();
        } on FileSystemException {
          // Locked/gone — skip; pruning is best-effort.
        }
      }
    } on FileSystemException {
      // Can't list — skip pruning this round.
    }
  }

  static bool _isOurLog(String filePath, String base) {
    final name = filePath.replaceAll('\\', '/').split('/').last;
    return name.startsWith('$base-') && name.endsWith('.log');
  }

  /// Filesystem-safe, lexicographically-chronological stamp, e.g.
  /// `2026-06-11_163405_071` (no colons — illegal on Windows).
  static String _stamp(DateTime t) {
    String p2(int n) => n.toString().padLeft(2, '0');
    String p3(int n) => n.toString().padLeft(3, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)}'
        '_${p2(t.hour)}${p2(t.minute)}${p2(t.second)}'
        '_${p3(t.millisecond)}';
  }
}
