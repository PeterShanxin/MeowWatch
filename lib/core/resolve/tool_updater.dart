import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../debug/app_log.dart';
import 'installed_versions.dart';
import 'tool_provisioner.dart';

/// Keeps the resolver tools on the version pinned by this build of the app
/// (issue #124).
///
/// Sites like YouTube change constantly and yt-dlp ships fixes within days, so
/// a resolver frozen at install time quietly rots. The tempting fix —
/// `yt-dlp -U` — was rejected: it verifies a download against a checksum file
/// published inside the very release it is installing, and skips verification
/// altogether (with a warning) when that checksum is missing. Since the app
/// *executes* this binary, that would re-open the arbitrary-code-execution
/// path the pinned, hash-verified install closes, leaving the pin protective
/// for roughly a day (Codex #225 P1).
///
/// So the pin *is* the update channel. Each app release bakes a newer version
/// and its SHA-256; when the recorded install no longer matches the baked pin,
/// the tool is re-provisioned through [ToolProvisioner]'s verified download.
/// The app's own updates are Ed25519-signed (#189), so every byte the app ever
/// executes traces back to a key shipped inside the app.
///
/// Everything here is best-effort by contract: an update must never throw into
/// a resolve and never block playback. Detecting drift is a single small file
/// read — no process spawn, no network — because it runs on the resolve path.
class ToolUpdater {
  ToolUpdater({
    required this.toolsDir,
    Future<void> Function()? installYtDlp,
    Future<void> Function()? installDeno,
    void Function(String line)? log,
    // Public params keep their names; the fields are private, so initializing
    // formals can't be used here (same shape as YtDlpResolver).
    // ignore: prefer_initializing_formals
  })  : _installYtDlp = installYtDlp,
        // ignore: prefer_initializing_formals
        _installDeno = installDeno,
        _log = log ?? appLog;

  /// Directory holding `yt-dlp.exe` (and optionally `deno.exe`).
  final Directory toolsDir;

  /// Install actions; null means "use the real [ToolProvisioner]".
  final Future<void> Function()? _installYtDlp;
  final Future<void> Function()? _installDeno;

  final void Function(String line) _log;

  /// In-flight reconcile per tools directory, process-wide — a background
  /// check and a failure-triggered [updateNow] must never download the same
  /// tool concurrently (same single-flight shape as [ToolProvisioner]).
  static final Map<String, Future<bool>> _inFlight = {};

  /// Bring the tools onto the pinned versions if an app update moved them.
  /// Fire-and-forget: never throws, never blocks the caller's resolve.
  Future<void> maybeUpdate() => updateNow();

  /// Same reconcile, but reports whether yt-dlp actually changed — the signal
  /// the resolve path uses to decide a failed resolve is worth retrying.
  ///
  /// When the installed copy is already on the pin this returns immediately
  /// without touching the network, so a resolve that failed for any other
  /// reason surfaces its error at once instead of waiting on an update that
  /// cannot help.
  Future<bool> updateNow() {
    final key = toolsDir.path;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _reconcile();
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<bool> _reconcile() async {
    final versions = InstalledVersions(toolsDir);
    final changed = await _reconcileYtDlp(versions);
    await _reconcileDeno(versions);
    return changed;
  }

  Future<bool> _reconcileYtDlp(InstalledVersions versions) async {
    final have = versions[InstalledVersions.ytDlp];
    if (have == ToolProvisioner.ytDlpVersion) return false;
    try {
      final install = _installYtDlp ??
          () => ToolProvisioner(toolsDir: toolsDir).installYtDlp(replace: true);
      await install();
      _log('resolver: yt-dlp ${have ?? 'unverified'} → '
          '${ToolProvisioner.ytDlpVersion}');
      return true;
    } on Exception catch (e) {
      // Nothing is recorded on failure, so the drift persists and the next
      // check simply tries again — which is what makes an offline user's
      // update land on their next session instead of being lost.
      _log('resolver: yt-dlp update failed ($e)');
      return false;
    }
  }

  /// Deno rides the same pin. Only reconciled when it is actually installed —
  /// provisioning it fresh is [ToolProvisioner]'s job, and a missing deno only
  /// costs YouTube format quality.
  Future<void> _reconcileDeno(InstalledVersions versions) async {
    if (!File(p.join(toolsDir.path, 'deno.exe')).existsSync()) return;
    final have = versions[InstalledVersions.deno];
    if (have == ToolProvisioner.denoVersion) return;
    try {
      final install = _installDeno ??
          () => ToolProvisioner(toolsDir: toolsDir).installDeno(replace: true);
      await install();
      _log('resolver: deno ${have ?? 'unverified'} → '
          '${ToolProvisioner.denoVersion}');
    } on Exception catch (e) {
      _log('resolver: deno update failed ($e)');
    }
  }
}
