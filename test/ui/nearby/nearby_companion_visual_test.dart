import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/nearby/desktop_nearby_service.dart';
import 'package:meowwatch/core/nearby/lan_interfaces.dart';
import 'package:meowwatch/core/theme/meow_context.dart';
import 'package:meowwatch/core/theme/meow_theme.dart';
import 'package:meowwatch/ui/nearby/nearby_companion_dialog.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// These are Flutter widget-renderer captures, not native window or LAN proof.
/// All identity, network, advertisement and persistence adapters are test-owned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TlsIdentity identity;
  var fontDescription = 'Flutter test default font';

  setUpAll(() async {
    identity = await TlsIdentity.generate();
    if (Platform.isWindows) {
      final fontRoot =
          '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts';
      final loader = FontLoader('Segoe UI');
      for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
        final bytes = await File('$fontRoot/$name').readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
      fontDescription = 'Windows Segoe UI (regular and bold)';
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final layout in [
    (name: 'desktop-1280x800', size: const Size(1280, 800), scale: 1.0),
    (name: 'compact-800x600-2x', size: const Size(800, 600), scale: 2.0),
  ]) {
    testWidgets(
      '${layout.name} Nearby states render and controls remain reachable',
      (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final errors = <String>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString());
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        final harness = _Harness(identity);
        final service = harness.service;
        final boundaryKey = GlobalKey();
        final captures = <String>[];
        var flowCompleted = false;
        final output = Directory('build/nearby-ui-captures/${layout.name}');
        await service.initialize();

        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await output.create(recursive: true);
              await File('${output.path}/$name.png').writeAsBytes(
                bytes!.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          });
          captures.add('$name.png');
        }

        Future<void> reach(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget);
        }

        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: themeDataFor(MeowThemeId.cozy),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: FilledButton(
                        onPressed: () =>
                            showNearbyCompanionDialog(context, service),
                        child: const Text('Nearby companion'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(
            find.widgetWithText(FilledButton, 'Nearby companion'),
          );
          await tester.pumpAndSettle();
          final enable = find.widgetWithText(FilledButton, 'Enable');
          expect(tester.widget<FilledButton>(enable).onPressed, isNull);
          expect(
            find.textContaining('Windows marks this connection as Public'),
            findsOneWidget,
          );
          await capture('01-public-disabled');
          await reach(
            find.textContaining('Windows marks this connection as Public'),
          );
          await capture('02-public-reason-visible');

          harness.interfaces = [_interface(LanNetworkProfile.private)];
          await service.refreshInterfaces();
          await tester.pumpAndSettle();
          await reach(enable);
          expect(tester.widget<FilledButton>(enable).onPressed, isNotNull);
          await capture('03-private-ready');
          await tester.tap(enable);
          await tester.pumpAndSettle();
          expect(service.phase, DesktopNearbyPhase.enabled);
          await reach(find.text('Pair a phone'));
          await capture('04-private-enabled');
          await tester.tap(find.text('Pair a phone'));
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsOneWidget);
          await Scrollable.ensureVisible(
            tester.element(find.byType(QrImageView)),
            alignment: 0.4,
          );
          await tester.pumpAndSettle();
          final qrBounds = tester.getRect(find.byType(QrImageView)).inflate(8);
          final viewport = tester.getRect(find.byType(SingleChildScrollView));
          expect(viewport.contains(qrBounds.topLeft), isTrue);
          expect(viewport.contains(qrBounds.bottomRight), isTrue);
          await capture('05-invitation-qr');
          await reach(find.widgetWithText(TextButton, 'Cancel'));
          await capture('06-invitation-actions');
          expect(
            find
                .widgetWithText(OutlinedButton, 'Copy full invite')
                .hitTestable(),
            findsOneWidget,
          );

          final decision = harness.requestApproval('Living room Android phone');
          await tester.pumpAndSettle();
          await reach(find.widgetWithText(FilledButton, 'Allow'));
          await capture('07-approval');
          expect(
            find.widgetWithText(TextButton, 'Deny').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Allow'));
          await tester.pumpAndSettle();
          expect(await decision, isTrue);
          final accepted = await harness.authority.approvePairing(
            harness.approval.id,
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          expect(
            service.pairedDevices.map((device) => device.tokenId),
            contains(accepted.credential.tokenId),
          );
          final phoneTile = find.ancestor(
            of: find.text('Living room Android phone'),
            matching: find.byType(ListTile),
          );
          final revoke = find.descendant(
            of: phoneTile,
            matching: find.widgetWithText(TextButton, 'Revoke'),
          );
          await reach(revoke);
          await capture('08-paired-phone');
          await tester.tap(revoke);
          await tester.pumpAndSettle();
          await capture('09-revoke-confirmation');
          final confirmRevoke = find.widgetWithText(FilledButton, 'Revoke');
          expect(confirmRevoke.hitTestable(), findsOneWidget);
          await tester.tap(confirmRevoke);
          await tester.pumpAndSettle();
          expect(
            service.pairedDevices.map((device) => device.tokenId),
            isNot(contains(accepted.credential.tokenId)),
          );
          expect(
            harness.persistence.revoked,
            contains(accepted.credential.tokenId),
          );
          await capture('10-revoked');
          FlutterError.onError = previousErrorHandler;
          expect(
            errors,
            isEmpty,
            reason: 'No layout, paint or framework failures',
          );
          flowCompleted = true;
        } finally {
          FlutterError.onError = previousErrorHandler;
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await service.close();
          await tester.runAsync(() async {
            await output.create(recursive: true);
            await File('${output.path}/evidence.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'renderer':
                    'Flutter widget renderer; not native window or LAN evidence',
                'service':
                    'Production DesktopNearbyService with test network, server, advertisement and in-memory persistence adapters',
                'theme': 'Production MeowThemeId.cozy',
                'font': fontDescription,
                'width': layout.size.width,
                'height': layout.size.height,
                'textScale': layout.scale,
                'captures': captures,
                'flowCompleted': flowCompleted,
                'frameworkErrors': errors,
              }),
            );
          });
        }
      },
      // These measurements use the Windows production font, not Ahem metrics.
      skip: !Platform.isWindows,
    );
  }
}

