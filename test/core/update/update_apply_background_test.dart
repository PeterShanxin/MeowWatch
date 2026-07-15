import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/release_signature.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:path/path.dart' as p;

/// The verify + extract pipeline that `applyUpdate` runs must not execute on
/// the UI isolate (#197 P4): hashing tens of MB, Ed25519 verify, and unzipping
/// are multi-second synchronous work that froze the window during "Install".
/// [verifyAndExtractUpdateInBackground] is the isolate-friendly entry point —
/// all-String parameters, and every security gate (checksum, signature,
/// zip-slip) still enforced inside it.
void main() {
  late Directory tempRoot;
  late ed.KeyPair keyPair;
  late String publicKeyB64;

  const version = '9.9.9-alpha';

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mw_apply_bg_test_');
    keyPair = ed.generateKey();
    publicKeyB64 = base64.encode(keyPair.publicKey.bytes);
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// Write a zip holding [entries] (name → content) to disk; returns its path.
  String writeZip(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    final zipBytes = ZipEncoder().encode(archive);
    final zipFile = File(p.join(tempRoot.path, 'update.zip'))
      ..writeAsBytesSync(zipBytes);
    return zipFile.path;
  }

  String shaOf(String zipPath) =>
      sha256.convert(File(zipPath).readAsBytesSync()).toString();

  String signFor(String v, String zipPath) {
    final msg = utf8.encode(
      releaseSignedMessage(version: v, sha256Hex: shaOf(zipPath)),
    );
    return base64.encode(ed.sign(keyPair.privateKey, Uint8List.fromList(msg)));
  }

  String extractDirPath() => p.join(tempRoot.path, 'extracted');

  test('happy path: verifies checksum + signature and extracts the payload',
      () async {
    final zipPath = writeZip({
      'meowwatch.exe': 'exe',
      'data/app.so': 'so',
    });

    await verifyAndExtractUpdateInBackground(
      zipPath: zipPath,
      version: version,
      expectedSha256: shaOf(zipPath),
      signature: signFor(version, zipPath),
      extractDirPath: extractDirPath(),
      publicKeyBase64: publicKeyB64,
    );

    expect(
      File(p.join(extractDirPath(), 'meowwatch.exe')).readAsStringSync(),
      'exe',
    );
    expect(
      File(p.join(extractDirPath(), 'data', 'app.so')).readAsStringSync(),
      'so',
    );
  });

  test('checksum mismatch throws and extracts nothing', () async {
    final zipPath = writeZip({'meowwatch.exe': 'exe'});

    await expectLater(
      verifyAndExtractUpdateInBackground(
        zipPath: zipPath,
        version: version,
        expectedSha256: 'deadbeef',
        signature: signFor(version, zipPath),
        extractDirPath: extractDirPath(),
        publicKeyBase64: publicKeyB64,
      ),
      throwsA(isA<UpdateVerificationException>()),
    );
    expect(Directory(extractDirPath()).existsSync(), isFalse);
  });

  test('bad signature throws (fail closed) and extracts nothing', () async {
    final zipPath = writeZip({'meowwatch.exe': 'exe'});
    // Signature made for a DIFFERENT version — must not verify.
    final wrongSig = signFor('0.0.1', zipPath);

    await expectLater(
      verifyAndExtractUpdateInBackground(
        zipPath: zipPath,
        version: version,
        expectedSha256: shaOf(zipPath),
        signature: wrongSig,
        extractDirPath: extractDirPath(),
        publicKeyBase64: publicKeyB64,
      ),
      throwsA(isA<UpdateSignatureException>()),
    );
    expect(Directory(extractDirPath()).existsSync(), isFalse);
  });

  test('missing signature throws (fail closed)', () async {
    final zipPath = writeZip({'meowwatch.exe': 'exe'});

    await expectLater(
      verifyAndExtractUpdateInBackground(
        zipPath: zipPath,
        version: version,
        expectedSha256: shaOf(zipPath),
        signature: null,
        extractDirPath: extractDirPath(),
        publicKeyBase64: publicKeyB64,
      ),
      throwsA(isA<UpdateSignatureException>()),
    );
  });

  test('zip-slip entry still rejected inside the background pipeline',
      () async {
    final zipPath = writeZip({'../mw_bg_escaped.txt': 'pwned'});
    final escaped = File(p.join(tempRoot.path, 'mw_bg_escaped.txt'));

    await expectLater(
      verifyAndExtractUpdateInBackground(
        zipPath: zipPath,
        version: version,
        expectedSha256: shaOf(zipPath),
        signature: signFor(version, zipPath),
        extractDirPath: extractDirPath(),
        publicKeyBase64: publicKeyB64,
      ),
      throwsA(isA<UnsafeArchiveEntryException>()),
    );
    expect(escaped.existsSync(), isFalse);
  });
}
