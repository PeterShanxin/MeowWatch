/// Coordinates periodic resume-position saves against the history DB.
///
/// `HomeScreen` ticks a save attempt every few seconds while a source is
/// open, even while paused. Without this gate that means writing the exact
/// same (file, position, duration) to SQLite forever, and a slow write can
/// overlap the next tick (#206). [attempt] fixes both, for a normal
/// (non-forced) call:
///
/// - **Single-flight.** While a previous [attempt]'s `write` is still
///   running, a new call is a silent no-op — never a second overlapping
///   write.
/// - **Skip unchanged.** Once a `write` has completed, a later call with the
///   identical (filePath, positionMs, durationMs) is also a no-op.
///
/// [force] (used by leave/dispose, so the final position is never dropped)
/// bypasses both checks — it always invokes `write`, matching how the
/// terminal save always ran before this gate existed.
///
/// A throwing `write` does not update the "last saved" baseline, so a later
/// attempt — even an otherwise-unchanged one — retries rather than silently
/// giving up.
class ResumeSaveGate {
  bool _saving = false;
  ({String filePath, int positionMs, int durationMs})? _lastSaved;

  /// True while a previous [attempt]'s `write` is still running.
  bool get isSaving => _saving;

  Future<void> attempt({
    required String filePath,
    required int positionMs,
    required int durationMs,
    required Future<void> Function() write,
    bool force = false,
  }) async {
    final snapshot = (
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
    );
    if (!force) {
      if (_saving) return;
      if (snapshot == _lastSaved) return;
    }

    _saving = true;
    try {
      await write();
      _lastSaved = snapshot;
    } finally {
      // MUST reset unconditionally: a throwing `write` (or a throwing
      // diagnostic log inside it) must never leave saves permanently stuck —
      // that exact class of bug (a guard flag left stuck true by a throwing
      // path) once froze this app's sync layer for months before it was
      // traced (see playback_sync_bridge.dart's `_drainingPeerStates`).
      _saving = false;
    }
  }
}
