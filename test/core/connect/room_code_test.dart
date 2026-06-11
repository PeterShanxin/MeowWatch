import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_code.dart';

void main() {
  // the-<adj>-<animal>-<verb>-and-the-<adj>-<animal>-<verb>
  final magicSentence =
      RegExp(r'^the-[a-z]+-[a-z]+-[a-z]+-and-the-[a-z]+-[a-z]+-[a-z]+$');

  test('produces a two-clause magic sentence', () {
    final code = generateRoomCode(Random(7));
    expect(code, matches(magicSentence));
  });

  test('is deterministic for a fixed seed', () {
    expect(generateRoomCode(Random(42)), generateRoomCode(Random(42)));
  });

  test('only ever draws from the published word lists', () {
    for (var seed = 0; seed < 200; seed++) {
      final parts = generateRoomCode(Random(seed)).split('-');
      // the <adj> <animal> <verb> and the <adj> <animal> <verb>
      expect(parts.length, 9);
      expect(parts[0], 'the');
      expect(parts[4], 'and');
      expect(parts[5], 'the');
      expect(roomAdjectives, contains(parts[1]));
      expect(roomAnimals, contains(parts[2]));
      expect(roomVerbs, contains(parts[3]));
      expect(roomAdjectives, contains(parts[6]));
      expect(roomAnimals, contains(parts[7]));
      expect(roomVerbs, contains(parts[8]));
    }
  });

  test('code space stays past the ~2e10 floor we promised on #109', () {
    // The magic sentence must not regress the privacy win it replaces: the old
    // `…-k3pn` scheme had ~2e10 combinations, and this must stay at least that
    // large so the entropy lives entirely in friendly words.
    expect(roomCodeCombinations, greaterThanOrEqualTo(20000000000));
  });

  group('word lists are clean', () {
    for (final entry in <String, List<String>>{
      'adjectives': roomAdjectives,
      'animals': roomAnimals,
      'verbs': roomVerbs,
    }.entries) {
      test('${entry.key} are unique, lowercase, and dictatable', () {
        expect(entry.value.toSet().length, entry.value.length,
            reason: 'no duplicate ${entry.key}');
        for (final word in entry.value) {
          // Letters only: no digits, no ambiguous glyphs, easy to say aloud.
          expect(word, matches(RegExp(r'^[a-z]+$')), reason: word);
        }
      });
    }
  });
}
