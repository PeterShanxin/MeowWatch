import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../app_version.dart';
import '../debug/app_log.dart';
import '../debug/log_redact.dart';
import 'release_signature.dart';
import 'semver.dart';

/// Metadata about an available update.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.signature,
    required this.releaseNotes,
    required this.releaseDate,
  });

  final String version;
  final String downloadUrl;
  final String? sha256;

  /// Base64 Ed25519 signature of the asset zip's bytes, from latest.json's
  /// `sig` field. Verified against the baked-in release public key before the
  /// update is applied. Null for releases published before signing existed —
  /// which the install path (fail-closed) refuses.
  final String? signature;
  final String releaseNotes;
  final String releaseDate;
}

/// One version's changelog entry, as published in `releases/changelog.json`.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.notes,
  });

  final String version;
  final String date;
  final String notes;
}

/// Result of comparing local version to remote.
enum UpdateStatus { upToDate, updateAvailable, checkFailed }

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,

  /// An `applyUpdate` is in flight. Verify+extract runs in a background
  /// isolate (#197), so the event loop is live while it works — this phase is
  /// what lets the dialog hide its Install button and the close handler
  /// swallow the X-click instead of racing a second apply (#205 review).
  installing,
  error,
}

/// Thrown when a downloaded update's SHA-256 does not match the hash published
/// in `latest.json`. Signals a corrupted or tampered download — the update is
/// aborted before any files are extracted or executed.
class UpdateVerificationException implements Exception {
  const UpdateVerificationException({
    required this.expected,
    required this.actual,
  });

  /// The hex digest published alongside the asset.
  final String expected;

  /// The hex digest computed from the bytes that actually arrived.
  final String actual;

  @override
  String toString() =>
      'Update checksum mismatch: expected $expected, got $actual';
}

/// Thrown when a zip entry's path would escape the extraction directory
/// (zip-slip / path traversal). The entry names in a release zip are attacker-
/// influenced — whoever can write the R2 bucket controls them — so an entry like
/// `..\..\Startup\evil.exe` or an absolute path must be rejected before any
/// bytes are written. Aborts the whole update.
class UnsafeArchiveEntryException implements Exception {
  const UnsafeArchiveEntryException({required this.entryName});

  /// The rejected entry name, as it appeared in the archive.
  final String entryName;

  @override
  String toString() =>
      'Unsafe archive entry rejected (path traversal): $entryName';
}

/// Checks for updates from the R2 release bucket, downloads, and applies them.
///
/// Flow:
///   1. `checkForUpdate()` → GET `{baseUrl}/releases/latest.json`
///   2. Compare remote version to [appVersion]
///   3. `downloadUpdate()` → stream zip to temp dir with progress callback
///   4. `applyUpdate()` → verify + extract in a background isolate, write
///      updater.ps1 and its hidden-launch VBS shim, start it, exit app
class UpdateService extends ChangeNotifier {
  static final UpdateService instance = UpdateService._();

  @visibleForTesting
  UpdateService.forTest({
    String? baseUrl,
    http.Client? client,
    String? publicKeyBase64,
  })  : _baseUrl = baseUrl ?? updateBaseUrl,
        _client = client ?? http.Client(),
        _publicKeyBase64 = publicKeyBase64 ?? releasePublicKeyBase64;

