import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/audio/notify_sounds.dart';

void main() {
  test('default ids resolve to the starred presets', () {
    expect(resolvePrimary(kDefaultPrimarySoundId).id, 'marimba');
    expect(resolveSecondary(kDefaultSecondarySoundId).id, 'low_thud');
  });

  test('unknown or null id falls back to the default', () {
    expect(resolvePrimary('nope').id, kDefaultPrimarySoundId);
    expect(resolvePrimary(null).id, kDefaultPrimarySoundId);
    expect(resolveSecondary('nope').id, kDefaultSecondarySoundId);
    expect(resolveSecondary(null).id, kDefaultSecondarySoundId);
  });

  test('a known non-default id resolves to itself', () {
    expect(resolvePrimary('glass').id, 'glass');
    expect(resolveSecondary('soft_bell').id, 'soft_bell');
  });

  test('every preset asset is a well-formed sounds URI', () {
    for (final s in [...kPrimarySounds, ...kSecondarySounds]) {
      expect(s.asset, startsWith('asset:///assets/sounds/'));
      expect(s.asset, endsWith('.wav'));
      expect(s.label, isNotEmpty);
    }
  });
}
