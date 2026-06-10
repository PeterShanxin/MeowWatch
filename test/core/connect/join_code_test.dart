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
      expect(buildJoinCode('happy-cat-11', null), 'happy-cat-11');
      expect(buildJoinCode('happy-cat-11', ''), 'happy-cat-11');
    });
  });

  group('parseJoinCode', () {
    test('splits a generated code into room + password', () {
      final r = parseJoinCode('happy-cat-11-k3pn');
      expect(r.room, 'happy-cat-11');
      expect(r.password, 'k3pn');
    });

    test('treats an old room-only code as room with no password', () {
      // The core backward-compat guarantee: an old "happy-cat-11" code still
      // parses to the same room and no password, so it folds back to itself.
      final r = parseJoinCode('happy-cat-11');
      expect(r.room, 'happy-cat-11');
      expect(r.password, isNull);
    });

    test('captures a multi-word password after the room shape', () {
      final r = parseJoinCode('happy-cat-11-mellow-yak');
      expect(r.room, 'happy-cat-11');
      expect(r.password, 'mellow-yak');
    });

    test('treats a custom room that is not adj-animal-NN as a bare room', () {
      final r = parseJoinCode('movienight');
      expect(r.room, 'movienight');
      expect(r.password, isNull);
    });

    test('trims surrounding whitespace', () {
      final r = parseJoinCode('  happy-cat-11-k3pn  ');
      expect(r.room, 'happy-cat-11');
      expect(r.password, 'k3pn');
    });
  });

  group('round-trip', () {
    test('build(parse(code)) reproduces the original code', () {
      for (final code in <String>[
        'happy-cat-11-k3pn',
        'happy-cat-11',
        'movienight',
        'sleepy-owl-13-mellow-yak',
      ]) {
        final p = parseJoinCode(code);
        expect(buildJoinCode(p.room, p.password), code);
      }
    });

    test('old codes survive a full generate-era round trip unchanged', () {
      // A friend on the old build shares "happy-cat-11"; a friend on the new
      // build parses then re-folds it. Both must land on the identical room.
      const old = 'happy-cat-11';
      final p = parseJoinCode(old);
      expect(buildJoinCode(p.room, p.password), old);
    });
  });
}