  UpdateService._({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? updateBaseUrl,
        _client = client ?? http.Client(),
        _publicKeyBase64 = releasePublicKeyBase64;

  final String _baseUrl;
  final http.Client _client;

  /// Release public key updates are verified against. The baked-in key in
  /// production; tests inject their own so they can sign real payloads.
  final String _publicKeyBase64;

  /// Test seam for the detached-updater launch — `applyUpdate` would otherwise
  /// spawn a real process. Null in production.
  @visibleForTesting
  Future<void> Function(String executable, List<String> arguments)?
      debugStartDetached;

  /// Test seam for terminating the process — `applyUpdate` ends in `exit(0)`,
  /// which would kill the test runner. Null in production.
  @visibleForTesting
  void Function(int code)? debugExitApp;

  /// The one in-flight (or completed) apply. Single-flight: verify+extract
  /// yields to the event loop (#197), so a double-click on Install or the
  /// window-close path could otherwise start a second apply against the same
  /// temp dir — racing file writes and launching duplicate updaters (#205
  /// review). Reset to null on failure so the user can retry.
  Future<void>? _applyFuture;

  UpdateInfo? _latestUpdate;

  /// The most recently fetched update info, or null if not checked yet.
  UpdateInfo? get latestUpdate => _latestUpdate;

  // Dialog-facing state. Mutated only inside this service; consumers read via
  // the getters and rebuild through [ChangeNotifier]. Kept on the singleton so
  // an in-progress download survives the dialog being dismissed and reopened.
  UpdatePhase _phase = UpdatePhase.idle;
  double _downloadProgress = 0;
  int _downloadReceivedBytes = 0;
  int? _downloadTotalBytes;
  String? _downloadedZipPath;
  String _errorMessage = '';
  List<ChangelogEntry> _changelog = const [];

  UpdatePhase get phase => _phase;

  /// 0.0–1.0 download fraction. Meaningful only when [hasDownloadTotal] is true;
  /// stays 0 when the server sent no Content-Length, in which case the UI should
  /// show an indeterminate indicator rather than a frozen 0% bar (#63).
  double get downloadProgress => _downloadProgress;

  /// Bytes received so far — gives the UI something moving even when the total
  /// is unknown.
  int get downloadReceivedBytes => _downloadReceivedBytes;

  /// Total bytes from the response Content-Length, or null when the server
  /// didn't advertise one (chunked/CDN responses).
  int? get downloadTotalBytes => _downloadTotalBytes;

  /// True when a usable total is known, so [downloadProgress] is a real
  /// fraction. False ⇒ the download is indeterminate.
  bool get hasDownloadTotal => (_downloadTotalBytes ?? 0) > 0;

  String? get downloadedZipPath => _downloadedZipPath;
  String get errorMessage => _errorMessage;
  List<ChangelogEntry> get changelog => _changelog;

  /// Check the R2 bucket for a newer version.
  ///
  /// Returns [UpdateStatus.updateAvailable] if a newer version exists,
  /// [UpdateStatus.upToDate] if current, or [UpdateStatus.checkFailed] on error.
  Future<UpdateStatus> checkForUpdate() async {
    try {
      final uri = Uri.parse('$_baseUrl/releases/latest.json');
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        appLog('update: check failed (HTTP ${response.statusCode})');
        return UpdateStatus.checkFailed;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = json['version'] as String;

      // Determine the correct asset key for this machine's architecture.
      final arch = _windowsArch;
      final assets = json['assets'] as Map<String, dynamic>?;
      if (assets == null) {
        appLog('update: check failed (latest.json has no assets)');
        return UpdateStatus.checkFailed;
      }

      final assetKey = 'windows-$arch';
      final asset = assets[assetKey] as Map<String, dynamic>?;
      if (asset == null) {
        appLog('update: check failed (no $assetKey asset)');
        return UpdateStatus.checkFailed;
      }

      _latestUpdate = UpdateInfo(
        version: remoteVersion,
        downloadUrl: asset['url'] as String,
        sha256: asset['sha256'] as String?,
        signature: asset['sig'] as String?,
        releaseNotes: (json['release_notes'] as String?) ?? '',
        releaseDate: (json['release_date'] as String?) ?? '',
      );

      final available = _isNewer(remoteVersion, appVersion);
      appLog(
        'update: check remote=$remoteVersion local=$appVersion '
        '${available ? '→ update available' : '→ up to date'}',
      );
      return available
          ? UpdateStatus.updateAvailable
          : UpdateStatus.upToDate;
    } on Exception catch (e) {
      appLog('update: check failed (${redactUrls('$e')})');
      return UpdateStatus.checkFailed;
    }
  }

  /// Fetch the multi-version changelog, newest first. By default returns only
  /// entries newer than the installed [appVersion] (for the "an update is
  /// available, here's what's in it" view); pass [onlyNewer] `false` to get the
  /// full history including the current version (for the up-to-date "what's
  /// new" view). Returns an empty list on any failure (missing file, network
  /// error, malformed JSON) so callers can fall back to the single-release note.
  Future<List<ChangelogEntry>> fetchChangelog({bool onlyNewer = true}) async {
    try {
      final uri = Uri.parse('$_baseUrl/releases/changelog.json');
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final entries = <ChangelogEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        // Read fields defensively: a wrong-shaped payload (numeric `date`,
        // missing `version`, etc.) is skipped, never thrown.
        final version = item['version'];
        if (version is! String) continue;
        if (onlyNewer && !_isNewer(version, appVersion)) continue;
        final date = item['date'];
        final notes = item['notes'];
        entries.add(ChangelogEntry(
          version: version,
          date: date is String ? date : '',
          notes: notes is String ? notes : '',
        ));
      }
      return entries;
    } catch (_) {
      // Any failure (network, malformed JSON, unexpected shape) → empty list so
      // the dialog falls back to the single-release note.
      return const [];
    }
  }

  Future<void> checkUpdateForDialog() async {
    // Coalesce concurrent calls: a check already in flight (or a download in
    // progress / finished) must not be restarted by a repeated "Check again"
    // tap, or overlapping network calls race and a stale result can win.
    if (phase == UpdatePhase.checking ||
        phase == UpdatePhase.downloading ||
        phase == UpdatePhase.readyToInstall ||
        phase == UpdatePhase.installing) {
      return;
    }
    _phase = UpdatePhase.checking;
    notifyListeners();

    final status = await checkForUpdate();
    if (status == UpdateStatus.checkFailed) {
      _errorMessage = 'Could not reach update server.\nCheck your connection and try again.';
      _phase = UpdatePhase.error;
      notifyListeners();
      return;
    }

    final isUpToDate = status == UpdateStatus.upToDate;
    _changelog = await fetchChangelog(onlyNewer: !isUpToDate);

    _phase = isUpToDate ? UpdatePhase.upToDate : UpdatePhase.updateAvailable;
    notifyListeners();
  }

  Future<void> startDownload() async {
    if (phase == UpdatePhase.downloading) return;
    _phase = UpdatePhase.downloading;
    _downloadProgress = 0;
    _downloadReceivedBytes = 0;
    _downloadTotalBytes = null;
    notifyListeners();

    // Notify at most once per whole percent (known total) or per 256 KiB
    // (unknown total): a ~50 MB zip arrives in thousands of chunks, and a
    // per-chunk notifyListeners() rebuilt the dialog far above frame rate
    // (#197 P5). The byte counters above stay exact on every chunk — only the
    // listener notification is coalesced.
    var lastNotifiedPercent = -1;
    var lastNotifiedBytes = -1;
    const notifyBytesStep = 256 * 1024;

    try {
      final path = await downloadUpdate((received, total) {
        _downloadReceivedBytes = received;
        _downloadTotalBytes = total;
        // Only a real fraction when the total is known; otherwise leave progress
        // at 0 and let the UI render an indeterminate bar (#63).
        final known = total != null && total > 0;
        _downloadProgress = known ? received / total : 0;
        if (known) {
          final percent = received * 100 ~/ total;
          if (percent == lastNotifiedPercent) return;
          lastNotifiedPercent = percent;
        } else {
          // First chunk always notifies so the byte counter visibly starts
          // moving; after that, once per step.
          if (lastNotifiedBytes >= 0 &&
              received - lastNotifiedBytes < notifyBytesStep) {
            return;
          }
          lastNotifiedBytes = received;
        }
        notifyListeners();
      });
      _downloadedZipPath = path;
      _phase = UpdatePhase.readyToInstall;
      appLog('update: download ok ${_latestUpdate?.version ?? '?'}');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      _phase = UpdatePhase.error;
      // The asset URL can be signed; strip any token before persisting.
      appLog('update: download failed (${redactUrls('$e')})');
      notifyListeners();
    }
  }

  /// Download the update zip to a temp directory, calling [onProgress] with the
  /// running byte count and the total (from Content-Length, or null when the
  /// server didn't advertise one — a chunked/CDN response). Fires on every chunk
  /// even when the total is unknown, so the UI always has visible motion.
  ///
  /// Returns the path to the downloaded zip file.
  Future<String> downloadUpdate(
    void Function(int received, int? total) onProgress,
  ) async {
    final info = _latestUpdate;
    if (info == null) throw StateError('No update info — call checkForUpdate first');

    final uri = Uri.parse(info.downloadUrl);
    final request = http.Request('GET', uri);
    final streamed = await _client.send(request).timeout(
      const Duration(seconds: 120),
    );

    final total = streamed.contentLength;
    var received = 0;

    final tempDir = Directory.systemTemp.createTempSync('meowwatch_update_');
    final zipFile = File(p.join(tempDir.path, 'update.zip'));
    final sink = zipFile.openWrite();

    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(received, total);
    }
    await sink.close();

    return zipFile.path;
  }

