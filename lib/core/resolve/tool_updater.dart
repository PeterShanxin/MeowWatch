import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../debug/app_log.dart';
import 'yt_dlp_resolver.dart' show ProcessRunner;

/// Keeps the provisioned resolver tools current after their pinned,
/// checksum-verified first install (issue #124).
///
/// The app never downloads yt-dlp bytes itself after that first install:
/// updates go through `yt-dlp -U`, yt-dlp's own per-release update path, and
/// `deno upgrade` for the JS runtime beside it. That keeps the trust model of
/// #223 intact — pin = fail-closed first install, native self-update = staying
/// current — without the app re-verifying moving targets.
///
/// Everything here is best-effort by contract: an update check must never
/// throw into a resolve, never block playback, and never spam an offline user
/// (one silent attempt per [checkInterval], stamped per attempt).
class ToolUpdater {
  ToolUpdater({
    required this.toolsDir,
    ProcessRunner? runner,
    DateTime Function()? now,
    void Function(String line)? log,
    this.checkInterval = const Duration(hours: 24),
    this.recheckWindow = const Duration(hours: 1),
    this.timeout = const Duration(minutes: 2),
    // Public param stays `runner`; the field is private, so an initializing
    // formal can't be used here (same shape as YtDlpResolver).
    // ignore: prefer_initializing_formals
  })  : _runner = runner,
        _now = now ?? DateTime.now,
        _log = log ?? appLog;

  /// Directory holding `yt-dlp.exe` (and optionally `deno.exe`).
  final Directory toolsDir;

  /// Minimum spacing between background update attempts.
  final Duration checkInterval;

  /// How long a completed cycle's "we are current" answer is trusted by
  /// [updateNow]. A full cycle costs ~8s of real time (measured in the app
  /// log), so a failing resolve must not re-pay it seconds after the
  /// background check already answered the same question.
  final Duration recheckWindow;

  /// Hard cap per spawned tool process; a hung updater is killed, not awaited.
  final Duration timeout;

  /// Test seam: when set, used instead of spawning real processes.
  final ProcessRunner? _runner;

  final DateTime Function() _now;
  final void Function(String line) _log;

  /// In-flight update per tools directory, process-wide — a background check
  /// and a failure-triggered [updateNow] must never run `-U` concurrently on
  /// the same exe (same single-flight shape as ToolProvisioner).
  static final Map<String, Future<bool>> _inFlight = {};

  File get _stamp => File(p.join(toolsDir.path, '.update-stamp'));

  /// The stamp file holds two epoch-millisecond fields, `<attempt> <confirmed>`:
  ///
  /// * **attempt** — when a check was last *tried*, written before the tools
  ///   run. Offline and crashed tries count, which is what stops an offline
  ///   user retrying on every single resolve. Gates [maybeUpdate].
  /// * **confirmed** — when a cycle last *completed*, i.e. `-U` actually ran
  ///   and the installed version is known current. Gates [updateNow].
  ///
  /// Both live on disk rather than in memory because both questions outlive
  /// the process: the app restarts constantly, and an in-process memo meant
  /// the first failing resolve of every new session re-paid the full ~8s
  /// cycle to re-derive an answer the previous session already had. On-disk
  /// also makes it correct across the two co-watch instances sharing a tools
  /// dir. A legacy one-field stamp parses as an attempt with no confirmation.
  ({DateTime? attempt, DateTime? confirmed}) _readStamp() {
    try {
      final fields = _stamp.readAsStringSync().trim().split(' ');
      DateTime? at(int i) {
        if (i >= fields.length) return null;
        final millis = int.tryParse(fields[i]);
        return millis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(millis);
      }

      return (attempt: at(0), confirmed: at(1));
    } on FileSystemException {
      return (attempt: null, confirmed: null); // No stamp yet — due.
    }
  }

  void _writeStampFields({DateTime? attempt, DateTime? confirmed}) {
    try {
      final a = attempt?.millisecondsSinceEpoch ?? 0;
      final c = confirmed?.millisecondsSinceEpoch ?? 0;
      _stamp.writeAsStringSync('$a $c');
    } on FileSystemException {
      // A missing stamp only means the next check runs early — harmless.
    }
  }

  /// Background daily check: skip when the stamp is fresh, otherwise run the
  /// update. Never throws; all failures are logged and swallowed.
  Future<void> maybeUpdate(String exePath) async {
    try {
      if (_stampFresh()) return;
      await _joinOrStart(exePath);
    } catch (e) {
      // Contract: a background update failure must never surface.
      _log('resolver: update check failed ($e)');
    }
  }

