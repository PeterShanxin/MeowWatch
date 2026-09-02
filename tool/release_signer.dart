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
//   dart run tool/release_signer.dart sign --version <v> [--allow-key-mismatch] \
//       <seed-file> <zip-path> <sig-out-path>
//       Sign the release. The signature covers a version-bound manifest
//       (version + the zip's SHA-256), not the raw bytes alone, so an old signed
//       zip can't be replayed under a faked higher version. Writes the base64
//       signature to <sig-out-path>. Fails if the seed's public half does not
//       match the key baked into the app. Pass --allow-key-mismatch ONLY for a
//       key-rotation transitional release — the build that bakes the NEW public
//       key but must be signed with the OLD private key so existing installs
//       (which still carry the old key) can verify it.
//
// Tag CI signs with the MEOWWATCH_RELEASE_KEY GitHub Actions secret (seed
// file contents on the `release` environment). This CLI takes a key file
// path; the tag job writes the secret to $RUNNER_TEMP and deletes it after.
// Never commit the seed; never put it on R2. See docs/AGENT_GUIDE.md →
// Release signing.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:meowwatch/core/update/release_signature.dart' as rel;

/// A freshly generated release keypair, base64-encoded for storage/pasting.
class ReleaseKeypair {
  const ReleaseKeypair({
    required this.privateSeedBase64,
    required this.publicKeyBase64,
  });

  /// 32-byte RFC 8032 seed — the private key. Keep off the repo and R2.
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

/// Sign the version-bound release manifest (see
/// [rel.releaseSignedMessage]) for [zipBytes] advertised as [version], using the
/// 32-byte seed [privateSeedBase64]. Returns the base64-encoded 64-byte
/// signature (the value that goes into latest.json's `sig`).
String signRelease({
  required String privateSeedBase64,
  required String version,
  required List<int> zipBytes,
}) {
  final sha = sha256.convert(zipBytes).toString();
  final priv = _privateKeyFromSeed(privateSeedBase64);
  final message = Uint8List.fromList(
    utf8.encode(rel.releaseSignedMessage(version: version, sha256Hex: sha)),
  );
  return base64.encode(ed.sign(priv, message));
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
    ..writeln('KEEP THIS FILE OFF the repo and R2. Tag CI uses the seed '
        'contents as the MEOWWATCH_RELEASE_KEY secret. Back it up safely.')
    ..writeln('')
    ..writeln('Paste this into releasePublicKeyBase64 '
        '(lib/core/update/release_signature.dart):')
    ..writeln(kp.publicKeyBase64);
}

Future<void> _sign(List<String> args) async {
  var allowMismatch = false;
  String? version;
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--allow-key-mismatch') {
      allowMismatch = true;
    } else if (arg == '--version') {
      if (i + 1 >= args.length) {
        stderr.writeln('--version needs a value');
        exit(2);
      }
      version = args[++i];
    } else if (arg.startsWith('--')) {
      stderr.writeln('unknown flag: $arg');
      exit(2);
    } else {
      positional.add(arg);
    }
  }
  if (version == null || version.isEmpty) {
    stderr.writeln('sign requires --version <version> (e.g. 0.41.0-alpha)');
    exit(2);
  }
  if (positional.length != 3) {
    stderr.writeln(
      'usage: sign --version <v> [--allow-key-mismatch] '
      '<seed-file> <zip-path> <sig-out-path>',
    );
    exit(2);
  }
  final seedFile = File(positional[0]);
  final zipFile = File(positional[1]);
  final sigOut = File(positional[2]);

  if (!seedFile.existsSync()) {
    stderr.writeln('release key file not found: ${seedFile.path}');
    exit(1);
  }
  if (!zipFile.existsSync()) {
    stderr.writeln('release zip not found: ${zipFile.path}');
    exit(1);
  }

  final seedB64 = seedFile.readAsStringSync().trim();

  // Guard: normally the signing seed MUST correspond to the public key the app
  // ships, so a wrong-key signing can't produce a release every install refuses.
  // The one legitimate exception is a key-rotation transitional release: it
  // bakes the NEW public key but is signed with the OLD private key, because
  // existing installs still verify against the old key. --allow-key-mismatch
  // permits exactly that (and only that).
  final derivedPublic = publicKeyForSeed(seedB64);
  if (derivedPublic != rel.releasePublicKeyBase64.trim()) {
    if (allowMismatch) {
      stderr.writeln(
        'WARNING: signing key does not match the baked-in releasePublicKeyBase64. '
        'Proceeding because --allow-key-mismatch was set (key-rotation '
        'transitional release, signed with the OLD key).',
      );
    } else {
      stderr.writeln(
        'release key mismatch: this seed\'s public key does not match '
        'releasePublicKeyBase64 baked into the app. Refusing to sign — the '
        'resulting release would fail verification on every install. Pass '
        '--allow-key-mismatch ONLY for a key-rotation transitional release '
        '(baking the NEW key while signing with the OLD one).',
      );
      exit(1);
    }
  }

  final zipBytes = await zipFile.readAsBytes();
  final sigB64 = signRelease(
    privateSeedBase64: seedB64,
    version: version,
    zipBytes: zipBytes,
  );

  // Self-check the invariant that always holds: the signature must verify for
  // this version under the signing seed's OWN public key, whether or not that
  // equals the baked-in key (during rotation it deliberately doesn't).
  if (!rel.isReleaseSignatureValid(
    version: version,
    bytes: zipBytes,
    signatureBase64: sigB64,
    publicKeyBase64: derivedPublic,
  )) {
    stderr.writeln('internal error: freshly-made signature failed to verify');
    exit(1);
  }

  sigOut.writeAsStringSync(sigB64);
  stdout.writeln(
    'Signed ${zipFile.path} as v$version → ${sigOut.path} '
    '(${sigB64.length} b64 chars)',
  );
}

Never _usageAndExit() {
  stderr.writeln(
    'usage:\n'
    '  dart run tool/release_signer.dart genkey <out-seed-file>\n'
    '  dart run tool/release_signer.dart sign --version <v> '
    '[--allow-key-mismatch] <seed-file> <zip-path> <sig-out-path>',
  );
  exit(2);
}
