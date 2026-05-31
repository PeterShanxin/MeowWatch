import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/update_service.dart';

void main() {
  final bytes = utf8.encode('meowwatch release payload');
  final digest = sha256.convert(bytes).toString();

  test('verifyChecksum passes when the digest matches', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(() => svc.verifyChecksum(bytes, digest), returnsNormally);
  });

  test('verifyChecksum is case-insensitive about the published hex', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(
      () => svc.verifyChecksum(bytes, digest.toUpperCase()),
      returnsNormally,
    );
  });

  test('verifyChecksum throws on a mismatch', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(
      () => svc.verifyChecksum(bytes, 'deadbeef'),
      throwsA(isA<UpdateVerificationException>()),
    );
  });

  test('verifyChecksum is a no-op when no hash was published (null)', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(() => svc.verifyChecksum(bytes, null), returnsNormally);
  });

  test('verifyChecksum is a no-op when the published hash is empty', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(() => svc.verifyChecksum(bytes, ''), returnsNormally);
  });

  test('verifyChecksum trims surrounding whitespace on the published hash', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(() => svc.verifyChecksum(bytes, '  $digest\n'), returnsNormally);
  });

  test('verifyChecksum treats a whitespace-only hash as no hash', () {
    final svc = UpdateService(baseUrl: 'https://example.test');
    expect(() => svc.verifyChecksum(bytes, '   '), returnsNormally);
  });
}