  /// Blocking update for the stale-retry path: ignores the daily stamp (a
  /// site that just broke is worth checking off-schedule), but not a cycle
  /// that completed within [recheckWindow] — re-running `-U` seconds after it
  /// reported "already current" only delays the error the user is waiting on.
  /// Returns whether yt-dlp's reported version actually changed. Never throws.
  Future<bool> updateNow(String exePath) async {
    if (_within(_readStamp().confirmed, recheckWindow)) return false;
    try {
      return await _joinOrStart(exePath);
    } catch (e) {
      _log('resolver: update failed ($e)');
      return false;
    }
  }

  Future<bool> _joinOrStart(String exePath) {
    final key = toolsDir.path;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _update(exePath);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  /// Whether [stamp] falls inside [window] ending now.
  ///
  /// A *future* stamp counts as stale, not fresh. The clock moves backward in
  /// practice — an NTP correction, a manual fix, a dead CMOS battery — and a
  /// stamp written while it was ahead leaves a negative age, which a naive
  /// `age < window` reads as fresh and would keep reading as fresh until
  /// wall-clock time catches up. That could pin a stale yt-dlp for days
  /// (Codex #225 P2). Erring toward one extra check costs seconds; erring the
  /// other way silently disables updating.
  bool _within(DateTime? stamp, Duration window) {
    if (stamp == null) return false;
    final age = _now().difference(stamp);
    return !age.isNegative && age < window;
  }

  bool _stampFresh() => _within(_readStamp().attempt, checkInterval);

  Future<bool> _update(String exePath) async {
    // Record the attempt *before* running anything: an offline or crashing
    // attempt must not retry-spam on every resolve — one quiet try per
    // interval. The previous confirmation is carried over so a failed attempt
    // never discards a still-valid answer.
    final priorConfirmed = _readStamp().confirmed;
    _writeStampFields(attempt: _now(), confirmed: priorConfirmed);
    final before = await _version(exePath);
    final update = await _run(exePath, const ['-U']);
    if (update.exitCode != 0) {
      // Never report "up to date" off the back of an update that did not run —
      // that reads in the log as a healthy check when yt-dlp is in fact
      // frozen at whatever version it had, and it would suppress the next
      // failure-triggered retry for an hour.
      final why = update.stderr.toString().trim();
      _log('resolver: yt-dlp update failed (exit ${update.exitCode}'
          '${why.isEmpty ? '' : ': ${why.split('\n').first}'})');
      await _upgradeDenoBestEffort();
      return false;
    }
    final after = await _version(exePath);
    final changed = before != after && after.isNotEmpty;
    _log(changed
        ? 'resolver: yt-dlp $before → $after'
        : 'resolver: yt-dlp up to date ($after)');
    // Only a cycle that actually ran `-U` earns the right to short-circuit
    // the next failure-triggered check — including one in a later session.
    _writeStampFields(attempt: _now(), confirmed: _now());
    await _upgradeDenoBestEffort();
    return changed;
  }

  Future<String> _version(String exePath) async {
    final result = await _run(exePath, const ['--version']);
    return result.stdout.toString().trim();
  }

  /// Deno rots far slower than yt-dlp but rots all the same; `deno upgrade`
  /// is its native self-update. Strictly best-effort — deno only improves
  /// YouTube format availability and must never fail the yt-dlp update.
  Future<void> _upgradeDenoBestEffort() async {
    final deno = p.join(toolsDir.path, 'deno.exe');
    if (!File(deno).existsSync()) return;
    try {
      await _run(deno, const ['upgrade', '-q']);
    } catch (e) {
      _log('resolver: deno upgrade failed ($e)');
    }
  }

  /// Run a tool with a hard timeout. Test path races the injected runner;
  /// production owns the [Process] so a hung updater is killed, not leaked
  /// (same shape as YtDlpResolver._runWithTimeout).
  Future<ProcessResult> _run(String exe, List<String> args) async {
    final runner = _runner;
    if (runner != null) {
      final result = await Future.any<ProcessResult?>([
        runner(exe, args),
        Future<ProcessResult?>.delayed(timeout, () => null),
      ]);
      if (result == null) throw TimeoutException('$exe ${args.join(' ')}');
      return result;
    }

    final process = await Process.start(exe, args);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exit = await Future.any<int?>([
      process.exitCode,
      Future<int?>.delayed(timeout, () => null),
    ]);
    if (exit == null) {
      process.kill(ProcessSignal.sigkill);
      unawaited(process.exitCode);
      unawaited(stdoutFuture);
      unawaited(stderrFuture);
      throw TimeoutException('$exe ${args.join(' ')}');
    }
    return ProcessResult(process.pid, exit, await stdoutFuture,
        await stderrFuture);
  }
}
