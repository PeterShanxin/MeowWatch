import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/nearby/desktop_nearby_service.dart';
import 'package:meowwatch/core/nearby/lan_interfaces.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';

void main() {
  late TlsIdentity tlsIdentity;

  setUpAll(() async {
    tlsIdentity = await TlsIdentity.generate();
  });

  test(
    'initialize remains disabled and namespaces the canonical data path',
    () async {
      String? firstHash;
      String? secondHash;
      final first = _service(
        tlsIdentity,
        supportPath: r'C:\MeowWatch\Profile',
        persistenceFactory: (hash) {
          firstHash = hash;
          return _Persistence(tlsIdentity);
        },
      );
      final second = _service(
        tlsIdentity,
        supportPath: r'c:\meowwatch\profile',
        persistenceFactory: (hash) {
          secondHash = hash;
          return _Persistence(tlsIdentity);
        },
      );

      await first.initialize();
      await second.initialize();

      expect(first.phase, DesktopNearbyPhase.ready);
      expect(first.isEnabled, isFalse);
      expect(first.desktopId, _id(1));
      expect(firstHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      if (Platform.isWindows) expect(firstHash, secondHash);
      await first.close();
      await second.close();
    },
  );

  test('stop invalidates authority before a pending bind completes', () async {
    final gate = Completer<DesktopNearbyServerHandle>();
    final handle = _ServerHandle();
    NearbyAuthority? capturedAuthority;
    var bindingClosed = 0;
    final service = _service(
      tlsIdentity,
      bindingClosed: () => bindingClosed++,
      serverBinder:
          ({
            required subnet,
            required identity,
            required authority,
            required handler,
            required approvePairing,
          }) {
            capturedAuthority = authority;
            return gate.future;
          },
    );
    await service.initialize();

    final enabling = service.enable(_privateInterface());
    await _until(() => capturedAuthority != null);
    final enablingExpectation = expectLater(
      enabling,
      throwsA(
        isA<NearbyException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    final stopping = service.stop();

    expect(
      () => capturedAuthority!.openConnection(peerAddress: '192.168.50.3'),
      throwsA(
        isA<NearbyException>().having(
          (error) => error.code,
          'code',
          'not_connected',
        ),
      ),
    );
    gate.complete(handle);
    await enablingExpectation;
    await stopping;

    expect(handle.closeCount, 1);
    expect(bindingClosed, 1);
    expect(service.phase, DesktopNearbyPhase.ready);
    await service.close();
  });

  test(
    'profile change fails closed and tears down the active session',
    () async {
      var current = <LanInterfaceAddress>[_privateInterface()];
      final handle = _ServerHandle();
      final advertisement = _Advertisement();
      var bindingClosed = 0;
      final service = _service(
        tlsIdentity,
        interfacesProvider: () async => current,
        bindingClosed: () => bindingClosed++,
        serverBinder: _immediateBinder(handle),
        advertisementFactory: _advertisementFactory(advertisement),
      );
      await service.initialize();
      await service.enable(current.single);
      expect(service.phase, DesktopNearbyPhase.enabled);

      current = [_publicInterface()];
      await service.refreshInterfaces();

      expect(service.phase, DesktopNearbyPhase.failed);
      expect(service.errorCode, 'lan_unavailable');
      expect(service.isEnabled, isFalse);
      expect(handle.closeCount, 1);
      expect(bindingClosed, 1);
      expect(advertisement.disposeCount, 1);
      await service.close();
    },
  );

  test(
    'pairing invite is ephemeral while paired reconnect server remains on',
    () async {
      final advertisements = <_Advertisement>[];
      final handle = _ServerHandle(port: 45231);
      final service = _service(
        tlsIdentity,
        serverBinder: _immediateBinder(handle),
        advertisementFactory:
            ({
              required desktopId,
              required displayName,
              required port,
              required pairingOpen,
            }) {
              final value = _Advertisement(pairingOpen: pairingOpen);
              advertisements.add(value);
              return value;
            },
      );
      await service.initialize();
      await service.enable(_privateInterface());

      final invitation = await service.openPairing();

      expect(PairingInvitation.decodeQr(service.invitationQr!), isNotNull);
      expect(invitation.endpoint.address.toString(), '192.168.50.2');
      expect(invitation.endpoint.port, 45231);
      expect(service.invitationSeconds, 120);
      expect(advertisements.map((item) => item.pairingOpen), [false, true]);

      await service.closePairing();

      expect(service.invitation, isNull);
      expect(service.phase, DesktopNearbyPhase.enabled);
      expect(handle.closeCount, 0);
      expect(advertisements.last.pairingOpen, isFalse);
      await service.close();
      expect(handle.closeCount, 1);
    },
  );

  test('mDNS failure keeps QR pairing available', () async {
    final advertisements = <_Advertisement>[];
    final service = _service(
      tlsIdentity,
      serverBinder: _immediateBinder(_ServerHandle()),
      advertisementFactory:
          ({
            required desktopId,
            required displayName,
            required port,
            required pairingOpen,
          }) {
            final value = _Advertisement(throwOnStart: true);
            advertisements.add(value);
            return value;
          },
    );
    await service.initialize();
    await service.enable(_privateInterface());

    expect(service.phase, DesktopNearbyPhase.enabled);
    expect(service.mdnsAvailable, isFalse);

    await service.openPairing();

    expect(service.invitationQr, isNotNull);
    expect(service.mdnsAvailable, isFalse);
    expect(advertisements, hasLength(2));
    expect(advertisements.every((item) => item.disposeCount == 1), isTrue);
    await service.close();
  });

  test('close clears an open pairing window and owned resources', () async {
    final handle = _ServerHandle();
    final advertisement = _Advertisement();
    var bindingClosed = 0;
    final service = _service(
      tlsIdentity,
      bindingClosed: () => bindingClosed++,
      serverBinder: _immediateBinder(handle),
      advertisementFactory: _advertisementFactory(advertisement),
    );
    await service.initialize();
    await service.enable(_privateInterface());
    await service.openPairing();
    expect(service.invitation, isNotNull);

    await service.close();

    expect(service.phase, DesktopNearbyPhase.closed);
    expect(service.invitation, isNull);
    expect(service.pendingApprovalName, isNull);
    expect(service.invitationSeconds, 0);
    expect(handle.closeCount, 1);
    expect(bindingClosed, 1);
    expect(advertisement.disposeCount, 2);
  });

  test('revocation persists and refreshes public paired metadata', () async {
    final credential = DeviceCredential(
      tokenId: _id(8),
      clientId: _id(9),
      clientName: 'Alice phone',
      secret: List.filled(32, 10),
      lastUsedAt: DateTime.utc(2026, 9, 16),
    );
    final persistence = _Persistence(tlsIdentity)
      ..credentials[credential.tokenId] = credential;
    final service = _service(
      tlsIdentity,
      persistenceFactory: (_) => persistence,
    );
    await service.initialize();
    expect(service.pairedDevices.single.clientName, 'Alice phone');

    await service.revoke(credential.tokenId);

    expect(service.pairedDevices, isEmpty);
    expect(await persistence.read(credential.tokenId), isNull);
    await service.close();
  });
}

DesktopNearbyService _service(
  TlsIdentity identity, {
  String supportPath = r'C:\MeowWatch\TestProfile',
  Future<List<LanInterfaceAddress>> Function()? interfacesProvider,
  DesktopNearbyPersistenceFactory? persistenceFactory,
  DesktopNearbyServerBinder? serverBinder,
  DesktopNearbyAdvertisementFactory? advertisementFactory,
  void Function()? bindingClosed,
}) => DesktopNearbyService(
  desktopName: 'MeowWatch test desktop',
  handlerFactory:
      ({required desktopId, required desktopName, required sessionEpoch}) =>
          DesktopNearbyHandlerBinding(
            handler: _Handler(sessionEpoch),
            close: () async => bindingClosed?.call(),
          ),
  supportDirectoryResolver: () async => Directory(supportPath),
  interfacesProvider: interfacesProvider ?? () async => [_privateInterface()],
  persistenceFactory: persistenceFactory ?? (_) => _Persistence(identity),
  serverBinder: serverBinder ?? _immediateBinder(_ServerHandle()),
  advertisementFactory:
      advertisementFactory ?? _advertisementFactory(_Advertisement()),
  interfacePollInterval: const Duration(days: 1),
);

DesktopNearbyServerBinder _immediateBinder(_ServerHandle handle) =>
    ({
      required subnet,
      required identity,
      required authority,
      required handler,
      required approvePairing,
    }) async => handle;

DesktopNearbyAdvertisementFactory _advertisementFactory(
  _Advertisement advertisement,
) =>
    ({
      required desktopId,
      required displayName,
      required port,
      required pairingOpen,
    }) => advertisement;

LanInterfaceAddress _privateInterface() => LanInterfaceAddress(
  address: '192.168.50.2',
  prefixLength: 24,
  interfaceIndex: 4,
  interfaceId: 'wifi-id',
  friendlyName: 'Wi-Fi',
  profile: LanNetworkProfile.private,
);

LanInterfaceAddress _publicInterface() => LanInterfaceAddress(
  address: '192.168.50.2',
  prefixLength: 24,
  interfaceIndex: 4,
  interfaceId: 'wifi-id',
  friendlyName: 'Wi-Fi',
  profile: LanNetworkProfile.public,
);

String _id(int byte) => encodeBytes(List.filled(16, byte));

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

final class _Persistence
    implements DesktopNearbyPersistence, NearbySecretStore {
  _Persistence(this.identity);
  final TlsIdentity identity;
  final Map<String, DeviceCredential> credentials = {};
  final Set<String> revoked = {};

  @override
  NearbySecretStore get secretStore => this;

  @override
  Future<PersistedDesktopIdentity> loadOrCreateIdentity() async =>
      PersistedDesktopIdentity(desktopId: _id(1), tlsIdentity: identity);

  @override
  Future<List<PairedDeviceMetadata>> listPairedDevices() async => [
    for (final credential in credentials.values)
      if (!revoked.contains(credential.tokenId))
        PairedDeviceMetadata(
          tokenId: credential.tokenId,
          clientId: credential.clientId,
          clientName: credential.clientName,
          lastUsedAt: credential.lastUsedAt,
        ),
  ];

  @override
  Future<DeviceCredential?> read(String tokenId) async =>
      revoked.contains(tokenId) ? null : credentials[tokenId];

  @override
  Future<void> revoke(String tokenId) async {
    revoked.add(tokenId);
    credentials.remove(tokenId);
  }

  @override
  Future<void> write(DeviceCredential credential) async {
    if (!revoked.contains(credential.tokenId)) {
      credentials[credential.tokenId] = credential;
    }
  }
}

final class _Handler implements NearbyCommandHandler {
  _Handler(this.epoch);
  final String epoch;
  @override
  Stream<NearbyServerEvent> get events => const Stream.empty();
  @override
  Map<String, Object?> get snapshot => {
    'session': {'epoch': epoch},
  };
  @override
  int get stateRevision => 0;
  @override
  Future<Map<String, Object?>> handle(NearbyCommand command) async => const {};
}

final class _ServerHandle implements DesktopNearbyServerHandle {
  _ServerHandle({this.port = 45111});
  @override
  final int port;
  int closeCount = 0;
  @override
  Future<void> close() async {
    closeCount++;
  }
}

final class _Advertisement implements DesktopNearbyAdvertisement {
  _Advertisement({this.pairingOpen = false, this.throwOnStart = false});
  final bool pairingOpen;
  final bool throwOnStart;
  int startCount = 0;
  int disposeCount = 0;
  @override
  Future<void> start() async {
    startCount++;
    if (throwOnStart) throw StateError('mDNS unavailable');
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
