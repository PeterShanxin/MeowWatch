import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/update/release_signature.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:path/path.dart' as p;

/// Everything a test needs to drive a real `applyUpdate` run without touching
/// the process: a service whose latest.json advertises a genuinely signed test
/// zip on disk, plus observable seams for the detached-updater launch and the
/// process exit (#197 P4 / #205 review).
class ApplyHarness {
  ApplyHarness._(this.service, this.zipPath, this._tempDir);

  final UpdateService service;

  /// Path of the signed test zip — pass to `applyUpdate`.
  final String zipPath;

  final Directory _tempDir;

  /// When the harness was created with `holdLauncher: true`, the updater
  /// launch awaits this gate — complete it to let the apply run to its end.
  final launchGate = Completer<void>();

  /// One entry per detached-updater launch: `[executable, ...arguments]`.
  final launches = <List<String>>[];

  /// Exit codes the apply requested (in place of a real `exit`).
  final exits = <int>[];

  void dispose() {
    service.dispose();
    disposeTempDirOnly();
  }

  /// Delete only the temp payload — for tests whose widget owns (and already
  /// disposes) the service, e.g. `UpdateDialog` with an injected service.
  void disposeTempDirOnly() {
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  }

  static Future<ApplyHarness> create({
    bool holdLauncher = false,
    bool corruptSignature = false,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('mw_apply_harness_');

    final content = Uint8List.fromList(utf8.encode('exe'));
    final archive = Archive()
      ..addFile(ArchiveFile('meowwatch.exe', content.length, content));
    final zipBytes = ZipEncoder().encode(archive);
    final zipFile = File(p.join(tempDir.path, 'update.zip'))
      ..writeAsBytesSync(zipBytes);

    const version = '99.0.0';
    final sha = sha256.convert(zipBytes).toString();
    final keyPair = ed.generateKey();
    final msg = utf8.encode(
      releaseSignedMessage(version: version, sha256Hex: sha),
    );
    final sig = corruptSignature
        ? base64.encode(List<int>.filled(64, 7))
        : base64.encode(ed.sign(keyPair.privateKey, Uint8List.fromList(msg)));

    final latest = jsonEncode({
      'version': version,
      'assets': {
        'windows-x64': {
          'url': 'https://example.test/a.zip',
          'sha256': sha,
          'sig': sig,
        },
        'windows-arm64': {
          'url': 'https://example.test/a.zip',
          'sha256': sha,
          'sig': sig,
        },
      },
    });
    final client = MockClient((req) async {
      if (req.url.path.endsWith('latest.json')) {
        return http.Response(latest, 200);
      }
      return http.Response('', 404);
    });

    final service = UpdateService.forTest(
      baseUrl: 'https://example.test',
      client: client,
      publicKeyBase64: base64.encode(keyPair.publicKey.bytes),
    );
    final harness = ApplyHarness._(service, zipFile.path, tempDir);
    service.debugStartDetached = (executable, arguments) async {
      harness.launches.add([executable, ...arguments]);
      if (holdLauncher) await harness.launchGate.future;
    };
    service.debugExitApp = (code) => harness.exits.add(code);

    if (await service.checkForUpdate() != UpdateStatus.updateAvailable) {
      throw StateError('harness: expected updateAvailable from latest.json');
    }
    return harness;
  }
}
