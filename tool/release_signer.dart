// Release signing tool for MeowWatch auto-updates.
//
// Plain-Dart CLI (imports no Flutter) so it runs under `dart run` on the release
// PC / CI. Two jobs:
//
//   dart run tool/release_signer.dart genkey <out-seed-file>
//       Generate a fresh Ed25519 keypair. Writes the 32-byte private seed
//       (base64) to <out-seed-file> and prints the public key (base64) to
//       stdout — paste it into `releasePublicKeyBase64` in
//       lib/core/update/release_signature.dart.
//
//   dart run tool/release_signer.dart sign <seed-file> <zip-path> <sig-out-path>
//       Sign the release zip's bytes. Writes the base64 signature to
//       <sig-out-path>. Fails if the seed's public half does not match the key
//       baked into the app, so an accidental wrong-key signing can't ship a
//       release the app would refuse.
//
// The private seed lives ONLY on the release PC (never in the repo, GitHub
// secrets, or R2). See docs/AGENT_GUIDE.md → Release signing.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:meowwatch/core/update/release_signature.dart' as rel;

/// A freshly generated release keypair, base64-encoded for storage/pasting.
class ReleaseKeypair {
  const ReleaseKeypair({
    required this.privateSeedBase64,
    required this.publicKeyBase64,
  });

  /// 32-byte RFC 8032 seed — the private key. Keep off the repo/GitHub/R2.
  final String privateSeedBase64;

  /// 32-byte public key — safe to commit into the app.
  final String publicKeyBase64;
}

/// Generate a new Ed25519 release keypair using secure random.
ReleaseKeypair generateReleaseKeypair() {
  final kp = ed.generateKey();
  return ReleaseKeypair(
    privateSeedBase64: base64.encode(ed.seed(kp.privateKey)),
    publicKeyBase64: base64.encode(kp.publicKey.bytes),
  );
}

/// Derive the base64 public key that corresponds to [privateSeedBase64].
String publicKeyForSeed(String privateSeedBase64) {
  final priv = _privateKeyFromSeed(privateSeedBase64);
  return base64.encode(ed.public(priv).bytes);
}

/// Sign [zipBytes] with the 32-byte seed [privateSeedBase64]; returns the
/// base64-encoded 64-byte signature (the value that goes into latest.json).
String signReleaseZip({
  required String privateSeedBase64,
  required List<int> zipBytes,
}) {
  final priv = _privateKeyFromSeed(privateSeedBase64);
  final sig = ed.sign(priv, Uint8List.fromList(zipBytes));
  return base64.encode(sig);
}

ed.PrivateKey _privateKeyFromSeed(String privateSeedBase64) {
  final seed = base64.decode(privateSeedBase64.trim());
  if (seed.length != ed.SeedSize) {
    throw ArgumentError(
      'release seed must be ${ed.SeedSize} bytes, got ${seed.length}',
    );
  }
  return ed.newKeyFromSeed(Uint8List.fromList(seed));
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usageAndExit();
  }
  switch (args.first) {
    case 'genkey':
      _genkey(args.sublist(1));
    case 'sign':
      await _sign(args.sublist(1));
    default:
      _usageAndExit();
  }
}

void _genkey(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: genkey <out-seed-file>');
    exit(2);
  }
  final outFile = File(args[0]);
  if (outFile.existsSync()) {
    stderr.writeln(
      'refusing to overwrite existing key file ${outFile.path} '
      '(delete it first if you really mean to rotate the key)',
    );
    exit(2);
  }
  final kp = generateReleaseKeypair();
  outFile.writeAsStringSync(kp.privateSeedBase64);
  stdout
    ..writeln('Private seed written to ${outFile.path}')
    ..writeln('KEEP THIS FILE OFF the repo, GitHub, and R2. Back it up safely.')
    ..writeln('')
    ..writeln('Paste this into releasePublicKeyBase64 '
        '(lib/core/update/release_signature.dart):')
    ..writeln(kp.publicKeyBase64);
}

Future<void> _sign(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: sign <seed-file> <zip-path> <sig-out-path>');
    exit(2);
  }
  final seedFile = File(args[0]);
  final zipFile = File(args[1]);
  final sigOut = File(args[2]);

  if (!seedFile.existsSync()) {
    stderr.writeln('release key file not found: ${seedFile.path}');
    exit(1);
  }
  if (!zipFile.existsSync()) {
    stderr.writeln('release zip not found: ${zipFile.path}');
    exit(1);
  }

  final seedB64 = seedFile.readAsStringSync().trim();

  // Guard: the seed we're signing with MUST correspond to the public key the
  // app ships. Signing with the wrong key would produce a release every install
  // refuses — fail loudly here instead of at every user's updater.
  final derivedPublic = publicKeyForSeed(seedB64);
  if (derivedPublic != rel.releasePublicKeyBase64.trim()) {
    stderr.writeln(
      'release key mismatch: this seed\'s public key does not match '
      'releasePublicKeyBase64 baked into the app. Refusing to sign — the '
      'resulting release would fail verification on every install.',
    );
    exit(1);
  }

  final zipBytes = await zipFile.readAsBytes();
  final sigB64 = signReleaseZip(privateSeedBase64: seedB64, zipBytes: zipBytes);

  // Self-check: the signature we just produced must verify under the baked key.
  if (!rel.isReleaseSignatureValid(bytes: zipBytes, signatureBase64: sigB64)) {
    stderr.writeln('internal error: freshly-made signature failed to verify');
    exit(1);
  }

  sigOut.writeAsStringSync(sigB64);
  stdout.writeln('Signed ${zipFile.path} → ${sigOut.path} (${sigB64.length} b64 chars)');
}

Never _usageAndExit() {
  stderr.writeln(
    'usage:\n'
    '  dart run tool/release_signer.dart genkey <out-seed-file>\n'
    '  dart run tool/release_signer.dart sign <seed-file> <zip-path> <sig-out-path>',
  );
  exit(2);
}
