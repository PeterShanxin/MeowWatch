import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'resolve_error.dart';

/// Downloads and maintains the external resolver tools on first use:
/// `yt-dlp.exe` (the actual page-URL resolver) and `deno.exe` (the JavaScript
/// runtime yt-dlp needs for full YouTube support since 2025.11 — it looks for
/// it in its own directory automatically).
///
/// The tools live in `<app data dir>/tools`, NOT next to the app exe and NOT
/// inside the release zip: the app updater's robocopy would overwrite a
/// self-updated `yt-dlp.exe` with a stale bundled copy on every app update,
/// and bundling would grow every update download by ~17 MB. A user-writable
/// directory we own is also what `yt-dlp -U` self-update (issue #124) needs.
///
/// yt-dlp is verified against the release's published `SHA2-256SUMS` before it
/// is ever executed; the download fails closed. Deno is best-effort: a failed
/// deno download degrades YouTube quality but must never block resolving.
class ToolProvisioner {
  ToolProvisioner({
    required this.toolsDir,
    http.Client? client,
    String? ytDlpSha256,
    String? denoSha256,
  })  : _client = client ?? http.Client(),
        _ytDlpSha256 = ytDlpSha256 ?? _kYtDlpSha256,
        _denoSha256 = denoSha256 ?? _kDenoZipSha256;

  /// Directory the tools are installed into (created on demand).
  final Directory toolsDir;

  final http.Client _client;

  /// Expected SHA-256 of the pinned yt-dlp.exe; overridable only for tests.
  final String _ytDlpSha256;

  /// Expected SHA-256 of the pinned Deno zip; overridable only for tests.
  final String _denoSha256;

  // yt-dlp is pinned to a specific version and verified against a hash baked
  // into the app, NOT fetched from `releases/latest` with a same-release
  // `SHA2-256SUMS`: that checksum lives in the very release it verifies, so a
  // compromised release could ship a malicious exe AND a matching sum and pass.
  // The app *executes* yt-dlp, so first install must be fail-closed against a
  // compromised release channel — the same bar the pinned Deno hash meets
  // (Codex #223 P1). Staying current is not sacrificed: yt-dlp rots without
  // updates, so issue #124 keeps it fresh via yt-dlp's own `-U` self-update
  // (its native, signed-per-release update path) after this trusted first
  // install. Bump the version + hash together when advancing the baseline.
  static const _kYtDlpVersion = '2026.07.04';
  static const _kYtDlpSha256 =
      '52fe3c26dcf71fbdc85b528589020bb0b8e383155cfa81b64dd447bbe35e24b8';
  static const _ytDlpUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/download/$_kYtDlpVersion/'
      'yt-dlp.exe';

  // Deno is pinned to a specific version and verified against a hash baked into
  // the app (not `releases/latest`): yt-dlp auto-discovers and *executes* the
  // deno beside it, so an unverified or floating download would be an
  // arbitrary-code-execution path. A pinned version + baked hash is fail-closed
  // even against a compromised deno release channel (Codex #223 P1). Bump both
  // together when moving Deno versions.
  static const _kDenoVersion = 'v2.9.3';
  static const _kDenoZipSha256 =
      '60343461ac5fe3a31f4ef12667f2946bb852e20655c8610aeb7e751e87f7df3a';
  static const _denoZipUrl =
      'https://github.com/denoland/deno/releases/download/$_kDenoVersion/'
      'deno-x86_64-pc-windows-msvc.zip';

  static const _downloadTimeout = Duration(minutes: 5);

  /// Randomizes the per-process temp file name (with the pid) so concurrent
  /// processes never collide on the same `.part`.
  static final _rng = Random();

  /// Path to a ready `yt-dlp.exe`, downloading it (and best-effort `deno.exe`)
  /// on first call. Later calls are a pure existence check — no network, no
  /// version probe on the hot path.
  ///
  /// [onStatus] receives short user-facing progress lines.
  ///
  /// Throws [ResolveException] with [ResolveErrorKind.network] when the
  /// download could not complete and [ResolveErrorKind.toolMissing] when the
  /// downloaded bytes failed checksum verification.
  /// In-flight provisioning per tools directory, process-wide. Two page-URL
  /// loads started before the first-use download finishes would otherwise both
  /// enter the download branch and race on the same `yt-dlp.exe.part` — one
  /// renaming/deleting it under the other. Sharing a single future serializes
  /// them: the second caller awaits the first's result.
  static final Map<String, Future<String>> _inFlight = {};

