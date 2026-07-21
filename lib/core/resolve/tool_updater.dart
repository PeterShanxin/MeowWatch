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

  /// When a full cycle last *completed* per tools dir — i.e. `-U` actually ran
  /// and we know the installed version is current. Deliberately in-process and
  /// separate from the on-disk stamp: the stamp throttles *attempts* (an
  /// offline try counts), whereas this records a *confirmed* answer, and only
  /// a confirmed answer may suppress the failure-triggered [updateNow].
  static final Map<String, DateTime> _confirmedCurrent = {};

  File get _stamp => File(p.join(toolsDir.path, '.update-stamp'));

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
    final confirmed = _confirmedCurrent[toolsDir.path];
    if (confirmed != null && _now().difference(confirmed) < recheckWindow) {
      return false;
    }
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

  bool _stampFresh() {
    try {
      final raw = _stamp.readAsStringSync().trim();
      final millis = int.tryParse(raw);
      if (millis == null) return false;
      final last = DateTime.fromMillisecondsSinceEpoch(millis);
      return _now().difference(last) < checkInterval;
    } on FileSystemException {
      return false; // No stamp yet — due.
    }
  }

  /// Stamp *before* the attempt: an offline or crashing attempt must not
  /// retry-spam on every resolve — one quiet try per interval.
  void _writeStamp() {
    try {
      _stamp.writeAsStringSync('${_now().millisecondsSinceEpoch}');
    } on FileSystemException {
      // A missing stamp only means the next check runs early — harmless.
    }
  }

  Future<bool> _update(String exePath) async {
    _writeStamp();
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
    // the next failure-triggered check.
    _confirmedCurrent[toolsDir.path] = _now();
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
