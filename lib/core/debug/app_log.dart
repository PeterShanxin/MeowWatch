import 'debug_log.dart';

/// Process-global diagnostic log, installed once at startup ([installAppLog])
/// and shared by every screen and subsystem (#140).
///
/// Before #140 the only logger lived inside `HomeScreen` and saw nothing but
/// Syncplay protocol traffic, so freezes outside the sync layer (#137 leaving a
/// room, #139 loading a video) left no trace. Now one rotating file per app run
/// captures the whole story — lobby, every room joined, video load/open/error,
/// history writes, settings, and update checks — so a single exported log can
/// diagnose any reported problem.
///
/// Subsystems that aren't owned by `HomeScreen` (the shared video engine, the
/// [DebugLog]-less connect screen, the update-service singleton) write through
/// the top-level [appLog]. It is best-effort: before a log is installed (the
/// brief window in `main()` before the log dir resolves), if the log dir was
/// unavailable, or after the log is closed, lines are simply dropped. Logging
/// must never crash or stall playback, so there is no buffering or blocking
/// here — the same contract every [DebugLog] call site already relies on.
DebugLog? _appLog;

/// The active session log, or null when none is installed. Exposed so the
/// screens can adjust its [DebugLog.level] live and flush/export it.
DebugLog? get appLogInstance => _appLog;

/// Install the process-wide session log. Call once from `main()` after the log
/// dir resolves. A later call replaces the reference (used by tests).
void installAppLog(DebugLog? log) => _appLog = log;

/// Forward one best-effort diagnostic line to the active session log. No-op when
/// no log is installed.
///
/// Crash-proof by contract: logging must NEVER throw into its caller. A
/// [DebugLog] whose sink is in a transient bad state could otherwise abort the
/// very code path that logged — it once escaped a peer-apply error handler and
/// left the room-sync drain flag stuck, freezing all sync (the 2026-06-21 field
/// freeze). Any failure here is swallowed; a dropped diagnostic line is always
/// preferable to disrupting playback or sync.
void appLog(String line) {
  try {
    _appLog?.call(line);
  } catch (_) {
    // Best-effort: never let a diagnostic failure surface to the caller.
  }
}