  Future<String> ensureYtDlp({void Function(String status)? onStatus}) {
    final key = toolsDir.path;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _ensureYtDlp(onStatus: onStatus);
    _inFlight[key] = future;
    // Clear on settle (success or failure) so a later load can retry after a
    // failed download; use whenComplete so the removal can't swallow the value.
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<String> _ensureYtDlp({void Function(String status)? onStatus}) async {
    final exePath = p.join(toolsDir.path, 'yt-dlp.exe');
    final exe = File(exePath);
    final deno = File(p.join(toolsDir.path, 'deno.exe'));

    if (!exe.existsSync()) {
      await toolsDir.create(recursive: true);
      onStatus?.call('Setting up the video finder…');
      final bytes = await _download(_ytDlpUrl);
      _verifyHash(bytes, _ytDlpSha256, 'yt-dlp.exe');
      await _writeAtomically(exe, bytes);
    }

    if (!deno.existsSync()) {
      // Best-effort: deno only improves YouTube format availability.
      try {
        onStatus?.call('Setting up YouTube support…');
        await _provisionDeno(deno);
      } on Exception {
        // Non-fatal by design; resolving proceeds without deno.
      }
    }

    return exePath;
  }

  /// Fetch [url] fully into memory, mapping transport failures to
  /// [ResolveErrorKind.network].
  Future<List<int>> _download(String url) async {
    final http.Response response;
    try {
      response =
          await _client.get(Uri.parse(url)).timeout(_downloadTimeout);
    } on Exception catch (e) {
      throw ResolveException(ResolveErrorKind.network, 'GET $url: $e');
    }
    if (response.statusCode != 200) {
      throw ResolveException(
        ResolveErrorKind.network,
        'GET $url: HTTP ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  /// Verify [bytes] against the baked-in [expectedHex] SHA-256. Fails closed
  /// with [ResolveErrorKind.toolMissing]: these bytes get executed, so a
  /// mismatch must abort the install.
  void _verifyHash(List<int> bytes, String expectedHex, String name) {
    final actual = sha256.convert(bytes).toString();
    if (actual != expectedHex.toLowerCase()) {
      throw ResolveException(
        ResolveErrorKind.toolMissing,
        '$name checksum mismatch: expected $expectedHex got $actual',
      );
    }
  }

  /// Install [bytes] at [target] atomically and safely across processes.
  ///
  /// Writes to a **process-unique** `.part` sibling (pid + random) so two
  /// MeowWatch processes sharing this tools dir — the documented two-instance
  /// co-watch on one PC, or a dev build beside the installed app — never write
  /// or rename the *same* temp and make one another's provisioning fail
  /// (Codex #223 P2). Whoever renames first wins; a loser that finds [target]
  /// already present discards its temp and reuses the installed copy. The
  /// unique temp also keeps a crash mid-write from shadowing a future retry.
  Future<void> _writeAtomically(File target, List<int> bytes) async {
    final part = File('${target.path}.$pid.${_rng.nextInt(1 << 32)}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      // Another process already installed it — discard ours, reuse theirs.
      if (target.existsSync()) {
        await part.delete();
        return;
      }
      try {
        await part.rename(target.path);
      } on FileSystemException {
        // Lost the rename race: [target] appeared between the check and the
        // rename (Windows rename onto an existing file throws). Reuse theirs.
        if (target.existsSync()) {
          if (part.existsSync()) await part.delete();
          return;
        }
        rethrow;
      }
    } on FileSystemException {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// Download the official deno zip and extract ONLY its `deno.exe` beside
  /// yt-dlp. The deno archive is best-effort (not checksum-verified), so it must
  /// never be trusted to write anything but its one expected entry — a wholesale
  /// extract of a malformed/compromised zip could otherwise overwrite the
  /// checksum-verified `yt-dlp.exe` with a `yt-dlp.exe` entry and defeat the
  /// fail-closed verification (Codex #223 P1). A sanity check rejects a payload
  /// that is not a Windows executable (`MZ` magic).
  Future<void> _provisionDeno(File deno) async {
    final zipBytes = await _download(_denoZipUrl);
    // Fail closed: only the exact pinned Deno build may be installed, since
    // yt-dlp will execute it. A tampered/rebuilt asset never reaches disk.
    _verifyHash(zipBytes, _denoSha256, 'deno zip');
    final archive = ZipDecoder().decodeBytes(zipBytes);
    ArchiveFile? entry;
    for (final file in archive) {
      if (file.isFile && p.basename(file.name) == 'deno.exe') {
        entry = file;
        break;
      }
    }
    if (entry == null) {
      throw const ResolveException(
        ResolveErrorKind.toolMissing,
        'deno.exe missing from archive',
      );
    }
    final bytes = entry.content as List<int>;
    if (bytes.length < 2 || bytes[0] != 0x4D || bytes[1] != 0x5A) {
      throw const ResolveException(
        ResolveErrorKind.toolMissing,
        'deno.exe payload is not a Windows executable',
      );
    }
    // Write only to the fixed destination path — the archive entry name never
    // influences where bytes land, so there is no zip-slip surface.
    await _writeAtomically(deno, bytes);
  }
}