String _id(int value) => encodeBytes(List<int>.filled(16, value));

LanInterfaceAddress _interface(LanNetworkProfile profile) =>
    LanInterfaceAddress(
      address: '192.168.20.4',
      prefixLength: 24,
      interfaceIndex: 8,
      interfaceId: 'test-ethernet',
      friendlyName: 'Ethernet',
      profile: profile,
    );

final class _Harness {
  _Harness(TlsIdentity identity) : persistence = _Persistence(identity) {
    service = DesktopNearbyService(
      desktopName: 'MeowWatch visual test desktop',
      handlerFactory:
          ({required desktopId, required desktopName, required sessionEpoch}) =>
              DesktopNearbyHandlerBinding(
                handler: _Handler(),
                close: () async {},
              ),
      supportDirectoryResolver: () async => Directory.current,
      canonicalPathResolver: (_) async => r'c:\nearby-widget-visual-test',
      interfacesProvider: () async => interfaces,
      persistenceFactory: (_) => persistence,
      serverBinder:
          ({
            required subnet,
            required identity,
            required authority,
            required handler,
            required approvePairing,
          }) async {
            this.authority = authority;
            approve = approvePairing;
            return _Server();
          },
      advertisementFactory:
          ({
            required desktopId,
            required displayName,
            required port,
            required pairingOpen,
          }) => _Advertisement(),
    );
  }
  final _Persistence persistence;
  late final DesktopNearbyService service;
  List<LanInterfaceAddress> interfaces = [_interface(LanNetworkProfile.public)];
  late NearbyAuthority authority;
  late Future<bool> Function(PendingApproval) approve;
  late PendingApproval approval;

  Future<bool> requestApproval(String name) {
    final invitation = service.invitation!;
    final connection = authority.openConnection(peerAddress: '192.168.20.5');
    final nonce = List<int>.filled(32, 3);
    final challenge = authority.beginPairing(
      connectionId: connection,
      clientId: _id(8),
      clientName: name,
      clientNonce: nonce,
      pairId: invitation.pairId,
    );
    final transcript = PairingTranscript(
      desktopId: invitation.desktopId,
      pairId: invitation.pairId,
      clientId: _id(8),
      clientName: name,
      clientNonce: nonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: invitation.certificateSha256,
    );
    approval = authority.verifyPairingProof(
      connection,
      transcript.clientProof(invitation.pairSecret),
    );
    return approve(approval);
  }
}

final class _Persistence
    implements DesktopNearbyPersistence, NearbySecretStore {
  _Persistence(this.identity);
  final TlsIdentity identity;
  final revoked = <String>[];
  final devices = <PairedDeviceMetadata>[
    PairedDeviceMetadata(
      tokenId: _id(4),
      clientId: _id(5),
      clientName: 'Bedroom phone',
      lastUsedAt: DateTime.utc(2026, 9, 16),
    ),
  ];
  @override
  NearbySecretStore get secretStore => this;
  @override
  Future<PersistedDesktopIdentity> loadOrCreateIdentity() async =>
      PersistedDesktopIdentity(desktopId: _id(1), tlsIdentity: identity);
  @override
  Future<List<PairedDeviceMetadata>> listPairedDevices() async =>
      List.of(devices);
  @override
  Future<DeviceCredential?> read(String tokenId) async => null;
  @override
  Future<void> revoke(String tokenId) async {
    revoked.add(tokenId);
    devices.removeWhere((device) => device.tokenId == tokenId);
  }

  @override
  Future<void> write(DeviceCredential credential) async {
    devices.add(
      PairedDeviceMetadata(
        tokenId: credential.tokenId,
        clientId: credential.clientId,
        clientName: credential.clientName,
        lastUsedAt: credential.lastUsedAt,
      ),
    );
  }
}

final class _Server implements DesktopNearbyServerHandle {
  @override
  int get port => 45231;
  @override
  Future<void> close() async {}
}

final class _Advertisement implements DesktopNearbyAdvertisement {
  @override
  Future<void> start() async {}
  @override
  Future<void> dispose() async {}
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
