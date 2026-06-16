import 'dart:async';
import 'dart:io';

import 'log_level.dart';

/// True for lines that are only useful at [LogLevel.verbose]: the high-frequency
/// firehose. Three shapes qualify:
/// - raw per-heartbeat protocol traffic (`<<` / `>>`),
/// - FOLLOW decisions that resolved to no action (`apply=false`), and
/// - app-wide playback/position trace lines, which all carry the `trace:` prefix
///   (locally-applied play/pause/seek ticks, duration/position churn, periodic
///   resume-position DB writes) added for the broadened diagnostics in #140.
///
/// Everything else — applied follows, reconnects/drops, errors, log markers, and
/// the meaningful app events (`video:`/`life:`/`db:`/`update:`/`settings:` —
/// loads, opens, failures, lifecycle, history outcomes) — is a meaningful event
/// kept at [LogLevel.neat]. Pure so it can be unit-tested without any I/O.
bool isVerboseOnly(String line) {
  final trimmed = line.trimLeft();
  final isRawTraffic = trimmed.startsWith('<<') || trimmed.startsWith('>>');
  if (isRawTraffic) {
    // A server `Error` (bad password, room full, kicked) only ever appears as a
    // raw `<<` line, and it's exactly the rejection detail Neat is meant to
    // keep — so don't treat an Error-bearing raw line as verbose-only spam.
    return !trimmed.contains('"Error"');
  }
  // The `trace:` prefix tags the broadened app firehose (#140): per-tick
  // playback state, position churn, and the every-few-seconds resume save.
  if (trimmed.startsWith('trace:')) return true;
  // `apply=false` is a no-op FOLLOW decision. Scope the check to FOLLOW lines:
  // with the broadened app logging, arbitrary filenames/error text now pass
  // through here, and a meaningful line that merely contains that substring
  // (e.g. `video: load apply=false.mkv`) must not be dropped at neat (#146).
  return trimmed.startsWith('FOLLOW') && trimmed.contains('apply=false');
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

  /// Serial chain of best-effort flushes. The eager per-line flush ([call]) and
  /// every explicit [flush]/[close]/off-switch all queue their `IOSink.flush()`
  /// here so two never overlap — concurrent flushes throw "StreamSink is bound
  /// to a stream". Errors are swallowed so the chain (and logging) survives a
  /// transient I/O failure.
  Future<void> _pendingFlush = Future<void>.value();

  /// Queue [sink].flush() onto [_pendingFlush] so it runs after any in-flight
  /// flush, never concurrently. Returns the queued future so a caller can await
  /// exactly its own flush.
  Future<void> _queueFlush(IOSink sink) {
    final next = _pendingFlush
        .then((_) => sink.flush())
        .catchError((Object _) {});
    _pendingFlush = next;
    return next;
  }

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
        // following [flush]/[close] can wait for the last lines to land. The
        // flush goes through [_queueFlush] so it can't overlap an in-flight
        // eager flush on the same sink.
        _closing = () async {
          try {
            await _queueFlush(sink);
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
      // Eagerly flush meaningful events (not the `trace:`/raw firehose) so a
      // fast OS window-close — which in the lobby / after leaving a room skips
      // the close handler's flush — still leaves the run-level trace on disk
      // (#140 review). Queued (not a bare `sink.flush()`) so it never overlaps
      // another flush. The frequent firehose stays buffered to keep this cheap.
      if (!isVerboseOnly(line)) unawaited(_queueFlush(sink));
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
    if (sink == null) {
      await _pendingFlush; // let any tail eager flushes land
      return;
    }
    // Queue our flush behind any in-flight one and await exactly it, so the
    // export read sees the latest lines without two flushes overlapping.
    await _queueFlush(sink);
  }

  Future<void> close() async {
    await _closing;
    _closing = null;
    final sink = _sink;
    // Stop new writes/eager flushes first; queued flushes then no-op on the
    // detached sink, so our final flush+close can't overlap one.
    _sink = null;
    await _pendingFlush;
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
