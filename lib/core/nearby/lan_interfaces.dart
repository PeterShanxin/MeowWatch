import 'package:flutter/services.dart';

enum LanNetworkProfile { private, public, domainAuthenticated, unknown }

enum LanAutomaticEligibility {
  eligible,
  unsupportedAddress,
  publicProfile,
  domainAuthenticatedProfile,
  unknownProfile,
}

class LanInterfaceAddress {
  factory LanInterfaceAddress({
    required String address,
    required int prefixLength,
    required int interfaceIndex,
    required String interfaceId,
    required String friendlyName,
    required LanNetworkProfile profile,
  }) {
    if (_parseIpv4(address) == null) {
      throw ArgumentError.value(address, 'address', 'must be numeric IPv4');
    }
    if (prefixLength < 1 || prefixLength > 32) {
      throw RangeError.range(prefixLength, 1, 32, 'prefixLength');
    }
    if (interfaceIndex <= 0) {
      throw RangeError.range(interfaceIndex, 1, null, 'interfaceIndex');
    }
    if (interfaceId.isEmpty) {
      throw ArgumentError.value(
        interfaceId,
        'interfaceId',
        'must not be empty',
      );
    }
    if (friendlyName.isEmpty) {
      throw ArgumentError.value(
        friendlyName,
        'friendlyName',
        'must not be empty',
      );
    }

    return LanInterfaceAddress._(
      address: address,
      prefixLength: prefixLength,
      interfaceIndex: interfaceIndex,
      interfaceId: interfaceId,
      friendlyName: friendlyName,
      profile: profile,
    );
  }

  const LanInterfaceAddress._({
    required this.address,
    required this.prefixLength,
    required this.interfaceIndex,
    required this.interfaceId,
    required this.friendlyName,
    required this.profile,
  });

  factory LanInterfaceAddress.fromPlatformMap(Map<Object?, Object?> value) {
    final address = _requiredField<String>(value, 'address');
    final prefixLength = _requiredField<int>(value, 'prefixLength');
    final interfaceIndex = _requiredField<int>(value, 'interfaceIndex');
    final interfaceId = _requiredField<String>(value, 'interfaceId');
    final friendlyName = _requiredField<String>(value, 'friendlyName');
    final profileName = _requiredField<String>(value, 'profile');

    if (_parseIpv4(address) == null) {
      throw const FormatException('LAN interface address is not numeric IPv4');
    }
    if (prefixLength < 1 || prefixLength > 32) {
      throw const FormatException('LAN interface prefixLength is out of range');
    }
    if (interfaceIndex <= 0 || interfaceId.isEmpty || friendlyName.isEmpty) {
      throw const FormatException('LAN interface identity is invalid');
    }

    return LanInterfaceAddress._(
      address: address,
      prefixLength: prefixLength,
      interfaceIndex: interfaceIndex,
      interfaceId: interfaceId,
      friendlyName: friendlyName,
      profile: switch (profileName) {
        'private' => LanNetworkProfile.private,
        'public' => LanNetworkProfile.public,
        'domainAuthenticated' => LanNetworkProfile.domainAuthenticated,
        _ => LanNetworkProfile.unknown,
      },
    );
  }

  final String address;
  final int prefixLength;
  final int interfaceIndex;
  final String interfaceId;
  final String friendlyName;
  final LanNetworkProfile profile;

  LanAutomaticEligibility get automaticEligibility {
    if (!isSupportedLanIpv4(address)) {
      return LanAutomaticEligibility.unsupportedAddress;
    }

    return switch (profile) {
      LanNetworkProfile.private => LanAutomaticEligibility.eligible,
      LanNetworkProfile.public => LanAutomaticEligibility.publicProfile,
      LanNetworkProfile.domainAuthenticated =>
        LanAutomaticEligibility.domainAuthenticatedProfile,
      LanNetworkProfile.unknown => LanAutomaticEligibility.unknownProfile,
    };
  }

  String? get automaticRejectionReason {
    return switch (automaticEligibility) {
      LanAutomaticEligibility.eligible => null,
      LanAutomaticEligibility.unsupportedAddress =>
        'This adapter does not have a supported private or link-local IPv4 address.',
      LanAutomaticEligibility.publicProfile =>
        'Windows marks this connection as Public. Only if you trust this network, change it to Private before enabling Nearby.',
      LanAutomaticEligibility.domainAuthenticatedProfile =>
        'Windows marks this connection as domain-authenticated. Nearby automatic enablement requires a Private network.',
      LanAutomaticEligibility.unknownProfile =>
        'This connection could not be confirmed as a Windows Private network, so Nearby was not enabled automatically.',
    };
  }

  bool containsPeer(String peerAddress) {
    final own = _parseIpv4(address);
    final peer = _parseIpv4(peerAddress);
    if (own == null || peer == null || !isSupportedLanIpv4(peerAddress)) {
      return false;
    }

    final mask = (0xffffffff << (32 - prefixLength)) & 0xffffffff;
    return (own & mask) == (peer & mask);
  }
}

class LanInterfaces {
  LanInterfaces({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('meowwatch/lan_interfaces');

  final MethodChannel _channel;

  Future<List<LanInterfaceAddress>> list() async {
    final values = await _channel.invokeListMethod<Object?>('listIPv4');
    if (values == null) {
      throw const FormatException('LAN interface platform response was null');
    }

    final result = <LanInterfaceAddress>[];
    for (final value in values) {
      if (value is! Map<Object?, Object?>) {
        throw const FormatException('LAN interface entry was not a map');
      }
      final candidate = LanInterfaceAddress.fromPlatformMap(value);
      if (isSupportedLanIpv4(candidate.address)) {
        result.add(candidate);
      }
    }
    return List<LanInterfaceAddress>.unmodifiable(result);
  }
}

bool isSupportedLanIpv4(String address) {
  final value = _parseIpv4(address);
  if (value == null) {
    return false;
  }

  final first = value >> 24;
  final second = (value >> 16) & 0xff;
  return first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168) ||
      (first == 169 && second == 254);
}

T _requiredField<T>(Map<Object?, Object?> value, String name) {
  final field = value[name];
  if (field is! T) {
    throw FormatException('LAN interface $name has the wrong type');
  }
  return field;
}

int? _parseIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return null;
  }

  var value = 0;
  for (final part in parts) {
    if (part.isEmpty || (part.length > 1 && part.startsWith('0'))) {
      return null;
    }
    final byte = int.tryParse(part);
    if (byte == null || byte < 0 || byte > 255) {
      return null;
    }
    value = (value << 8) | byte;
  }
  return value;
}
