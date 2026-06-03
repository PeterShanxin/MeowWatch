import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/icon_sizes.dart';

void main() {
  test('icon sizes ascend', () {
    expect([IconSizes.sm, IconSizes.md, IconSizes.lg, IconSizes.xl], [16, 20, 24, 32]);
  });

  test('emoji glyph sizes are distinct from icon sizes', () {
    expect(Glyphs.react, 20);
    expect(Glyphs.burst, 34);
  });
}
