import 'dart:async';
import 'dart:io';

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
  ToolProvisioner({required this.toolsDir, http.Client? client})
      : _client = client ?? http.Client();

  /// Directory the tools are installed into (created on demand).
  final Directory toolsDir;

  final http.Client _client;

  static const _ytDlpBase =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download';
  static const _denoZipUrl =
      'https://github.com/denoland/deno/releases/latest/download/'
      'deno-x86_64-pc-windows-msvc.zip';

  static const _downloadTimeout = Duration(minutes: 5);

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
      final bytes = await _download('$_ytDlpBase/yt-dlp.exe');
      final sums = await _download('$_ytDlpBase/SHA2-256SUMS');
      _verifySha256(bytes, String.fromCharCodes(sums), 'yt-dlp.exe');
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

  /// Check [bytes] against the entry for [assetName] in a yt-dlp
  /// `SHA2-256SUMS` file (`<hex>  <name>` per line). Fails closed: a missing
  /// entry is as fatal as a mismatch — these bytes get executed.
  void _verifySha256(List<int> bytes, String sumsText, String assetName) {
    String? expected;
    for (final line in sumsText.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[1] == assetName) {
        expected = parts[0].toLowerCase();
        break;
      }
    }
    if (expected == null) {
      throw ResolveException(
        ResolveErrorKind.toolMissing,
        'no SHA2-256SUMS entry for $assetName',
      );
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw ResolveException(
        ResolveErrorKind.toolMissing,
        '$assetName checksum mismatch: expected $expected got $actual',
      );
    }
  }

  /// Write [bytes] via a `.part` sibling then rename, so a crash mid-write
  /// never leaves a truncated exe that would shadow a future retry.
  Future<void> _writeAtomically(File target, List<int> bytes) async {
    final part = File('${target.path}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(target.path);
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
