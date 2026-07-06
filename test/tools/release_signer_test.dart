import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/release_signature.dart';

// The release signer is a plain-Dart CLI under tool/, not shipped in the app.
// Import it directly to prove its crypto round-trips with the in-app verifier.
import '../../tool/release_signer.dart';

void main() {
  final zipBytes = Uint8List.fromList(
    List<int>.generate(2048, (i) => (i * 17 + 3) & 0xff),
  );
  const version = '0.41.0-alpha';

  test('generateReleaseKeypair yields a 32-byte seed and public key', () {
    final kp = generateReleaseKeypair();
    expect(base64.decode(kp.privateSeedBase64).length, 32);
    expect(base64.decode(kp.publicKeyBase64).length, 32);
  });

  test('publicKeyForSeed derives the keypair\'s public half', () {
    final kp = generateReleaseKeypair();
    expect(publicKeyForSeed(kp.privateSeedBase64), kp.publicKeyBase64);
  });

  test('a signature from signRelease verifies under the derived key', () {
    final kp = generateReleaseKeypair();
    final sig = signRelease(
      privateSeedBase64: kp.privateSeedBase64,
      version: version,
      zipBytes: zipBytes,
    );
    expect(
      isReleaseSignatureValid(
        version: version,
        bytes: zipBytes,
        signatureBase64: sig,
        publicKeyBase64: kp.publicKeyBase64,
      ),
      isTrue,
    );
  });

  test('the signature does not verify under a different version', () {
    final kp = generateReleaseKeypair();
    final sig = signRelease(
      privateSeedBase64: kp.privateSeedBase64,
      version: version,
      zipBytes: zipBytes,
    );
    expect(
      isReleaseSignatureValid(
        version: '9.9.9',
        bytes: zipBytes,
        signatureBase64: sig,
        publicKeyBase64: kp.publicKeyBase64,
      ),
      isFalse,
    );
  });

  test('the signature does not verify over tampered bytes', () {
    final kp = generateReleaseKeypair();
    final sig = signRelease(
      privateSeedBase64: kp.privateSeedBase64,
      version: version,
      zipBytes: zipBytes,
    );
    final tampered = Uint8List.fromList(zipBytes)..[0] ^= 0x01;
    expect(
      isReleaseSignatureValid(
        version: version,
        bytes: tampered,
        signatureBase64: sig,
        publicKeyBase64: kp.publicKeyBase64,
      ),
      isFalse,
    );
  });

  test('signRelease rejects a wrong-length seed', () {
    expect(
      () => signRelease(
        privateSeedBase64: base64.encode(Uint8List(16)),
        version: version,
        zipBytes: zipBytes,
      ),
      throwsArgumentError,
    );
  });
}
