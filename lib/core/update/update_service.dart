import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

/// Result of comparing local version to remote.
enum UpdateStatus { upToDate, updateAvailable, checkFailed }

/// Checks for updates from the R2 release bucket, downloads, and applies them.
///
/// Flow:
///   1. `checkForUpdate()` → GET `{baseUrl}/releases/latest.json`
///   2. Compare remote version to [appVersion]
///   3. `downloadUpdate()` → stream zip to temp dir with progress callback
///   4. `applyUpdate()` → extract zip, write updater.ps1, launch it, exit app
class UpdateService {
  UpdateService({String? baseUrl}) : _baseUrl = baseUrl ?? updateBaseUrl;

  final String _baseUrl;
  final http.Client _client = http.Client();

  UpdateInfo? _latestUpdate;

  /// The most recently fetched update info, or null if not checked yet.
  UpdateInfo? get latestUpdate => _latestUpdate;

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

  /// Download the update zip to a temp directory, calling [onProgress] with
  /// a 0.0–1.0 fraction as bytes arrive.
  ///
  /// Returns the path to the downloaded zip file.
  Future<String> downloadUpdate(void Function(double progress) onProgress) async {
    final info = _latestUpdate;
    if (info == null) throw StateError('No update info — call checkForUpdate first');

    final uri = Uri.parse(info.downloadUrl);
    final request = http.Request('GET', uri);
    final streamed = await _client.send(request).timeout(
      const Duration(seconds: 120),
    );

    final total = streamed.contentLength ?? 0;
    var received = 0;

    final tempDir = Directory.systemTemp.createTempSync('meowwatch_update_');
    final zipFile = File(p.join(tempDir.path, 'update.zip'));
    final sink = zipFile.openWrite();

    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
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

    final script = _buildUpdaterScript(
      extractedDir: extractDir.path,
      appDir: appDir,
      tempDir: tempDir.path,
      exeName: p.basename(Platform.resolvedExecutable),
    );

    await File(scriptPath).writeAsString(script);

    // Launch the PowerShell script detached, then exit.
    await Process.start(
      'powershell',
      ['-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      mode: ProcessStartMode.detached,
    );

    exit(0);
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

  /// Build the PowerShell script that performs the file swap.
  String _buildUpdaterScript({
    required String extractedDir,
    required String appDir,
    required String tempDir,
    required String exeName,
  }) {
    // Escape backslashes for PowerShell string literals.
    String esc(String s) => s.replaceAll(r'\', r'\\');
    return '''
# MeowWatch Auto-Updater
# This script is generated by the app and runs after it exits.

# Wait for the app to fully exit.
Start-Sleep -Seconds 2

# Retry loop in case the process takes a moment to release file locks.
for (\$i = 0; \$i -lt 10; \$i++) {
    try {
        Copy-Item -Path "${esc(extractedDir)}\\*" -Destination "${esc(appDir)}" -Recurse -Force -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}

# Restart the updated app.
Start-Process "${esc(appDir)}\\$exeName"

# Clean up temp files.
Start-Sleep -Seconds 2
Remove-Item -Path "${esc(tempDir)}" -Recurse -Force -ErrorAction SilentlyContinue
''';
  }

  void dispose() {
    _client.close();
  }
}
