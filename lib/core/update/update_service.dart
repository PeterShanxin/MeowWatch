import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../app_version.dart';

/// Metadata about an available update.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.releaseNotes,
    required this.releaseDate,
  });

  final String version;
  final String downloadUrl;
  final String? sha256;
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

/// Checks for updates from the R2 release bucket, downloads, and applies them.
///
/// Flow:
///   1. `checkForUpdate()` → GET `{baseUrl}/releases/latest.json`
///   2. Compare remote version to [appVersion]
///   3. `downloadUpdate()` → stream zip to temp dir with progress callback
///   4. `applyUpdate()` → verify SHA-256, extract zip, write updater.ps1,
///      launch it, exit app
class UpdateService extends ChangeNotifier {
  static final UpdateService instance = UpdateService._();

  @visibleForTesting
  UpdateService.forTest({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? updateBaseUrl,
        _client = client ?? http.Client();

  UpdateService._({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? updateBaseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

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
      if (response.statusCode != 200) return UpdateStatus.checkFailed;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = json['version'] as String;

      // Determine the correct asset key for this machine's architecture.
      final arch = _windowsArch;
      final assets = json['assets'] as Map<String, dynamic>?;
      if (assets == null) return UpdateStatus.checkFailed;

      final assetKey = 'windows-$arch';
      final asset = assets[assetKey] as Map<String, dynamic>?;
      if (asset == null) return UpdateStatus.checkFailed;

      _latestUpdate = UpdateInfo(
        version: remoteVersion,
        downloadUrl: asset['url'] as String,
        sha256: asset['sha256'] as String?,
        releaseNotes: (json['release_notes'] as String?) ?? '',
        releaseDate: (json['release_date'] as String?) ?? '',
      );

      if (_isNewer(remoteVersion, appVersion)) {
        return UpdateStatus.updateAvailable;
      }
      return UpdateStatus.upToDate;
    } on Exception {
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
        phase == UpdatePhase.readyToInstall) {
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

    try {
      final path = await downloadUpdate((received, total) {
        _downloadReceivedBytes = received;
        _downloadTotalBytes = total;
        // Only a real fraction when the total is known; otherwise leave progress
        // at 0 and let the UI render an indeterminate bar (#63).
        _downloadProgress =
            (total != null && total > 0) ? received / total : 0;
        notifyListeners();
      });
      _downloadedZipPath = path;
      _phase = UpdatePhase.readyToInstall;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Download failed: $e';
      _phase = UpdatePhase.error;
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
  Future<void> applyUpdate(String zipPath) async {
    final zipBytes = await File(zipPath).readAsBytes();

    // Integrity gate: confirm the bytes match the hash published in
    // latest.json before we extract or run anything. A mismatch means the
    // download was corrupted or tampered with — abort instead of installing.
    verifyChecksum(zipBytes, _latestUpdate?.sha256);

    final archive = ZipDecoder().decodeBytes(zipBytes);

    final tempDir = Directory(p.dirname(zipPath));
    final extractDir = Directory(p.join(tempDir.path, 'extracted'));
    extractDir.createSync(recursive: true);

    for (final file in archive) {
      final outPath = p.join(extractDir.path, file.name);
      if (file.isFile) {
        final outFile = File(outPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }

    // The app directory is the folder containing the current executable.
    final appDir = p.dirname(Platform.resolvedExecutable);
    final scriptPath = p.join(tempDir.path, 'updater.ps1');

    final script = buildUpdaterScript(
      extractedDir: extractDir.path,
      appDir: appDir,
      tempDir: tempDir.path,
      exeName: p.basename(Platform.resolvedExecutable),
    );

    await File(scriptPath).writeAsString(script);

    // Launch the updater so it OUTLIVES this process. A directly-spawned
    // detached child stays inside our Windows job object, so the instant we
    // exit(0) the job's kill-on-close terminates the updater before it runs a
    // single line — this was the silent auto-update failure (app closed,
    // nothing happened, version unchanged, no updater.log written). Routing
    // through cmd's `start` re-parents PowerShell outside our process tree so
    // it survives our exit. See [buildUpdaterLaunch].
    final launch = buildUpdaterLaunch(scriptPath: scriptPath);
    await Process.start(
      launch.executable,
      launch.arguments,
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  /// Verify [bytes] against the [expected] SHA-256 hex digest.
  ///
  /// No-op when [expected] is null or empty — older releases may not publish a
  /// hash, and we can only verify against what was provided. When a hash *is*
  /// present, a mismatch throws [UpdateVerificationException]. The comparison
  /// is case-insensitive, since hex digests may be published in either case,
  /// and the published value is trimmed so stray whitespace (templating or
  /// copy/paste) doesn't reject a valid download.
  void verifyChecksum(List<int> bytes, String? expected) {
    final want = expected?.trim();
    if (want == null || want.isEmpty) return;
    final actual = sha256.convert(bytes).toString();
    if (actual.toLowerCase() != want.toLowerCase()) {
      throw UpdateVerificationException(expected: want, actual: actual);
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
  bool _isNewer(String remote, String local) {
    final rParts = _parseSemver(remote);
    final lParts = _parseSemver(local);

    for (var i = 0; i < 3; i++) {
      if (rParts.$1[i] > lParts.$1[i]) return true;
      if (rParts.$1[i] < lParts.$1[i]) return false;
    }

    // Numeric parts equal — compare pre-release: no pre-release > any pre-release.
    if (rParts.$2 == null && lParts.$2 != null) return true;
    if (rParts.$2 != null && lParts.$2 == null) return false;
    if (rParts.$2 != null && lParts.$2 != null) {
      return rParts.$2!.compareTo(lParts.$2!) > 0;
    }
    return false; // Exactly equal.
  }

  /// Parse "0.1.0-alpha" → ([0, 1, 0], "alpha").
  (List<int>, String?) _parseSemver(String v) {
    // Strip leading 'v' if present.
    final s = v.startsWith('v') ? v.substring(1) : v;
    final dashIdx = s.indexOf('-');
    final numPart = dashIdx >= 0 ? s.substring(0, dashIdx) : s;
    final prePart = dashIdx >= 0 ? s.substring(dashIdx + 1) : null;
    final nums = numPart.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return (nums, prePart);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Build the command that launches the updater script so it survives this
/// process exiting.
///
/// MUST route through `cmd /c start` rather than spawning `powershell`
/// directly: on Windows the app runs inside a job object, and a detached child
/// we spawn ourselves stays *in that job*. When we `exit(0)`, the job's
/// kill-on-close tears the child down before it executes a line — which is
/// exactly why auto-update appeared to do nothing (the app closed, the version
/// never changed, and no `updater.log` was ever written). `start` re-parents
/// PowerShell outside our process tree so it outlives us.
///
/// The empty `''` is `start`'s window-title argument — required, or `start`
/// would mis-read a quoted path as the title. `-WindowStyle Hidden` keeps the
/// updater console from flashing on screen during the swap.
({String executable, List<String> arguments}) buildUpdaterLaunch({
  required String scriptPath,
}) {
  return (
    executable: 'cmd',
    arguments: [
      '/c',
      'start',
      '',
      'powershell',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      scriptPath,
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
String buildUpdaterScript({
  required String extractedDir,
  required String appDir,
  required String tempDir,
  required String exeName,
}) {
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

# Restart the updated app from its own folder.
"[\$(Get-Date -Format o)] files updated; restarting" | Out-File -FilePath \$log -Append -Encoding utf8
Start-Process -FilePath "$appDir\\$exeName" -WorkingDirectory "$appDir"

# Clean up temp files (keep the log). Also remove this script itself so it
# doesn't linger as an executable artifact; PowerShell has already read it into
# memory, so self-deletion is safe.
Start-Sleep -Seconds 2
Remove-Item -Path "$extractedDir" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tempDir\\update.zip" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
''';
}
