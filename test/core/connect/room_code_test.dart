import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_code.dart';

void main() {
  test('produces an adjective-animal-number code', () {
    final code = generateRoomCode(Random(7));
    expect(code, matches(RegExp(r'^[a-z]+-[a-z]+-\d{2}$')));
  });

  test('is deterministic for a fixed seed', () {
    expect(generateRoomCode(Random(42)), generateRoomCode(Random(42)));
  });

  test('number is always two digits (10..99)', () {
    for (var seed = 0; seed < 50; seed++) {
      final number = int.parse(generateRoomCode(Random(seed)).split('-').last);
      expect(number, inInclusiveRange(10, 99));
    }
  });
}
