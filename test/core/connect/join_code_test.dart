import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/join_code.dart';

void main() {
  group('generatePassphrase', () {
    test('produces a short, unambiguous lowercase token', () {
      final pass = generatePassphrase(Random(7));
      expect(pass, matches(RegExp(r'^[a-z0-9]{4}$')));
      // No visually ambiguous characters (0/o, 1/l/i) so it stays easy to read
      // and retype out loud.
      expect(pass, isNot(contains('0')));
      expect(pass, isNot(contains('1')));
      expect(pass, isNot(contains('l')));
      expect(pass, isNot(contains('o')));
      expect(pass, isNot(contains('i')));
    });

    test('is deterministic for a fixed seed', () {
      expect(generatePassphrase(Random(42)), generatePassphrase(Random(42)));
    });
  });

  group('buildJoinCode', () {
    test('folds the password into the room when present', () {
      expect(buildJoinCode('happy-cat-11', 'k3pn'), 'happy-cat-11-k3pn');
    });

    test('returns the bare room when there is no password', () {
      // The backward-compat guarantee: with no secret a code is just the room,
      // so old room-only codes are produced (and join) unchanged.
      expect(buildJoinCode('happy-cat-11', null), 'happy-cat-11');
      expect(buildJoinCode('happy-cat-11', ''), 'happy-cat-11');
    });
  });
}
