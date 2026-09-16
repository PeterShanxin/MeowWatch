import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/nearby/lan_interfaces.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LanInterfaceAddress', () {
    test('parses the Windows adapter contract', () {
      final candidate = LanInterfaceAddress.fromPlatformMap(<String, Object?>{
        'address': '192.168.50.12',
        'prefixLength': 24,
        'interfaceIndex': 7,
        'interfaceId': '{A4ED6A76-2380-4A4E-B29F-D45230C79B5E}',
        'friendlyName': 'Wi-Fi',
        'profile': 'private',
      });

      expect(candidate.address, '192.168.50.12');
      expect(candidate.prefixLength, 24);
      expect(candidate.interfaceIndex, 7);
      expect(candidate.interfaceId, '{A4ED6A76-2380-4A4E-B29F-D45230C79B5E}');
      expect(candidate.friendlyName, 'Wi-Fi');
      expect(candidate.profile, LanNetworkProfile.private);
      expect(candidate.automaticEligibility, LanAutomaticEligibility.eligible);
      expect(candidate.automaticRejectionReason, isNull);
    });

    test('requires every platform field to have the expected type', () {
      expect(
        () => LanInterfaceAddress.fromPlatformMap(<String, Object?>{
          'address': '192.168.1.2',
          'prefixLength': '24',
          'interfaceIndex': 7,
          'interfaceId': 'adapter',
          'friendlyName': 'Ethernet',
          'profile': 'private',
        }),
        throwsFormatException,
      );
    });

    test('rejects invalid prefixes from the platform boundary', () {
      expect(
        () => LanInterfaceAddress.fromPlatformMap(<String, Object?>{
          'address': '10.0.0.4',
          'prefixLength': 0,
          'interfaceIndex': 7,
          'interfaceId': 'adapter',
          'friendlyName': 'Ethernet',
          'profile': 'private',
        }),
        throwsFormatException,
      );
      expect(
        () => LanInterfaceAddress.fromPlatformMap(<String, Object?>{
          'address': '10.0.0.4',
          'prefixLength': 33,
          'interfaceIndex': 7,
          'interfaceId': 'adapter',
          'friendlyName': 'Ethernet',
          'profile': 'private',
        }),
        throwsFormatException,
      );
    });

    test('checks on-link prefix boundaries', () {
      final candidate = _candidate(address: '192.168.40.9', prefixLength: 24);

      expect(candidate.containsPeer('192.168.40.0'), isTrue);
      expect(candidate.containsPeer('192.168.40.255'), isTrue);
      expect(candidate.containsPeer('192.168.41.1'), isFalse);
      expect(candidate.containsPeer('8.8.8.8'), isFalse);
      expect(candidate.containsPeer('::ffff:192.168.40.4'), isFalse);
      expect(candidate.containsPeer('desktop.local'), isFalse);
    });

    test('a 32-bit prefix matches only the selected address', () {
      final candidate = _candidate(address: '10.20.30.40', prefixLength: 32);

      expect(candidate.containsPeer('10.20.30.40'), isTrue);
      expect(candidate.containsPeer('10.20.30.41'), isFalse);
    });
  });

  group('LAN address classification', () {
    test('accepts RFC1918 and IPv4 link-local addresses', () {
      expect(isSupportedLanIpv4('10.0.0.1'), isTrue);
      expect(isSupportedLanIpv4('172.16.0.1'), isTrue);
      expect(isSupportedLanIpv4('172.31.255.254'), isTrue);
      expect(isSupportedLanIpv4('192.168.255.254'), isTrue);
      expect(isSupportedLanIpv4('169.254.10.20'), isTrue);
    });

    test('rejects public, loopback, multicast, and non-numeric addresses', () {
      expect(isSupportedLanIpv4('172.15.255.255'), isFalse);
      expect(isSupportedLanIpv4('172.32.0.0'), isFalse);
      expect(isSupportedLanIpv4('8.8.8.8'), isFalse);
      expect(isSupportedLanIpv4('127.0.0.1'), isFalse);
      expect(isSupportedLanIpv4('224.0.0.251'), isFalse);
      expect(isSupportedLanIpv4('0.0.0.0'), isFalse);
      expect(isSupportedLanIpv4('::1'), isFalse);
      expect(isSupportedLanIpv4('desktop.local'), isFalse);
    });
  });

  group('automatic selection', () {
    test('accepts only an explicitly private Windows profile', () {
      expect(
        _candidate(profile: LanNetworkProfile.private).automaticEligibility,
        LanAutomaticEligibility.eligible,
      );
      expect(
        _candidate(profile: LanNetworkProfile.public).automaticEligibility,
        LanAutomaticEligibility.publicProfile,
      );
      expect(
        _candidate(
          profile: LanNetworkProfile.domainAuthenticated,
        ).automaticEligibility,
        LanAutomaticEligibility.domainAuthenticatedProfile,
      );
      expect(
        _candidate(profile: LanNetworkProfile.unknown).automaticEligibility,
        LanAutomaticEligibility.unknownProfile,
      );
    });

    test('explains why an unknown profile cannot auto-enable Nearby', () {
      final candidate = _candidate(profile: LanNetworkProfile.unknown);

      expect(
        candidate.automaticRejectionReason,
        contains('could not be confirmed'),
      );
      expect(candidate.automaticRejectionReason, contains('Private'));
    });

    test('does not recommend trusting a public network blindly', () {
      final candidate = _candidate(profile: LanNetworkProfile.public);

      expect(candidate.automaticRejectionReason, contains('if you trust'));
      expect(candidate.automaticRejectionReason, contains('Public'));
    });
  });

  group('LanInterfaces', () {
    const channel = MethodChannel('meowwatch/lan_interfaces');
    late LanInterfaces interfaces;

    setUp(() {
      interfaces = LanInterfaces(channel: channel);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('filters non-LAN addresses returned by the native boundary', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'listIPv4');
            return <Object?>[
              _platformCandidate(address: '192.168.1.4'),
              _platformCandidate(address: '8.8.8.8'),
              _platformCandidate(address: '127.0.0.1'),
            ];
          });

      final candidates = await interfaces.list();

      expect(candidates, hasLength(1));
      expect(candidates.single.address, '192.168.1.4');
    });

    test('fails closed on a malformed native response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return <Object?>[
              _platformCandidate(address: '192.168.1.4'),
              <String, Object?>{'address': '192.168.1.5'},
            ];
          });

      await expectLater(interfaces.list(), throwsFormatException);
    });
  });
}

LanInterfaceAddress _candidate({
  String address = '192.168.1.4',
  int prefixLength = 24,
  LanNetworkProfile profile = LanNetworkProfile.private,
}) {
  return LanInterfaceAddress(
    address: address,
    prefixLength: prefixLength,
    interfaceIndex: 7,
    interfaceId: '{A4ED6A76-2380-4A4E-B29F-D45230C79B5E}',
    friendlyName: 'Wi-Fi',
    profile: profile,
  );
}

Map<String, Object?> _platformCandidate({required String address}) {
  return <String, Object?>{
    'address': address,
    'prefixLength': 24,
    'interfaceIndex': 7,
    'interfaceId': '{A4ED6A76-2380-4A4E-B29F-D45230C79B5E}',
    'friendlyName': 'Wi-Fi',
    'profile': 'private',
  };
}