  /// Extract the zip, write an updater script, launch it, and exit the app.
  ///
  /// The PowerShell script waits for this process to exit, copies the new files
  /// over the existing installation, restarts the app, and cleans up temp files.
  ///
  /// Pass [restartAfter] false to swap the files without relaunching — used by
  /// the apply-on-close path (#62), where the user is quitting.
  Future<void> applyUpdate(String zipPath, {bool restartAfter = true}) {
    // Single-flight: a second call (double-clicked Install, or the close path
    // firing mid-install) shares the in-flight apply instead of racing it.
    return _applyFuture ??= _applyUpdateImpl(zipPath, restartAfter: restartAfter);
  }

  Future<void> _applyUpdateImpl(
    String zipPath, {
    required bool restartAfter,
  }) async {
    appLog('update: apply start ${_latestUpdate?.version ?? '?'} (verify+extract)');
    _phase = UpdatePhase.installing;
    notifyListeners();

    try {
      final tempDir = Directory(p.dirname(zipPath));
      final extractDir = Directory(p.join(tempDir.path, 'extracted'));

      // Verify + extract runs in a background isolate: hashing a tens-of-MB
      // zip, Ed25519 verify, and unzipping are multi-second synchronous jobs
      // that froze the window (no repaint) for the whole "Install" (#197 P4).
      // Every security gate — checksum, signature, zip-slip — still runs, just
      // off the UI isolate. See [verifyAndExtractUpdateInBackground] for why
      // each gate exists.
      await verifyAndExtractUpdateInBackground(
        zipPath: zipPath,
        version: _latestUpdate?.version ?? '',
        expectedSha256: _latestUpdate?.sha256,
        signature: _latestUpdate?.signature,
        extractDirPath: extractDir.path,
        publicKeyBase64: _publicKeyBase64,
      );

      // The app directory is the folder containing the current executable.
      final appDir = p.dirname(Platform.resolvedExecutable);
      final scriptPath = p.join(tempDir.path, 'updater.ps1');
      final vbsPath = p.join(tempDir.path, 'updater.vbs');

      final script = buildUpdaterScript(
        extractedDir: extractDir.path,
        appDir: appDir,
        tempDir: tempDir.path,
        exeName: p.basename(Platform.resolvedExecutable),
        restart: restartAfter,
      );

      await File(scriptPath).writeAsString(script);
      await File(vbsPath).writeAsString(buildUpdaterVbs(scriptPath: scriptPath));

      // Launch the updater so it OUTLIVES this process. A directly-spawned
      // detached child stays inside our Windows job object, so the instant we
      // exit(0) the job's kill-on-close terminates the updater before it runs a
      // single line — this was the silent auto-update failure (app closed,
      // nothing happened, version unchanged, no updater.log written). Routing
      // through cmd's `start` re-parents the child outside our process tree so
      // it survives our exit. See [buildUpdaterLaunch].
      final launch = buildUpdaterLaunch(vbsPath: vbsPath);
      await (debugStartDetached ?? _startDetachedProcess)(
        launch.executable,
        launch.arguments,
      );

      // Last chance to get the update trace onto disk: exit(0) below kills the
      // process, so flush the session log before it goes (#140).
      appLog('update: updater launched; exiting');
      await appLogInstance?.flush();
      (debugExitApp ?? exit)(0);
    } catch (e) {
      // Clear the single-flight slot so the user can retry, and surface the
      // failure through the dialog's error body instead of a dead spinner.
      _applyFuture = null;
      _errorMessage =
          'Install failed. The update file may be corrupted — try downloading it again.';
      _phase = UpdatePhase.error;
      appLog('update: apply failed (${redactUrls('$e')})');
      notifyListeners();
      rethrow;
    }
  }

