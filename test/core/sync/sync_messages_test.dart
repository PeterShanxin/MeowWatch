import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_messages.dart';

void main() {
  group('LineFramer', () {
    test('splits a single complete line', () {
      final framer = LineFramer();
      final lines = framer.addChunk(utf8.encode('hello\r\n'));
      expect(lines, ['hello']);
    });

    test('buffers a partial line until terminator arrives', () {
      final framer = LineFramer();
      expect(framer.addChunk(utf8.encode('hel')), isEmpty);
      expect(framer.addChunk(utf8.encode('lo\r\n')), ['hello']);
    });

    test('returns multiple lines from one chunk', () {
      final framer = LineFramer();
      final lines = framer.addChunk(utf8.encode('a\r\nb\r\nc\r\n'));
      expect(lines, ['a', 'b', 'c']);
    });

    test('tolerates lone newline terminator', () {
      final framer = LineFramer();
      expect(framer.addChunk(utf8.encode('x\ny\n')), ['x', 'y']);
    });
  });

  group('encoders', () {
    test('encodeHello builds the documented structure', () {
      final hello = encodeHello(
        username: 'lin',
        room: 'cozy-fox-42',
        password: null,
      );
      expect(hello, {
        'Hello': {
          'username': 'lin',
          'room': {'name': 'cozy-fox-42'},
          'version': '1.2.255',
          'realversion': '1.7.5',
          'features': isA<Map<String, Object>>(),
        },
      });
    });

    test('encodeHello includes password when given', () {
      final hello = encodeHello(
        username: 'lin',
        room: 'r',
        password: 'secret',
      );
      final inner = (hello['Hello']! as Map)['password'];
      expect(inner, 'secret');
    });

    test('encodeFile builds Set.file', () {
      final msg = encodeFile(
        name: 'movie.mkv',
        sizeBytes: 1024,
        duration: const Duration(seconds: 90),
      );
      expect(msg, {
        'Set': {
          'file': {'name': 'movie.mkv', 'duration': 90.0, 'size': 1024},
        },
      });
    });

    test('encodeTlsRequest builds startTLS send', () {
      expect(encodeTlsRequest(), {
        'TLS': {'startTLS': 'send'},
      });
    });

    test('encodeChat builds Chat', () {
      expect(encodeChat('hi'), {'Chat': 'hi'});
    });

    test('encodeList builds List null', () {
      expect(encodeList(), {'List': null});
    });

    test('encodeState builds playstate and ping', () {
      final msg = encodeState(
        position: const Duration(seconds: 5),
        paused: false,
        doSeek: false,
        latencyCalculation: 111.0,
        clientLatencyCalculation: 222.0,
        clientRtt: 0.05,
        clientIgnore: 0,
        serverIgnore: 0,
      );
      final state = msg['State']! as Map;
      expect((state['playstate']! as Map)['position'], 5.0);
      expect((state['playstate']! as Map)['paused'], false);
      expect((state['ping']! as Map)['latencyCalculation'], 111.0);
      expect((state['ping']! as Map)['clientLatencyCalculation'], 222.0);
      expect(state.containsKey('ignoringOnTheFly'), isFalse);
    });

    test('encodeState includes doSeek and ignoringOnTheFly when set', () {
      final msg = encodeState(
        position: const Duration(seconds: 5),
        paused: false,
        doSeek: true,
        latencyCalculation: null,
        clientLatencyCalculation: 222.0,
        clientRtt: 0.05,
        clientIgnore: 1,
        serverIgnore: 0,
      );
      final state = msg['State']! as Map;
      expect((state['playstate']! as Map)['doSeek'], true);
      expect((state['ignoringOnTheFly']! as Map)['client'], 1);
    });
  });

  group('decodeServerMessage', () {
    test('classifies a Hello', () {
      final m = decodeServerMessage({'Hello': {'username': 'lin'}});
      expect(m, isA<HelloMessage>());
    });

    test('classifies a State with playstate and ping', () {
      final m = decodeServerMessage({
        'State': {
          'playstate': {'position': 12.5, 'paused': true, 'setBy': 'lin'},
          'ping': {'latencyCalculation': 99.0},
        },
      }) as StateMessage;
      expect(m.peer!.position, const Duration(milliseconds: 12500));
      expect(m.peer!.paused, isTrue);
      expect(m.peer!.setBy, 'lin');
      expect(m.latencyCalculation, 99.0);
    });

    test('extracts the echoed clientLatencyCalculation from a State ping', () {
      final m = decodeServerMessage({
        'State': {
          'ping': {'latencyCalculation': 99.0, 'clientLatencyCalculation': 222.5},
        },
      }) as StateMessage;
      expect(m.clientLatencyCalculation, 222.5);
    });

    test('classifies a State carrying ignoringOnTheFly', () {
      final m = decodeServerMessage({
        'State': {
          'ignoringOnTheFly': {'server': 3},
          'ping': {'latencyCalculation': 1.0},
        },
      }) as StateMessage;
      expect(m.serverIgnore, 3);
      expect(m.peer, isNull);
    });

    test('classifies Set user joined as presence', () {
      final m = decodeServerMessage({
        'Set': {
          'user': {
            'lin': {
              'room': {'name': 'r'},
              'event': {'joined': true},
            },
          },
        },
      }) as PresenceMessage;
      expect(m.events.single.username, 'lin');
      expect(m.events.single.kind, PresenceKind.joined);
    });

    test('classifies Chat', () {
      final m = decodeServerMessage({
        'Chat': {'username': 'lin', 'message': 'hi'},
      }) as ChatServerMessage;
      expect(m.message.username, 'lin');
      expect(m.message.text, 'hi');
    });

    test('classifies TLS', () {
      final m = decodeServerMessage({'TLS': {'startTLS': 'true'}})
          as TlsMessage;
      expect(m.startTls, isTrue);
    });

    test('classifies Error', () {
      final m = decodeServerMessage({'Error': {'message': 'bad'}})
          as ErrorMessage;
      expect(m.message, 'bad');
    });

    test('classifies List into a roster of usernames', () {
      final m = decodeServerMessage({
        'List': {
          'room': {
            'A': {'position': 0},
            'B': {'position': 0},
          },
        },
      }) as RosterMessage;
      expect(m.usernames, containsAll(<String>['A', 'B']));
    });

    test('roster keeps only the given room when selfRoom is set', () {
      final m = decodeServerMessage({
        'List': {
          'ours': {
            'A': {'position': 0},
            'B': {'position': 0},
          },
          'someone-elses-room': {
            'stranger': {'position': 0},
          },
        },
      }, selfRoom: 'ours') as RosterMessage;
      expect(m.usernames, containsAll(<String>['A', 'B']));
      expect(m.usernames, isNot(contains('stranger')));
    });

    test('roster carries peer files', () {
      final m = decodeServerMessage({
        'List': {
          'room': {
            'A': {
              'file': {'name': 'movie.mkv', 'size': 1000, 'duration': 60.0},
            },
            'B': {'position': 0},
          },
        },
      }) as RosterMessage;
      final fileA = m.files.singleWhere((f) => f.username == 'A');
      expect(fileA.name, 'movie.mkv');
      expect(fileA.sizeBytes, 1000);
      expect(fileA.duration, const Duration(seconds: 60));
      expect(m.files.where((f) => f.username == 'B'), isEmpty);
    });

    test('classifies a standalone Set file as PeerFileMessage', () {
      final m = decodeServerMessage({
        'Set': {
          'user': {
            'lin': {
              'file': {'name': 'show.mp4', 'size': 2048, 'duration': 12.5},
            },
          },
        },
      }) as PeerFileMessage;
      expect(m.files.single.username, 'lin');
      expect(m.files.single.name, 'show.mp4');
      expect(m.files.single.sizeBytes, 2048);
      expect(m.files.single.duration, const Duration(milliseconds: 12500));
    });

    test('Set with join event keeps presence AND surfaces the file', () {
      final m = decodeServerMessage({
        'Set': {
          'user': {
            'lin': {
              'event': {'joined': true},
              'file': {'name': 'show.mp4', 'size': 2048},
            },
          },
        },
      });
      expect(m, isA<PresenceMessage>());
      final pm = m as PresenceMessage;
      expect(pm.events.single.fileName, 'show.mp4');
      // A peer joining with a file already loaded must not lose that file.
      expect(pm.files.single.name, 'show.mp4');
      expect(pm.files.single.sizeBytes, 2048);
    });

    test('unknown command yields UnknownMessage', () {
      final m = decodeServerMessage({'Whatever': 1});
      expect(m, isA<UnknownMessage>());
    });
  });
}
