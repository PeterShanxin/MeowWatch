import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/app_support_dir.dart';
import 'resolve_error.dart';
import 'resolved_media.dart';
import 'tool_provisioner.dart';
import 'tool_updater.dart';
import 'yt_dlp_resolver.dart';

/// Provision a ready `yt-dlp.exe` inside [toolsDir], reporting progress lines
/// to [onStatus]. Seam for tests; defaults to [ToolProvisioner.ensureYtDlp].
typedef ProvisionTool = Future<String> Function(
  Directory toolsDir,
  void Function(String status)? onStatus,
);

/// Resolve [pageUrl] with the yt-dlp at [exePath]. Seam for tests; defaults to
/// [YtDlpResolver.resolve].
typedef ResolvePage = Future<ResolvedMedia> Function(
  String exePath,
  String pageUrl,
);

/// Fire-and-forget check that the tools match this build's pinned versions.
/// Seam for tests; defaults to [ToolUpdater.maybeUpdate] (#124).
typedef BackgroundUpdate = Future<void> Function();

/// Blocking reconcile for the stale-retry path; resolves to whether yt-dlp was
/// actually replaced. Seam for tests; defaults to [ToolUpdater.updateNow].
typedef UpdateNow = Future<bool> Function();

/// Orchestrates the page-URL resolve pipeline for a load: locate/provision the
/// tools, run yt-dlp, normalize failures. UI-free so the whole flow — statuses,
/// pass-through, error normalization — is unit-testable; the home screen only
/// supplies the notice surface and supersede guards around [run].
class ResolveFlow {
  ResolveFlow({
    Future<Directory> Function()? toolsDirProvider,
    ProvisionTool? provision,
    ResolvePage? resolve,
    BackgroundUpdate? backgroundUpdate,
    UpdateNow? updateNow,
  })  : _toolsDir = toolsDirProvider ?? _defaultToolsDir,
        _provision = provision ?? _defaultProvision,
        _resolve = resolve ?? _defaultResolve,
        // Public params keep their names; the fields are private, so
        // initializing formals can't be used here (same shape as
        // YtDlpResolver).
        // ignore: prefer_initializing_formals
        _backgroundUpdate = backgroundUpdate,
        // ignore: prefer_initializing_formals
        _updateNow = updateNow;

  final Future<Directory> Function() _toolsDir;
  final ProvisionTool _provision;
  final ResolvePage _resolve;

  /// Null means "use the real [ToolUpdater] for the tools dir at hand" — the
  /// dir isn't known until [run], so the defaults are built there.
  final BackgroundUpdate? _backgroundUpdate;
  final UpdateNow? _updateNow;

  static Future<Directory> _defaultToolsDir() async =>
      Directory(p.join((await resolveAppSupportDir()).path, 'tools'));

  static Future<String> _defaultProvision(
    Directory toolsDir,
    void Function(String status)? onStatus,
  ) =>
      ToolProvisioner(toolsDir: toolsDir).ensureYtDlp(onStatus: onStatus);

  static Future<ResolvedMedia> _defaultResolve(
    String exePath,
    String pageUrl,
  ) =>
      YtDlpResolver(exePath: exePath).resolve(pageUrl);

  /// Resolve [pageUrl] into playable streams. Every failure surfaces as a
  /// [ResolveException]; anything unexpected (a vanished exe, a filesystem
  /// error) is normalized to [ResolveErrorKind.unknown] so callers have exactly
  /// one error type to map to user copy.
  ///
  /// Two update hooks ride along (#124): a fire-and-forget check that never
  /// delays the resolve, and — when the resolve fails in a site-broke way —
  /// one blocking reconcile + single retry, since a yt-dlp left behind by an
  /// app update is a likely cause of a site suddenly failing to extract. Both
  /// are cheap when nothing drifted: a small file read, no network.
  Future<ResolvedMedia> run(
    String pageUrl, {
    void Function(String status)? onStatus,
  }) async {
    try {
      final dir = await _toolsDir();
      final exe = await _provision(dir, onStatus);
      final updater = ToolUpdater(toolsDir: dir);
      // Background freshness check with the binary we already have — the
      // resolve below never waits on it.
      unawaited((_backgroundUpdate ?? updater.maybeUpdate)());
      onStatus?.call('Finding the video…');
      try {
        return await _resolve(exe, pageUrl);
      } on ResolveException catch (e) {
        if (!_updateWorthRetry(e.kind)) rethrow;
        // Site-broke shape: a resolver left behind by an app update is the
        // prime suspect. Retry once only if it was actually replaced.
        final changed = await (_updateNow ?? updater.updateNow)();
        if (!changed) rethrow;
        onStatus?.call('The video finder needed an update — retrying…');
        return await _resolve(exe, pageUrl);
      }
    } on ResolveException {
      rethrow;
    } on Exception catch (e) {
      throw ResolveException(ResolveErrorKind.unknown, 'unexpected: $e');
    }
  }

  /// Only failure shapes a newer extractor could plausibly fix. Network, geo,
  /// DRM, login walls, and timeouts are not staleness — re-provisioning would
  /// download 17 MB to change nothing.
  static bool _updateWorthRetry(ResolveErrorKind kind) =>
      kind == ResolveErrorKind.unsupportedSite ||
      kind == ResolveErrorKind.unknown;
}
