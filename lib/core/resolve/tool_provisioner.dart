import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'installed_versions.dart';
import 'resolve_error.dart';

/// Downloads and maintains the external resolver tools on first use:
/// `yt-dlp.exe` (the actual page-URL resolver) and `deno.exe` (the JavaScript
/// runtime yt-dlp needs for full YouTube support since 2025.11 — it looks for
/// it in its own directory automatically).
///
/// The tools live in `<app data dir>/tools`, NOT next to the app exe and NOT
/// inside the release zip: bundling would grow every app update download by
/// ~17 MB for a file that changes on its own schedule. A user-writable
/// directory the app owns is also what re-provisioning onto a newer pin
/// (issue #124) needs.
///
/// Both tools are verified against a SHA-256 baked into the app before they are
/// ever executed; a download that does not match fails closed. Deno is
/// best-effort in the sense that a *failed* deno download degrades YouTube
/// quality rather than blocking resolving — never in the sense of skipping
/// verification.
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
  // The app *executes* yt-dlp, so every install must be fail-closed against a
  // compromised release channel — the same bar the pinned Deno hash meets
  // (Codex #223 P1).
  //
  // Staying current is not sacrificed, and notably is NOT delegated to
  // `yt-dlp -U`: that path fetches `SHA2-256SUMS` from the very release it is
  // installing (and skips verification with a warning when the hash is
  // absent), so it would re-open exactly the hole this pin closes, leaving the
  // pin protective for only about a day (Codex #225 P1). Instead the pin
  // itself is the update channel: each app release bakes a newer version+hash,
  // and [ToolUpdater] re-provisions through this verified path when the
  // installed copy no longer matches (#124). The app's own updates are
  // Ed25519-signed (#189), so the trust root for every executed byte is a key
  // shipped with the app. Bump version + hash together.
  static const ytDlpVersion = '2026.07.04';
  static const _kYtDlpSha256 =
      '52fe3c26dcf71fbdc85b528589020bb0b8e383155cfa81b64dd447bbe35e24b8';
  static const _ytDlpUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/download/$ytDlpVersion/'
      'yt-dlp.exe';

  // Deno is pinned to a specific version and verified against a hash baked into
  // the app (not `releases/latest`): yt-dlp auto-discovers and *executes* the
  // deno beside it, so an unverified or floating download would be an
  // arbitrary-code-execution path. A pinned version + baked hash is fail-closed
  // even against a compromised deno release channel (Codex #223 P1). Updates
  // ride the pin for the same reason yt-dlp's do — `deno upgrade` would install
  // whatever its endpoint serves, unverified (Codex #225 P1). Bump both
  // together when moving Deno versions.
  static const denoVersion = 'v2.9.3';
  static const _kDenoZipSha256 =
      '60343461ac5fe3a31f4ef12667f2946bb852e20655c8610aeb7e751e87f7df3a';
  static const _denoZipUrl =
      'https://github.com/denoland/deno/releases/download/$denoVersion/'
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
      onStatus?.call('Setting up the video finder…');
      await installYtDlp();
    }

    if (!deno.existsSync()) {
      // Best-effort: deno only improves YouTube format availability.
      try {
        onStatus?.call('Setting up YouTube support…');
        await installDeno();
      } on Exception {
        // Non-fatal by design; resolving proceeds without deno.
      }
    }

    return exePath;
  }

  /// Download, verify and install the pinned `yt-dlp.exe`. Records the version
  /// only after the hash check passes, so the record can never claim a version
  /// the app did not verify.
  ///
  /// [replace] separates the two callers. First install leaves it false: if a
  /// second process installed the tool while this one was downloading, that
  /// copy is kept and ours discarded (Codex #223 P2) — clobbering a binary
  /// another instance may be executing buys nothing when both copies are the
  /// same verified bytes. The upgrade path ([ToolUpdater], moving onto a pin a
  /// new app release advanced) sets it true, because there replacing what is
  /// on disk is the entire point.
  Future<void> installYtDlp({bool replace = false}) async {
    await toolsDir.create(recursive: true);
    final bytes = await _download(_ytDlpUrl);
    _verifyHash(bytes, _ytDlpSha256, 'yt-dlp.exe');
    final installed = await _writeAtomically(
        File(p.join(toolsDir.path, 'yt-dlp.exe')), bytes,
        replace: replace);
    // Only claim the pin when these bytes actually landed. Losing the race
    // means the file belongs to another process, whose build may pin a
    // different version — recording ours would make ToolUpdater see a match
    // and skip reconciliation forever (Codex #225 P2). Recording nothing
    // leaves it drifted, so the next check re-provisions with replace: true.
    if (installed) {
      InstalledVersions(toolsDir).record(InstalledVersions.ytDlp, ytDlpVersion);
    }
  }

  /// Download, verify and install the pinned `deno.exe`. See [installYtDlp]
  /// for what [replace] separates.
  Future<void> installDeno({bool replace = false}) async {
    await toolsDir.create(recursive: true);
    await _provisionDeno(File(p.join(toolsDir.path, 'deno.exe')),
        replace: replace);
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
  /// Returns whether *these* bytes ended up at [target]; false means another
  /// process won the race and its copy was kept.
  Future<bool> _writeAtomically(File target, List<int> bytes,
      {bool replace = false}) async {
    final part = File('${target.path}.$pid.${_rng.nextInt(1 << 32)}.part');
    try {
      await part.writeAsBytes(bytes, flush: true);
      if (target.existsSync()) {
        if (!replace) {
          // Another process already installed it — discard ours, reuse theirs.
          await part.delete();
          return false;
        }
        // Deliberate upgrade onto the new pin. Windows cannot rename onto an
        // existing file, and a delete-then-rename would leave a window with no
        // tool at all for a concurrent resolve, so swing the old copy aside
        // first and put it back if the swap fails.
        final aside = File('${target.path}.$pid.old');
        await target.rename(aside.path);
        try {
          await part.rename(target.path);
        } on FileSystemException {
          await aside.rename(target.path);
          rethrow;
        }
        // Best-effort: a locked leftover is harmless and gets cleaned up by a
        // later upgrade, whereas failing here would undo a good install.
        try {
          await aside.delete();
        } on FileSystemException {
          // Ignored by contract; see above.
        }
        return true;
      }
      try {
        await part.rename(target.path);
      } on FileSystemException {
        // Lost the rename race: [target] appeared between the check and the
        // rename (Windows rename onto an existing file throws). Reuse theirs.
        if (target.existsSync()) {
          if (part.existsSync()) await part.delete();
          return false;
        }
        rethrow;
      }
      return true;
    } on FileSystemException {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// Download the official deno zip and extract ONLY its `deno.exe` beside
  /// yt-dlp. The archive must
  /// never be trusted to write anything but its one expected entry — a wholesale
  /// extract of a malformed/compromised zip could otherwise overwrite the
  /// checksum-verified `yt-dlp.exe` with a `yt-dlp.exe` entry and defeat the
  /// fail-closed verification (Codex #223 P1). A sanity check rejects a payload
  /// that is not a Windows executable (`MZ` magic).
  Future<void> _provisionDeno(File deno, {bool replace = false}) async {
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
    if (await _writeAtomically(deno, bytes, replace: replace)) {
      InstalledVersions(toolsDir).record(InstalledVersions.deno, denoVersion);
    }
  }
}
