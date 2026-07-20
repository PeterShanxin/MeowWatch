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

  /// Blocking update for the stale-retry path: ignores the stamp, returns
  /// whether yt-dlp's reported version actually changed. Never throws.
  Future<bool> updateNow(String exePath) async {
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
    await _run(exePath, const ['-U']);
    final after = await _version(exePath);
    final changed = before != after && after.isNotEmpty;
    _log(changed
        ? 'resolver: yt-dlp $before → $after'
        : 'resolver: yt-dlp up to date ($after)');
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
