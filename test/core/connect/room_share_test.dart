import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_share.dart';

void main() {
  const sentence = 'sleepy-otter-counts-cozy-stars';

  group('encodeShareCode', () {
    test('default server + port stays the bare sentence', () {
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 8999),
        sentence,
      );
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 8999),
        isNot(contains('@')),
      );
    });

    test('custom server, default port appends @host only', () {
      expect(
        encodeShareCode(room: sentence, server: 'cozy.example.net', port: 8999),
        '$sentence@cozy.example.net',
      );
    });

    test('custom server + port appends @host:port', () {
      expect(
        encodeShareCode(room: sentence, server: 'cozy.example.net', port: 9000),
        '$sentence@cozy.example.net:9000',
      );
    });

    test('custom port on the default host still carries the port', () {
      expect(
        encodeShareCode(room: sentence, server: 'syncplay.pl', port: 9000),
        '$sentence@syncplay.pl:9000',
      );
    });
  });

  group('parseShareCode — backward compatibility', () {
    test('a bare magic sentence is room-only', () {
      final r = parseShareCode(sentence);
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, isNull);
      expect(r.port, isNull);
    });

    test('an old room-only code (happy-cat-11) is room-only', () {
      final r = parseShareCode('happy-cat-11');
      expect(r.isValid, isTrue);
      expect(r.room, 'happy-cat-11');
      expect(r.server, isNull);
      expect(r.port, isNull);
    });

    test('a folded private code joins verbatim', () {
      final r = parseShareCode('happy-cat-11-k3pn');
      expect(r.isValid, isTrue);
      expect(r.room, 'happy-cat-11-k3pn');
      expect(r.server, isNull);
    });
  });

  group('parseShareCode — structured codes', () {
    test('room@host yields the room + server, default port', () {
      final r = parseShareCode('$sentence@cozy.example.net');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, 'cozy.example.net');
      expect(r.port, isNull);
    });

    test('room@host:port yields room + server + port', () {
      final r = parseShareCode('$sentence@cozy.example.net:9000');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });

    test('surrounding whitespace is trimmed', () {
      final r = parseShareCode('  $sentence@cozy.example.net:9000  ');
      expect(r.isValid, isTrue);
      expect(r.room, sentence);
      expect(r.server, 'cozy.example.net');
      expect(r.port, 9000);
    });
  });

  group('parseShareCode — round-trips with encodeShareCode', () {
    for (final c in const [
      ['syncplay.pl', 8999],
      ['cozy.example.net', 8999],
      ['cozy.example.net', 9000],
      ['syncplay.pl', 9000],
    ]) {
      final server = c[0] as String;
      final port = c[1] as int;
      test('$server:$port survives encode → parse', () {
        final encoded =
            encodeShareCode(room: sentence, server: server, port: port);
        final parsed = parseShareCode(encoded);
        expect(parsed.isValid, isTrue);
        expect(parsed.room, sentence);
        // A null server/port from the parser means "use the default" — which is
        // exactly what was encoded, so reconstruct before comparing.
        expect(parsed.server ?? 'syncplay.pl', server);
        expect(parsed.port ?? 8999, port);
      });
    }
  });

  group('parseShareCode — malformed gets clear feedback', () {
    for (final bad in const [
      '$sentence@', // empty host
      '@cozy.example.net', // empty room
      '$sentence@cozy.example.net:abc', // non-numeric port
      '$sentence@cozy.example.net:70000', // port out of range
      '$sentence@cozy.example.net:0', // port out of range
      '$sentence@host@extra', // a second @
      '$sentence@cozy example.net', // whitespace in host
    ]) {
      test('rejects "$bad"', () {
        final r = parseShareCode(bad);
        expect(r.isValid, isFalse);
        expect(r.error, malformedShareCodeMessage);
      });
    }
  });
}
