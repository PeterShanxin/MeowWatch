import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/nearby/desktop_nearby_service.dart';
import 'package:meowwatch/core/nearby/lan_interfaces.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/nearby/nearby_companion_dialog.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';

void main() {
  late TlsIdentity identity;

  setUpAll(() async {
    identity = await TlsIdentity.generate();
  });

  testWidgets('shows the actual Public profile reason and disables enable', (
    tester,
  ) async {
    final public = LanInterfaceAddress(
      address: '192.168.20.4',
      prefixLength: 24,
      interfaceIndex: 8,
      interfaceId: 'ethernet-id',
      friendlyName: 'Ethernet',
      profile: LanNetworkProfile.public,
    );
    final service = DesktopNearbyService(
      desktopName: 'MeowWatch test desktop',
      handlerFactory:
          ({required desktopId, required desktopName, required sessionEpoch}) =>
              DesktopNearbyHandlerBinding(
                handler: _Handler(),
                close: () async {},
              ),
      supportDirectoryResolver: () async => Directory.current,
      canonicalPathResolver: (_) async => r'c:\nearby-ui-test',
      interfacesProvider: () async => [public],
      persistenceFactory: (_) => _Persistence(identity),
    );
    await service.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: themeDataFor(MeowThemeId.cozy),
        home: Scaffold(body: NearbyCompanionDialog(service: service)),
      ),
    );
    await tester.pump();

    expect(find.text('Choose a Windows Private network'), findsOneWidget);
    expect(
      find.textContaining('Windows marks this connection as Public'),
      findsOneWidget,
    );
    expect(find.text('192.168.20.4/24 · Public'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enable'),
    );
    expect(button.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await service.close().timeout(const Duration(seconds: 2));
  });
}

String _id(int byte) => encodeBytes(List.filled(16, byte));

final class _Persistence
    implements DesktopNearbyPersistence, NearbySecretStore {
  _Persistence(this.identity);
  final TlsIdentity identity;
  @override
  NearbySecretStore get secretStore => this;
  @override
  Future<PersistedDesktopIdentity> loadOrCreateIdentity() async =>
      PersistedDesktopIdentity(desktopId: _id(1), tlsIdentity: identity);
  @override
  Future<List<PairedDeviceMetadata>> listPairedDevices() async => const [];
  @override
  Future<DeviceCredential?> read(String tokenId) async => null;
  @override
  Future<void> revoke(String tokenId) async {}
  @override
  Future<void> write(DeviceCredential credential) async {}
}

final class _Handler implements NearbyCommandHandler {
  @override
  Stream<NearbyServerEvent> get events => const Stream.empty();
  @override
  Future<Map<String, Object?>> handle(NearbyCommand command) async => const {};
  @override
  Map<String, Object?> get snapshot => const {};
  @override
  int get stateRevision => 0;
}