  static Future<void> _startDetachedProcess(
    String executable,
    List<String> arguments,
  ) =>
      Process.start(executable, arguments, mode: ProcessStartMode.detached);

  /// Verify [bytes] against the [expected] SHA-256 hex digest.
  ///
  /// No-op when [expected] is null or empty — older releases may not publish a
  /// hash, and we can only verify against what was provided. When a hash *is*
  /// present, a mismatch throws [UpdateVerificationException]. The comparison
  /// is case-insensitive, since hex digests may be published in either case,
  /// and the published value is trimmed so stray whitespace (templating or
  /// copy/paste) doesn't reject a valid download.
  void verifyChecksum(List<int> bytes, String? expected) =>
      verifyUpdateChecksum(bytes, expected);

  /// Extract [archive] into [extractDir], rejecting any entry whose resolved
  /// path would land outside [extractDir] (zip-slip). Throws
  /// [UnsafeArchiveEntryException] on the first unsafe entry, aborting the whole
  /// extraction — the entry names come from an attacker-influenced zip, so a
  /// `..`-traversal or absolute-path entry must never be written. The
  /// `archive` package performs no such check itself.
  static void extractArchive(Archive archive, Directory extractDir) {
    final root = p.normalize(extractDir.path);
    for (final file in archive) {
      final outPath = p.normalize(p.join(root, file.name));
      // Allow the root itself (e.g. a '.' entry); everything else must sit
      // strictly beneath it. `p.isWithin` rejects both `..`-traversal and a
      // sibling like `<root>_evil` that a bare `startsWith(root)` would miss.
      if (outPath != root && !p.isWithin(root, outPath)) {
        throw UnsafeArchiveEntryException(entryName: file.name);
      }
      if (file.isFile) {
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
  }

  /// Determine the Windows CPU architecture for asset selection.
  String get _windowsArch {
    final arch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    if (arch.toUpperCase().contains('ARM')) return 'arm64';
    return 'x64';
  }

  /// Naive semver comparison: returns true if [remote] > [local].
  ///
  /// Handles pre-release tags by stripping them for the numeric comparison
  /// and then comparing the tag strings if the numeric parts are equal.
  bool _isNewer(String remote, String local) => isVersionNewer(remote, local);

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Verify [bytes] against the [expected] SHA-256 hex digest.
///
/// No-op when [expected] is null or empty — older releases may not publish a
/// hash, and we can only verify against what was provided. When a hash *is*
/// present, a mismatch throws [UpdateVerificationException]. The comparison
/// is case-insensitive, since hex digests may be published in either case,
/// and the published value is trimmed so stray whitespace (templating or
/// copy/paste) doesn't reject a valid download.
///
/// Top-level (not a method) so the background isolate's closure captures no
/// service state (#197 P4).
void verifyUpdateChecksum(List<int> bytes, String? expected) {
  final want = expected?.trim();
  if (want == null || want.isEmpty) return;
  final actual = sha256.convert(bytes).toString();
  if (actual.toLowerCase() != want.toLowerCase()) {
    throw UpdateVerificationException(expected: want, actual: actual);
  }
}

/// Run the CPU-heavy verify + extract pipeline in a background isolate.
///
/// Reading and SHA-256-hashing a tens-of-MB zip, verifying its Ed25519
/// signature, and unzipping it are multi-second synchronous jobs; on the UI
/// isolate they froze the window for the whole "Install" (#197 P4). Parameters
/// are plain Strings so the closure crosses the isolate boundary cheaply.
///
/// The security gates run unchanged, in order, inside the worker:
///
/// 1. **Integrity** — the bytes must match the hash published in latest.json,
///    or the download was corrupted/tampered with.
/// 2. **Authenticity** — the checksum only proves the bytes match latest.json,
///    which lives in the same bucket as the zip; the Ed25519 signature is made
///    with a private key the bucket never sees, binds the advertised version
///    (anti-rollback), and fails closed.
/// 3. **Containment** — every zip entry must extract strictly inside
///    [extractDirPath] (zip-slip rejection).
///
/// Throws [UpdateVerificationException], [UpdateSignatureException], or
/// [UnsafeArchiveEntryException] — all sendable across the isolate boundary.
Future<void> verifyAndExtractUpdateInBackground({
  required String zipPath,
  required String version,
  required String? expectedSha256,
  required String? signature,
  required String extractDirPath,
  String publicKeyBase64 = releasePublicKeyBase64,
}) {
  return Isolate.run(() {
    final zipBytes = File(zipPath).readAsBytesSync();
    verifyUpdateChecksum(zipBytes, expectedSha256);
    verifyReleaseSignature(
      version,
      zipBytes,
      signature,
      publicKeyBase64: publicKeyBase64,
    );
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final extractDir = Directory(extractDirPath)..createSync(recursive: true);
    UpdateService.extractArchive(archive, extractDir);
  });
}

/// Build the VBScript shim that relaunches the PowerShell updater with a
/// window that is hidden from its very first frame.
///
/// `powershell -WindowStyle Hidden` alone is not enough: the console window is
/// created visible and PowerShell only hides it once its (slow) startup gets
/// that far, so users watched a console flash — or sit — on screen during the
/// update (#197). `WScript.Shell.Run` with window style `0` passes SW_HIDE at
/// process creation, so the console never appears at all. `False` = don't
/// wait: wscript exits immediately and the updater runs on alone.
/// `-WindowStyle Hidden` stays as belt-and-braces.
String buildUpdaterVbs({required String scriptPath}) {
  // VBScript escapes a quote inside a double-quoted string by doubling it.
  final quoted = scriptPath.replaceAll('"', '""');
  return '''
' MeowWatch updater launch shim — generated by the app, runs once, deleted by
' the updater script it starts.
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$quoted""", 0, False
''';
}

/// Build the command that launches the updater VBS shim so the updater
/// survives this process exiting AND never shows a console window.
///
/// MUST route through `cmd /c start` rather than spawning the child directly:
/// on Windows the app runs inside a job object, and a detached child we spawn
/// ourselves stays *in that job*. When we `exit(0)`, the job's kill-on-close
/// tears the child down before it executes a line — which is exactly why
/// auto-update appeared to do nothing (the app closed, the version never
/// changed, and no `updater.log` was ever written). `start` re-parents the
/// child outside our process tree so it outlives us.
///
/// `start` on a console app (like powershell) allocates a visible console
/// window for the whole run (#197); `wscript` is a GUI-subsystem executable,
/// so no console ever exists in this chain. The empty `''` is `start`'s
/// window-title argument — required, or `start` would mis-read a quoted path
/// as the title. `//B` (batch mode) suppresses wscript's script-error popups.
({String executable, List<String> arguments}) buildUpdaterLaunch({
  required String vbsPath,
}) {
  return (
    executable: 'cmd',
    arguments: [
      '/c',
      'start',
      '',
      'wscript',
      '//B',
      vbsPath,
    ],
  );
}

/// Build the PowerShell script that swaps the new files over the install and
/// restarts the app, after the current process exits.
///
/// Uses `robocopy` to copy [extractedDir] over [appDir], overwriting in place.
/// The previous version used `Copy-Item -Recurse`, which nests an existing
/// `data` folder into itself (`appDir\data\data\...`) — so the app's Dart code
/// (`data\app.so`) was never actually replaced and the app stayed on the old
/// version. robocopy merges subfolders correctly. It uses `/E` (add/overwrite),
/// not `/MIR`, on purpose: we don't want to delete files the new build happens
/// to omit, which is safer if the install folder ever holds anything extra.
///
/// robocopy exit codes 0–7 are success (8+ is failure); the script only
/// restarts when the copy succeeded, writes a log to [tempDir] for diagnosis,
/// and deletes its own script + temp payload at the end (keeping the log).
/// When [restart] is false the script swaps the files but does NOT relaunch the
/// app — used by the apply-on-close path (#62), where the user is quitting and
/// would not want the app to pop back open. The in-dialog "Install & Restart"
/// button keeps the default ([restart] true).
String buildUpdaterScript({
  required String extractedDir,
  required String appDir,
  required String tempDir,
  required String exeName,
  bool restart = true,
}) {
  final restartBlock = restart
      ? '''
# Restart the updated app from its own folder.
"[\$(Get-Date -Format o)] files updated; restarting" | Out-File -FilePath \$log -Append -Encoding utf8
Start-Process -FilePath "$appDir\\$exeName" -WorkingDirectory "$appDir"
'''
      : '''
# Files swapped; the app was closing, so do not relaunch (#62).
"[\$(Get-Date -Format o)] files updated; not restarting (app closed)" | Out-File -FilePath \$log -Append -Encoding utf8
''';
  // PowerShell double-quoted strings treat backslash literally (the escape char
  // is the backtick), so Windows paths go in verbatim — no escaping needed. The
  // `\\` separators below are single backslashes after Dart unescapes them.
  return '''
# MeowWatch Auto-Updater
# This script is generated by the app and runs after it exits.
\$ErrorActionPreference = 'Continue'
\$log = "$tempDir\\updater.log"
"[\$(Get-Date -Format o)] updater start" | Out-File -FilePath \$log -Encoding utf8

# Wait for the app to fully exit and release file locks.
Start-Sleep -Seconds 2

# Copy the new files over the install (overwrite in place). robocopy merges
# subfolders correctly; the old recursive copy nested an existing 'data' folder
# into itself, leaving the Dart app.so un-updated. /E adds and overwrites but
# does not delete files the new build omits. Exit codes 0-7 are success.
\$ok = \$false
for (\$i = 0; \$i -lt 10; \$i++) {
    robocopy "$extractedDir" "$appDir" /E /IS /IT /R:2 /W:1 /NP /NFL /NDL /NJH /NJS *>> \$log
    if (\$LASTEXITCODE -lt 8) { \$ok = \$true; break }
    "[\$(Get-Date -Format o)] robocopy attempt \$i failed (code \$LASTEXITCODE)" | Out-File -FilePath \$log -Append -Encoding utf8
    Start-Sleep -Seconds 1
}

if (-not \$ok) {
    "[\$(Get-Date -Format o)] update FAILED; not restarting" | Out-File -FilePath \$log -Append -Encoding utf8
    exit 1
}

$restartBlock
# Clean up temp files (keep the log). Also remove this script itself so it
# doesn't linger as an executable artifact; PowerShell has already read it into
# memory, so self-deletion is safe.
Start-Sleep -Seconds 2
Remove-Item -Path "$extractedDir" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tempDir\\update.zip" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tempDir\\updater.vbs" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
''';
}
