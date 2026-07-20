import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/app_support_dir.dart';
import 'resolve_error.dart';
import 'resolved_media.dart';
import 'tool_provisioner.dart';
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

/// Orchestrates the page-URL resolve pipeline for a load: locate/provision the
/// tools, run yt-dlp, normalize failures. UI-free so the whole flow — statuses,
/// pass-through, error normalization — is unit-testable; the home screen only
/// supplies the notice surface and supersede guards around [run].
class ResolveFlow {
  ResolveFlow({
    Future<Directory> Function()? toolsDirProvider,
    ProvisionTool? provision,
    ResolvePage? resolve,
  })  : _toolsDir = toolsDirProvider ?? _defaultToolsDir,
        _provision = provision ?? _defaultProvision,
        _resolve = resolve ?? _defaultResolve;

  final Future<Directory> Function() _toolsDir;
  final ProvisionTool _provision;
  final ResolvePage _resolve;

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
  Future<ResolvedMedia> run(
    String pageUrl, {
    void Function(String status)? onStatus,
  }) async {
    try {
      final dir = await _toolsDir();
      final exe = await _provision(dir, onStatus);
      onStatus?.call('Finding the video…');
      return await _resolve(exe, pageUrl);
    } on ResolveException {
      rethrow;
    } on Exception catch (e) {
      throw ResolveException(ResolveErrorKind.unknown, 'unexpected: $e');
    }
  }
}
