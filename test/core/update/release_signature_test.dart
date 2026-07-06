import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/release_signature.dart';

/// Exercises the Ed25519 authenticity gate on the auto-update path. The signing
/// half (holding the private key) is never in the app — these tests mint an
/// ephemeral keypair with the same library the release signer uses and prove the
/// verifier accepts only a signature made by that key over exactly this version
/// and these bytes.
void main() {
  // A stand-in "release zip" — content is irrelevant, only the bytes matter.
  final zipBytes = Uint8List.fromList(
    List<int>.generate(4096, (i) => (i * 31 + 7) & 0xff),
  );
  const version = '0.41.0-alpha';

  late ed.KeyPair keyPair;
  late String publicKeyB64;
  late String signatureB64;

  String signFor(String v, List<int> bytes) {
    final sha = sha256.convert(bytes).toString();
    final msg = utf8.encode(releaseSignedMessage(version: v, sha256Hex: sha));
    return base64.encode(ed.sign(keyPair.privateKey, Uint8List.fromList(msg)));
  }

  setUp(() {
    keyPair = ed.generateKey();
    publicKeyB64 = base64.encode(keyPair.publicKey.bytes);
    signatureB64 = signFor(version, zipBytes);
  });

  group('isReleaseSignatureValid', () {
    test('accepts a genuine signature for the exact version and bytes', () {
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: zipBytes,
          signatureBase64: signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        isTrue,
      );
    });

    test('rejects the signature under a different (rolled-back) version', () {
      // An attacker replays an old signed zip but advertises a higher version.
      expect(
        isReleaseSignatureValid(
          version: '9.9.9',
          bytes: zipBytes,
          signatureBase64: signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        isFalse,
      );
    });

    test('rejects a signature when even one byte is tampered', () {
      final tampered = Uint8List.fromList(zipBytes)..[0] ^= 0x01;
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: tampered,
          signatureBase64: signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        isFalse,
      );
    });

    test('rejects a valid signature made by a different key', () {
      final otherKey = base64.encode(ed.generateKey().publicKey.bytes);
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: zipBytes,
          signatureBase64: signatureB64,
          publicKeyBase64: otherKey,
        ),
        isFalse,
      );
    });

    test('rejects a null, empty, or whitespace signature', () {
      for (final sig in <String?>[null, '', '   ', '\n']) {
        expect(
          isReleaseSignatureValid(
            version: version,
            bytes: zipBytes,
            signatureBase64: sig,
            publicKeyBase64: publicKeyB64,
          ),
          isFalse,
          reason: 'signature ${jsonEncode(sig)} must not verify',
        );
      }
    });

    test('rejects a malformed (non-base64) signature', () {
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: zipBytes,
          signatureBase64: 'not!valid!base64!!',
          publicKeyBase64: publicKeyB64,
        ),
        isFalse,
      );
    });

    test('rejects a well-formed base64 signature of the wrong length', () {
      final shortSig = base64.encode(Uint8List(32)); // valid b64, not 64 bytes
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: zipBytes,
          signatureBase64: shortSig,
          publicKeyBase64: publicKeyB64,
        ),
        isFalse,
      );
    });

    test('rejects a wrong-length public key without throwing', () {
      final shortKey = base64.encode(Uint8List(16));
      expect(
        isReleaseSignatureValid(
          version: version,
          bytes: zipBytes,
          signatureBase64: signatureB64,
          publicKeyBase64: shortKey,
        ),
        isFalse,
      );
    });
  });

  group('verifyReleaseSignature (fail-closed)', () {
    test('returns normally for a genuine signature', () {
      expect(
        () => verifyReleaseSignature(
          version,
          zipBytes,
          signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        returnsNormally,
      );
    });

    test('throws when no signature was published', () {
      expect(
        () => verifyReleaseSignature(
          version,
          zipBytes,
          null,
          publicKeyBase64: publicKeyB64,
        ),
        throwsA(isA<UpdateSignatureException>()),
      );
    });

    test('throws when the advertised version does not match the signature', () {
      expect(
        () => verifyReleaseSignature(
          '9.9.9',
          zipBytes,
          signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        throwsA(isA<UpdateSignatureException>()),
      );
    });

    test('throws when the bytes do not match', () {
      final tampered = Uint8List.fromList(zipBytes)..[10] ^= 0xff;
      expect(
        () => verifyReleaseSignature(
          version,
          tampered,
          signatureB64,
          publicKeyBase64: publicKeyB64,
        ),
        throwsA(isA<UpdateSignatureException>()),
      );
    });
  });

  test('baked-in releasePublicKeyBase64 is a well-formed 32-byte key', () {
    final decoded = base64.decode(releasePublicKeyBase64);
    expect(decoded.length, ed.PublicKeySize);
  });
}
