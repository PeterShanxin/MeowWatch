import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:meowwatch/core/nearby/lan_interfaces.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';
import 'package:path/path.dart' as path;

/// Release-only native plugin probe. Each stage runs in a separate process.
/// It never starts a listener, advertises a service, or uses the normal profile.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['MEOWWATCH_NEARBY_SMOKE_DIR'];
  final stage = Platform.environment['MEOWWATCH_NEARBY_SMOKE_STAGE'];
  if (root == null || !{'write', 'read', 'revoked'}.contains(stage)) exit(64);
  final directory = Directory(root).absolute;
  if (!path.split(directory.path).contains('nearby-native-smoke')) exit(64);
  await directory.create(recursive: true);
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('MeowWatch · Checking native Nearby support')),
      ),
    ),
  );
  final result = <String, Object?>{
    'stage': stage,
    'platform': Platform.operatingSystem,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'checks': <String>[],
    'passed': false,
  };
  final checks = result['checks']! as List<String>;
  try {
    final canonical = await directory.resolveSymbolicLinks();
    final namespace = sha256
        .convert(utf8.encode(canonical.toLowerCase()))
        .toString();
    final store = ProtectedNearbyStore(namespaceHash: namespace);
    final identity = await store.loadOrCreateDesktopIdentity(
      createTlsIdentity: () => TlsIdentity.generate(),
    );
    final metadataFile = File(path.join(directory.path, 'metadata.json'));
    if (stage == 'write') {
      if (await metadataFile.exists()) throw StateError('profile_not_fresh');
      final random = SystemSecureRandom();
      final credential = DeviceCredential(
        tokenId: encodeBytes(random.bytes(16)),
        clientId: encodeBytes(random.bytes(16)),
        clientName: 'Native storage probe',
        secret: random.bytes(32),
        lastUsedAt: DateTime.now().toUtc(),
      );
      await store.write(credential);
      if ((await store.read(credential.tokenId))?.clientId !=
          credential.clientId) {
        throw StateError('credential_round_trip_failed');
      }
      await metadataFile.writeAsString(
        jsonEncode({
          'desktopId': identity.desktopId,
          'fingerprint': encodeBytes(identity.tlsIdentity.certificateSha256),
          'tokenId': credential.tokenId,
          'clientId': credential.clientId,
        }),
      );
      checks.add('native_protected_write_read');
    } else {
      final saved =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      if (saved['desktopId'] != identity.desktopId ||
          saved['fingerprint'] !=
              encodeBytes(identity.tlsIdentity.certificateSha256)) {
        throw StateError('identity_not_durable');
      }
      checks.add('native_identity_survived_process_restart');
      final tokenId = saved['tokenId'] as String;
      if (stage == 'read') {
        if ((await store.read(tokenId))?.clientId != saved['clientId']) {
          throw StateError('credential_not_durable');
        }
        checks.add('native_credential_survived_process_restart');
        await store.revoke(tokenId);
        if (await store.read(tokenId) != null) {
          throw StateError('revoke_failed');
        }
        checks.add('native_revoke');
      } else {
        if (await store.read(tokenId) != null) {
          throw StateError('revocation_not_durable');
        }
        checks.add('native_revocation_survived_process_restart');
      }
    }
    final interfaces = await LanInterfaces().list();
    result['interfaces'] = interfaces
        .map(
          (entry) => {
            'profile': entry.profile.name,
            'prefixLength': entry.prefixLength,
            'eligible':
                entry.automaticEligibility == LanAutomaticEligibility.eligible,
          },
        )
        .toList();
    checks.add('native_windows_interface_profile_read');
    result['passed'] = true;
  } catch (error) {
    result['errorType'] = error.runtimeType.toString();
    result['errorCode'] = switch (error) {
      NearbyStorageException(:final code) => code,
      NearbyException(:final code) => code,
      StateError(:final message) => message,
      _ => 'native_probe_failed',
    };
  }
  result['completedAtUtc'] = DateTime.now().toUtc().toIso8601String();
  await File(
    path.join(directory.path, '$stage.json'),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  exit(result['passed'] == true ? 0 : 1);
}
