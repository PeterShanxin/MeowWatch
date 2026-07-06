import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

/// The domain-separated message that the release signature actually covers.
///
/// The signature binds the **version** and the **zip's SHA-256** together, not
/// just the raw bytes. Signing bytes alone would let a compromised bucket replay
/// an old, genuinely-signed zip under a faked higher `version` in latest.json (a
/// rollback/downgrade attack) — a bytes-only signature would still verify, and
/// the app decides "newer?" from that same unsigned version field. Folding the
/// advertised version into the signed message means the app rejects any zip whose
/// claimed version isn't the one that was signed.
///
/// A fixed prefix provides domain separation (a signature can't be repurposed for
/// another protocol). The signer (`tool/release_signer.dart`) and the verifier
/// below build this string identically. SHA-256 is normalised to lower-case hex.
String releaseSignedMessage({
  required String version,
  required String sha256Hex,
}) =>
    'meowwatch-release-v1\n$version\n${sha256Hex.toLowerCase()}';

/// Thrown when a downloaded update is missing a signature or its signature does
/// not verify against [releasePublicKeyBase64] for the advertised version.
///
/// The auto-updater treats this as fatal and refuses to install: a bad or absent
/// signature means the bytes were not produced by the holder of the release key
/// for this version (a poisoned/rolled-back bucket, a corrupted download, or an
/// unsigned build), so extracting and launching them would run untrusted code.
class UpdateSignatureException implements Exception {
  const UpdateSignatureException(this.reason);

  final String reason;

  @override
  String toString() => 'Update signature verification failed: $reason';
}

/// Pure predicate: is [signatureBase64] a valid release signature for [bytes]
/// advertised as [version], under [publicKeyBase64]?
///
/// Returns false — never throws — for every failure mode (absent or blank
/// signature, malformed base64, wrong-length key or signature, a version that
/// doesn't match what was signed, or tampered bytes) so callers can treat "not
/// provably authentic" as a single boolean.
bool isReleaseSignatureValid({
  required String version,
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

  final sha = sha256.convert(bytes).toString();
  final message = Uint8List.fromList(
    utf8.encode(releaseSignedMessage(version: version, sha256Hex: sha)),
  );
  try {
    return ed.verify(ed.PublicKey(keyBytes), message, sigBytes);
  } catch (_) {
    // ed.verify throws ArgumentError on a bad key length (guarded above) and
    // could in principle throw on malformed group elements; treat any throw as
    // "not verifiable".
    return false;
  }
}

/// Fail-closed wrapper used on the install path: throws
/// [UpdateSignatureException] unless [signatureBase64] authenticates [bytes] as
/// [version] against [publicKeyBase64]. Distinguishes "no signature" from "wrong
/// signature" only for the log message; both abort the update.
void verifyReleaseSignature(
  String version,
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
    version: version,
    bytes: bytes,
    signatureBase64: sig,
    publicKeyBase64: publicKeyBase64,
  )) {
    throw const UpdateSignatureException(
      'signature does not match the release version and bytes',
    );
  }
}
