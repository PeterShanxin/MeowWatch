import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Base64-encoded Ed25519 public key (32 bytes) that every genuine MeowWatch
/// release is signed against.
///
/// The matching private key never touches this repo, GitHub, or the R2 bucket —
/// it lives only on the release PC (see `tool/release_signer.dart`). That is the
/// whole point: the download's SHA-256 lives in the same bucket as the zip, so
/// anyone who can swap the zip can swap the hash to match. A signature made with
/// a key the bucket never sees can't be forged that way, so it — not the hash —
/// is the real trust root.
///
/// Rotating this key means shipping a build carrying the NEW key BEFORE the first
/// release signed by it, or existing installs can't verify the update and will
/// (correctly) refuse it.
const String releasePublicKeyBase64 = 'L/Qi3IEXz8zP25W150UUNofXvCtHmFduO1upDKm7Wqs=';

/// Thrown when a downloaded update is missing a signature or its signature does
/// not verify against [releasePublicKeyBase64].
///
/// The auto-updater treats this as fatal and refuses to install: a bad or absent
/// signature means the bytes were not produced by the holder of the release key
/// (a poisoned bucket, a corrupted download, or an unsigned build), so extracting
/// and launching them would run untrusted code.
class UpdateSignatureException implements Exception {
  const UpdateSignatureException(this.reason);

  final String reason;

  @override
  String toString() => 'Update signature verification failed: $reason';
}

/// Pure predicate: does [signatureBase64] verify [bytes] under [publicKeyBase64]?
///
/// Returns false — never throws — for every failure mode (absent or blank
/// signature, malformed base64, wrong-length key or signature, or a genuine
/// mismatch) so callers can treat "not provably authentic" as a single boolean.
bool isReleaseSignatureValid({
  required List<int> bytes,
  required String? signatureBase64,
  String publicKeyBase64 = releasePublicKeyBase64,
}) {
  final sig = signatureBase64?.trim();
  if (sig == null || sig.isEmpty) return false;

  Uint8List sigBytes;
  Uint8List keyBytes;
  try {
    sigBytes = base64.decode(sig);
    keyBytes = base64.decode(publicKeyBase64.trim());
  } on FormatException {
    return false;
  }
  if (sigBytes.length != ed.SignatureSize ||
      keyBytes.length != ed.PublicKeySize) {
    return false;
  }

  try {
    return ed.verify(ed.PublicKey(keyBytes), Uint8List.fromList(bytes), sigBytes);
  } catch (_) {
    // ed.verify throws ArgumentError on a bad key length (already guarded above)
    // and could in principle throw on malformed group elements; treat any throw
    // as "not verifiable".
    return false;
  }
}

/// Fail-closed wrapper used on the install path: throws
/// [UpdateSignatureException] unless [signatureBase64] authenticates [bytes]
/// against [publicKeyBase64]. Distinguishes "no signature" from "wrong
/// signature" only for the log message; both abort the update.
void verifyReleaseSignature(
  List<int> bytes,
  String? signatureBase64, {
  String publicKeyBase64 = releasePublicKeyBase64,
}) {
  final sig = signatureBase64?.trim();
  if (sig == null || sig.isEmpty) {
    throw const UpdateSignatureException(
      'no signature published for this release',
    );
  }
  if (!isReleaseSignatureValid(
    bytes: bytes,
    signatureBase64: sig,
    publicKeyBase64: publicKeyBase64,
  )) {
    throw const UpdateSignatureException(
      'signature does not match the release key',
    );
  }
}
