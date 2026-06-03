import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/theme/tokens/type_scale.dart';

void main() {
  test('type sizes ascend caption..display', () {
    const sizes = [
      TypeScale.caption, TypeScale.body, TypeScale.label,
      TypeScale.title, TypeScale.heading, TypeScale.display,
    ];
    expect(sizes, [11, 13, 15, 18, 24, 30]);
    for (var i = 1; i < sizes.length; i++) {
      expect(sizes[i], greaterThan(sizes[i - 1]));
    }
  });

  test('weights cover the four used roles', () {
    expect(TypeScale.regular, FontWeight.w400);
    expect(TypeScale.medium, FontWeight.w500);
    expect(TypeScale.semibold, FontWeight.w600);
    expect(TypeScale.bold, FontWeight.w700);
  });
}
