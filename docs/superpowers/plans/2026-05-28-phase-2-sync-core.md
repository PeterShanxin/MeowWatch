# Phase 2: Sync Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a custom Dart client of the Syncplay text protocol and wire it to the existing `VideoCore` so two MeowWatch instances joined to the same room sync play/pause/seek through a public Syncplay server.

**Architecture:** A `SyncCore` abstraction (mirrors the Phase 1 `VideoCore` pattern: imperative methods in, broadcast streams out) with a concrete `SyncplayClient` that speaks the line-based JSON protocol over a TCP socket upgraded to TLS. A `PlaybackSyncBridge` connects `SyncCore` ↔ `VideoCore`: local play/pause/seek is pushed to the server; remote peer state is applied to the local player, with a guard so applied-remote changes are not echoed back. A throwaway dev connect bar lets a human start two instances and join a room until the real connect screen lands in Phase 4.

**Tech Stack:** Dart `dart:io` (`Socket`, `SecureSocket`), `dart:convert` (`json`), existing `VideoCore`/`PlaybackState` from Phase 1. Tests: `flutter_test` + `mocktail`. Target server: `syncplay.pl:8999` (TLS required).

**Protocol reference (verified against upstream `syncplay/protocols.py` + `client.py`, May 2026):**
- Transport: one JSON object per line, terminated `\r\n`, UTF-8.
- Handshake: optional `{"TLS":{"startTLS":"send"}}` → server `{"TLS":{"startTLS":"true"}}` → upgrade socket to TLS → `{"Hello":{...}}` → server `Hello` reply = connected.
- `Hello` payload: `{"username":str, "password"?:str, "room":{"name":str}, "version":"1.2.255", "realversion":"1.7.5", "features":{...}}`.
- File announce: `{"Set":{"file":{"name":str,"duration":float_seconds,"size":int_bytes}}}` followed by `{"List":null}`.
- Server pushes `{"State":{"playstate":{"position":float,"paused":bool,"doSeek"?:bool,"setBy"?:str},"ping":{"latencyCalculation"?:float,"serverRtt"?:float},"ignoringOnTheFly"?:{...}}}` roughly once per second. The client MUST reply to every server `State` with its own `State` (this is the heartbeat).
- `ignoringOnTheFly` is the seek/pause handshake: when the local user changes state the client increments `client` and includes it; the server echoes it; until echoed the client ignores incoming positions so its own change is not overwritten.
- Peers appear via `{"Set":{"user":{"<name>":{"room":{"name":..},"file":{..},"event"?:{"joined"|"left":..}}}}}`.
- Chat: `{"Chat":{"username":str,"message":str}}` (received plumbed to a stream; no chat UI this phase).

**Intentionally deferred (spec §5.2 lists them, but they belong to later roadmap phases):**
- Chat UI and the `__meow__:` custom-event hack → Phase 3 / Phase 6. Chat *receive* is plumbed to a stream now; nothing renders it.
- File-mismatch detection/helper → Phase 6. We announce our file but do not diff the peer's.
- "Ready" state propagation → not needed for play/pause/seek sync; later phase.
- Connect screen + saved profiles → Phase 4. This phase uses a throwaway dev connect bar.

---

## File Structure (Phase 2 deliverables)

```
D:\Repos\MeowWatch\
├── lib\
│   ├── core\
│   │   └── sync\
│   │       ├── syncplay_constants.dart      # Port, version strings, features map, sync thresholds, default server
│   │       ├── sync_messages.dart           # Encode helpers (Map builders) + decode classifier + LineFramer
│   │       ├── peer_state.dart              # PeerPlayState, PresenceEvent, ChatMessage, SyncConnectionState data classes
│   │       ├── ping_service.dart            # RTT moving average + forward-delay (latency compensation)
│   │       ├── sync_core.dart               # Abstract SyncCore interface (streams + commands)
│   │       ├── syncplay_client.dart         # Concrete SyncCore over Socket/SecureSocket + handshake state machine
│   │       └── playback_sync_bridge.dart    # Wires SyncCore <-> VideoCore with loop guard + drift threshold
│   └── ui\
│       └── dev_connect_bar.dart             # TEMP throwaway connect form (removed/replaced in Phase 4)
└── test\
    └── core\
        └── sync\
            ├── sync_messages_test.dart
            ├── peer_state_test.dart
            ├── ping_service_test.dart
            ├── sync_core_test.dart           # Contract tests against FakeSyncCore
            └── playback_sync_bridge_test.dart
```

`SyncplayClient` (real socket) is exercised by manual E2E (Task 14) because it needs a live server. All pure logic — message encode/decode, framing, ping math, the bridge — is unit-tested with fakes.

---

## Task 1: Syncplay constants

**Files:**
- Create: `lib/core/sync/syncplay_constants.dart`
- Test: none (constants only)

- [ ] **Step 1: Write the constants file**

Content for `lib/core/sync/syncplay_constants.dart`:

```dart
/// Wire-protocol constants for the Syncplay client, verified against upstream
/// syncplay/constants.py (May 2026).
class SyncplayConstants {
  SyncplayConstants._();

  /// Sent as `version` in Hello for backward compat; real version goes in
  /// `realversion`. Upstream clients do exactly this.
  static const protocolVersion = '1.2.255';
  static const realVersion = '1.7.5';

  static const defaultServer = 'syncplay.pl';
  static const defaultPort = 8999;

  /// Feature map advertised in Hello. We support chat receive only this phase,
  /// but advertise the standard static flags so servers treat us as a modern
  /// client.
  static const features = <String, Object>{
    'sharedPlaylists': false,
    'chat': true,
    'featureList': true,
    'readiness': true,
    'managedRooms': true,
    'persistentRooms': true,
    'setOthersReadiness': false,
  };

  /// If the local position differs from the latency-adjusted peer position by
  /// more than this while following, hard-seek to match. Upstream uses ~1s.
  static const seekThreshold = Duration(milliseconds: 1500);

  /// Below this, a position change is treated as natural playback drift rather
  /// than a user seek.
  static const seekDetectThreshold = Duration(milliseconds: 1000);
}
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/sync/syncplay_constants.dart
git commit -m "feat(sync): add Syncplay protocol constants"
```

---

## Task 2: Data types (`peer_state.dart`)

**Files:**
- Create: `lib/core/sync/peer_state.dart`
- Test: `test/core/sync/peer_state_test.dart`

- [ ] **Step 1: Write the failing test**

Content for `test/core/sync/peer_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';

void main() {
  group('PeerPlayState', () {
    test('positionFromSeconds converts float seconds to Duration', () {
      final s = PeerPlayState.fromSeconds(
        seconds: 12.5,
        paused: false,
        doSeek: true,
        setBy: 'lin',
      );
      expect(s.position, const Duration(milliseconds: 12500));
      expect(s.paused, isFalse);
      expect(s.doSeek, isTrue);
      expect(s.setBy, 'lin');
    });

    test('positionSeconds converts Duration back to float seconds', () {
      const s = PeerPlayState(
        position: Duration(milliseconds: 3200),
        paused: true,
      );
      expect(s.positionSeconds, 3.2);
      expect(s.doSeek, isFalse);
    });

    test('equal states are equal', () {
      const a = PeerPlayState(position: Duration(seconds: 1), paused: false);
      const b = PeerPlayState(position: Duration(seconds: 1), paused: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SyncConnectionState', () {
    test('carries status and optional message', () {
      const c = SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: 'boom',
      );
      expect(c.status, SyncConnectionStatus.error);
      expect(c.message, 'boom');
    });
  });

  group('PresenceEvent', () {
    test('captures username and kind', () {
      const e = PresenceEvent(username: 'lin', kind: PresenceKind.joined);
      expect(e.username, 'lin');
      expect(e.kind, PresenceKind.joined);
    });
  });

  group('ChatMessage', () {
    test('captures username and text', () {
      const m = ChatMessage(username: 'lin', text: 'hi');
      expect(m.username, 'lin');
      expect(m.text, 'hi');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/peer_state_test.dart`
Expected: FAIL — `peer_state.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Content for `lib/core/sync/peer_state.dart`:

```dart
import 'package:flutter/foundation.dart';

enum SyncConnectionStatus { disconnected, connecting, handshaking, connected, error }

@immutable
class SyncConnectionState {
  const SyncConnectionState({required this.status, this.message});

  final SyncConnectionStatus status;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is SyncConnectionState &&
      other.status == status &&
      other.message == message;

  @override
  int get hashCode => Object.hash(status, message);
}

@immutable
class PeerPlayState {
  const PeerPlayState({
    required this.position,
    required this.paused,
    this.doSeek = false,
    this.setBy,
  });

  factory PeerPlayState.fromSeconds({
    required double seconds,
    required bool paused,
    bool doSeek = false,
    String? setBy,
  }) {
    return PeerPlayState(
      position: Duration(milliseconds: (seconds * 1000).round()),
      paused: paused,
      doSeek: doSeek,
      setBy: setBy,
    );
  }

  final Duration position;
  final bool paused;
  final bool doSeek;
  final String? setBy;

  double get positionSeconds => position.inMilliseconds / 1000.0;

  @override
  bool operator ==(Object other) =>
      other is PeerPlayState &&
      other.position == position &&
      other.paused == paused &&
      other.doSeek == doSeek &&
      other.setBy == setBy;

  @override
  int get hashCode => Object.hash(position, paused, doSeek, setBy);
}

enum PresenceKind { joined, left }

@immutable
class PresenceEvent {
  const PresenceEvent({
    required this.username,
    required this.kind,
    this.room,
    this.fileName,
  });

  final String username;
  final PresenceKind kind;
  final String? room;
  final String? fileName;
}

@immutable
class ChatMessage {
  const ChatMessage({required this.username, required this.text});

  final String username;
  final String text;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/peer_state_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/peer_state.dart test/core/sync/peer_state_test.dart
git commit -m "feat(sync): add peer/connection/chat data types"
```

---

## Task 3: Line framing (`LineFramer` in `sync_messages.dart`)

The socket delivers arbitrary byte chunks; the protocol is line-delimited. `LineFramer` buffers bytes and yields complete UTF-8 lines.

**Files:**
- Create: `lib/core/sync/sync_messages.dart` (framer only this task; encode/decode added in Task 4)
- Test: `test/core/sync/sync_messages_test.dart`

- [ ] **Step 1: Write the failing test**

Content for `test/core/sync/sync_messages_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_messages_test.dart`
Expected: FAIL — `sync_messages.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Content for `lib/core/sync/sync_messages.dart`:

```dart
import 'dart:convert';

/// Buffers raw socket bytes and yields complete lines. The Syncplay protocol
/// sends one JSON object per line terminated by `\r\n`; we also tolerate a lone
/// `\n`.
class LineFramer {
  final List<int> _buffer = <int>[];

  List<String> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0x0A) {
        // newline
        var end = i;
        if (end > start && _buffer[end - 1] == 0x0D) {
          end -= 1; // strip preceding carriage return
        }
        lines.add(utf8.decode(_buffer.sublist(start, end)));
        start = i + 1;
      }
    }
    _buffer.removeRange(0, start);
    return lines;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_messages_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_messages.dart test/core/sync/sync_messages_test.dart
git commit -m "feat(sync): add LineFramer for socket byte buffering"
```

---

## Task 4: Message encoders + decoder classifier

Encoders return the `Map` to be JSON-serialized. The decoder classifies an incoming parsed `Map` into a typed `ServerMessage`.

**Files:**
- Modify: `lib/core/sync/sync_messages.dart`
- Modify: `test/core/sync/sync_messages_test.dart`

- [ ] **Step 1: Add failing tests**

Append to `test/core/sync/sync_messages_test.dart` (inside `main()`, after the `LineFramer` group):

```dart
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

    test('unknown command yields UnknownMessage', () {
      final m = decodeServerMessage({'Whatever': 1});
      expect(m, isA<UnknownMessage>());
    });
  });
```

Add this import at the top of the test file (it already imports sync_messages and dart:convert):

```dart
import 'package:meowwatch/core/sync/peer_state.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_messages_test.dart`
Expected: FAIL — encoder/decoder functions and message types not defined.

- [ ] **Step 3: Write the implementation**

Append to `lib/core/sync/sync_messages.dart` (add imports at top):

```dart
import 'syncplay_constants.dart';
import 'peer_state.dart';
```

Then append:

```dart
// ---------------------------------------------------------------------------
// Encoders — each returns the Map to be json.encode()'d and written as a line.
// ---------------------------------------------------------------------------

Map<String, Object?> encodeHello({
  required String username,
  required String room,
  String? password,
}) {
  final hello = <String, Object?>{
    'username': username,
    'room': {'name': room},
    'version': SyncplayConstants.protocolVersion,
    'realversion': SyncplayConstants.realVersion,
    'features': SyncplayConstants.features,
  };
  if (password != null && password.isNotEmpty) {
    hello['password'] = password;
  }
  return {'Hello': hello};
}

Map<String, Object?> encodeFile({
  required String name,
  required int sizeBytes,
  required Duration duration,
}) {
  return {
    'Set': {
      'file': {
        'name': name,
        'duration': duration.inMilliseconds / 1000.0,
        'size': sizeBytes,
      },
    },
  };
}

Map<String, Object?> encodeTlsRequest() => {
      'TLS': {'startTLS': 'send'},
    };

Map<String, Object?> encodeChat(String text) => {'Chat': text};

Map<String, Object?> encodeList() => {'List': null};

Map<String, Object?> encodeState({
  required Duration position,
  required bool paused,
  required bool doSeek,
  required double? latencyCalculation,
  required double clientLatencyCalculation,
  required double clientRtt,
  required int clientIgnore,
  required int serverIgnore,
}) {
  final playstate = <String, Object?>{
    'position': position.inMilliseconds / 1000.0,
    'paused': paused,
  };
  if (doSeek) playstate['doSeek'] = true;

  final ping = <String, Object?>{
    'clientLatencyCalculation': clientLatencyCalculation,
    'clientRtt': clientRtt,
  };
  if (latencyCalculation != null) {
    ping['latencyCalculation'] = latencyCalculation;
  }

  final state = <String, Object?>{
    'playstate': playstate,
    'ping': ping,
  };

  if (clientIgnore != 0 || serverIgnore != 0) {
    final ignore = <String, Object?>{};
    if (serverIgnore != 0) ignore['server'] = serverIgnore;
    if (clientIgnore != 0) ignore['client'] = clientIgnore;
    state['ignoringOnTheFly'] = ignore;
  }

  return {'State': state};
}

// ---------------------------------------------------------------------------
// Decoder — classify an incoming parsed Map into a typed ServerMessage.
// ---------------------------------------------------------------------------

sealed class ServerMessage {
  const ServerMessage();
}

class HelloMessage extends ServerMessage {
  const HelloMessage();
}

class StateMessage extends ServerMessage {
  const StateMessage({
    this.peer,
    this.latencyCalculation,
    this.clientIgnore,
    this.serverIgnore,
  });

  /// Peer playstate, or null if this State carried no playstate block.
  final PeerPlayState? peer;
  final double? latencyCalculation;
  final int? clientIgnore;
  final int? serverIgnore;
}

class PresenceMessage extends ServerMessage {
  const PresenceMessage(this.events);
  final List<PresenceEvent> events;
}

class ChatServerMessage extends ServerMessage {
  const ChatServerMessage(this.message);
  final ChatMessage message;
}

class TlsMessage extends ServerMessage {
  const TlsMessage({required this.startTls});
  final bool startTls;
}

class ErrorMessage extends ServerMessage {
  const ErrorMessage(this.message);
  final String message;
}

class UnknownMessage extends ServerMessage {
  const UnknownMessage();
}

ServerMessage decodeServerMessage(Map<dynamic, dynamic> message) {
  if (message.containsKey('Hello')) return const HelloMessage();
  if (message.containsKey('State')) return _decodeState(message['State'] as Map);
  if (message.containsKey('Set')) return _decodeSet(message['Set'] as Map);
  if (message.containsKey('Chat')) {
    final chat = message['Chat'] as Map;
    return ChatServerMessage(ChatMessage(
      username: chat['username'] as String? ?? '',
      text: chat['message'] as String? ?? '',
    ));
  }
  if (message.containsKey('TLS')) {
    final tls = message['TLS'] as Map;
    final answer = tls['startTLS'];
    return TlsMessage(startTls: answer is String && answer.contains('true'));
  }
  if (message.containsKey('Error')) {
    final err = message['Error'] as Map;
    return ErrorMessage(err['message'] as String? ?? 'unknown error');
  }
  return const UnknownMessage();
}

StateMessage _decodeState(Map state) {
  PeerPlayState? peer;
  if (state['playstate'] is Map) {
    final ps = state['playstate'] as Map;
    final pos = ps['position'];
    final paused = ps['paused'];
    if (pos is num && paused is bool) {
      peer = PeerPlayState.fromSeconds(
        seconds: pos.toDouble(),
        paused: paused,
        doSeek: ps['doSeek'] == true,
        setBy: ps['setBy'] as String?,
      );
    }
  }
  double? latency;
  if (state['ping'] is Map) {
    final ping = state['ping'] as Map;
    final lc = ping['latencyCalculation'];
    if (lc is num) latency = lc.toDouble();
  }
  int? clientIgnore;
  int? serverIgnore;
  if (state['ignoringOnTheFly'] is Map) {
    final ig = state['ignoringOnTheFly'] as Map;
    if (ig['client'] is num) clientIgnore = (ig['client'] as num).toInt();
    if (ig['server'] is num) serverIgnore = (ig['server'] as num).toInt();
  }
  return StateMessage(
    peer: peer,
    latencyCalculation: latency,
    clientIgnore: clientIgnore,
    serverIgnore: serverIgnore,
  );
}

ServerMessage _decodeSet(Map set) {
  if (set['user'] is Map) {
    final events = <PresenceEvent>[];
    (set['user'] as Map).forEach((name, value) {
      if (value is! Map) return;
      final room = value['room'] is Map ? (value['room'] as Map)['name'] as String? : null;
      final fileName = value['file'] is Map ? (value['file'] as Map)['name'] as String? : null;
      final event = value['event'];
      if (event is Map && event['left'] != null) {
        events.add(PresenceEvent(
          username: name as String,
          kind: PresenceKind.left,
          room: room,
          fileName: fileName,
        ));
      } else if (event is Map && event['joined'] != null) {
        events.add(PresenceEvent(
          username: name as String,
          kind: PresenceKind.joined,
          room: room,
          fileName: fileName,
        ));
      }
    });
    if (events.isNotEmpty) return PresenceMessage(events);
  }
  return const UnknownMessage();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_messages_test.dart`
Expected: PASS (all encoder + decoder tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_messages.dart test/core/sync/sync_messages_test.dart
git commit -m "feat(sync): add protocol message encoders and decoder"
```

---

## Task 5: Ping service (latency math)

Tracks round-trip time as a moving average and reports the forward delay used to advance a peer's position for the time the State spent in transit.

**Files:**
- Create: `lib/core/sync/ping_service.dart`
- Test: `test/core/sync/ping_service_test.dart`

- [ ] **Step 1: Write the failing test**

Content for `test/core/sync/ping_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/ping_service.dart';

void main() {
  group('PingService', () {
    test('first RTT sample is adopted directly', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('subsequent samples are exponentially weighted', () {
      final ping = PingService(weight: 0.85);
      ping.recordRtt(0.10);
      ping.recordRtt(0.20);
      // 0.85*0.10 + 0.15*0.20 = 0.115
      expect(ping.rtt, closeTo(0.115, 1e-9));
    });

    test('forwardDelay is half the RTT', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.forwardDelay, closeTo(0.05, 1e-9));
    });

    test('newTimestamp returns a monotonically sensible epoch seconds', () {
      final ping = PingService();
      final a = ping.newTimestamp();
      expect(a, greaterThan(0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/ping_service_test.dart`
Expected: FAIL — `ping_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Content for `lib/core/sync/ping_service.dart`:

```dart
/// Tracks RTT as an exponential moving average and derives the one-way forward
/// delay used to latency-compensate a peer's reported position. Mirrors
/// upstream's PingService (PING_MOVING_AVERAGE_WEIGHT = 0.85).
class PingService {
  PingService({this.weight = 0.85});

  final double weight;
  double _rtt = 0.0;
  bool _hasSample = false;

  double get rtt => _rtt;

  /// One-way delay estimate (half the round trip).
  double get forwardDelay => _rtt / 2.0;

  void recordRtt(double sample) {
    if (!_hasSample) {
      _rtt = sample;
      _hasSample = true;
    } else {
      _rtt = weight * _rtt + (1 - weight) * sample;
    }
  }

  /// Epoch seconds as a double, sent as clientLatencyCalculation so the peer's
  /// echo lets us measure RTT on the next State.
  double newTimestamp() =>
      DateTime.now().millisecondsSinceEpoch / 1000.0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/ping_service_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/ping_service.dart test/core/sync/ping_service_test.dart
git commit -m "feat(sync): add PingService for latency compensation"
```

---

## Task 6: `SyncCore` abstract interface + contract tests

Mirrors the Phase 1 `VideoCore` pattern: broadcast streams out, imperative commands in. A `FakeSyncCore` in the test verifies the base wiring.

**Files:**
- Create: `lib/core/sync/sync_core.dart`
- Test: `test/core/sync/sync_core_test.dart`

- [ ] **Step 1: Write the failing test**

Content for `test/core/sync/sync_core_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';

class FakeSyncCore extends SyncCore {
  bool connected = false;
  Duration? lastSentPosition;
  bool? lastSentPaused;
  bool? lastSentDoSeek;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    connected = true;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connected),
    );
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  // Test helper to drive the peer stream.
  void pushPeer(PeerPlayState s) => emitPeerState(s);
}

void main() {
  late FakeSyncCore core;

  setUp(() => core = FakeSyncCore());
  tearDown(() async => core.dispose());

  test('connect emits connected state', () async {
    final states = <SyncConnectionState>[];
    final sub = core.connectionState.listen(states.add);
    await core.connect(
      server: 's',
      port: 1,
      username: 'u',
      room: 'r',
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(states.last.status, SyncConnectionStatus.connected);
  });

  test('peer state stream emits pushed states', () async {
    final peers = <PeerPlayState>[];
    final sub = core.peerState.listen(peers.add);
    core.pushPeer(const PeerPlayState(position: Duration(seconds: 3), paused: false));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(peers.single.position, const Duration(seconds: 3));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_core_test.dart`
Expected: FAIL — `sync_core.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Content for `lib/core/sync/sync_core.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'peer_state.dart';

/// Abstract interface for room sync. Implementations may speak the Syncplay
/// protocol over a socket, or be a fake for tests. Commands in, streams out —
/// the same shape as VideoCore.
abstract class SyncCore {
  final StreamController<SyncConnectionState> _connection =
      StreamController<SyncConnectionState>.broadcast();
  final StreamController<PeerPlayState> _peer =
      StreamController<PeerPlayState>.broadcast();
  final StreamController<PresenceEvent> _presence =
      StreamController<PresenceEvent>.broadcast();
  final StreamController<ChatMessage> _chat =
      StreamController<ChatMessage>.broadcast();
  bool _disposed = false;

  Stream<SyncConnectionState> get connectionState => _connection.stream;
  Stream<PeerPlayState> get peerState => _peer.stream;
  Stream<PresenceEvent> get presence => _presence.stream;
  Stream<ChatMessage> get chat => _chat.stream;

  @protected
  void emitConnectionState(SyncConnectionState s) {
    if (!_disposed) _connection.add(s);
  }

  @protected
  void emitPeerState(PeerPlayState s) {
    if (!_disposed) _peer.add(s);
  }

  @protected
  void emitPresence(PresenceEvent e) {
    if (!_disposed) _presence.add(e);
  }

  @protected
  void emitChat(ChatMessage m) {
    if (!_disposed) _chat.add(m);
  }

  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  });

  Future<void> disconnect();

  /// Announce the locally loaded file to the room.
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  });

  /// Push the latest local playback position/paused state. Called frequently
  /// (every position tick); the implementation stores it for the next State
  /// heartbeat — it does not necessarily transmit immediately.
  void updateLocalState({required Duration position, required bool paused});

  /// Mark that the local user just changed state (play/pause/seek) so the next
  /// State carries the ignoringOnTheFly handshake. [doSeek] true for seeks.
  void notifyLocalChange({required bool doSeek});

  void sendChat(String text);

  @protected
  Future<void> disposeBackend();

  @mustCallSuper
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disposeBackend();
    await _connection.close();
    await _peer.close();
    await _presence.close();
    await _chat.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/sync_core_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/sync_core.dart test/core/sync/sync_core_test.dart
git commit -m "feat(sync): add SyncCore abstract interface"
```

---

## Task 7: `PlaybackSyncBridge` — local change detection

The bridge listens to `VideoCore.stateStream`, pushes the position to `SyncCore.updateLocalState` every tick, and detects user-initiated changes (pause toggle or seek) to call `notifyLocalChange`. A guard prevents changes the bridge itself applied (from remote) being re-sent.

**Files:**
- Create: `lib/core/sync/playback_sync_bridge.dart`
- Test: `test/core/sync/playback_sync_bridge_test.dart`

- [ ] **Step 1: Write the failing test**

Content for `test/core/sync/playback_sync_bridge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(fileName: filePath, status: PlaybackStatus.paused));
  }

  @override
  Future<void> play() async => emit(state.copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async => emit(state.copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> seek(Duration position) async => emit(state.copyWith(position: position));

  @override
  Future<void> setVolume(double volume) async => emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {}

  // Drive an arbitrary state for tests.
  void push(PlaybackState s) => emit(s);
}

class _RecordingSyncCore extends SyncCore {
  final List<({Duration position, bool paused})> localUpdates = [];
  final List<bool> changes = []; // doSeek values

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile({required String name, required int size, required Duration duration}) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {
    localUpdates.add((position: position, paused: paused));
  }

  @override
  void notifyLocalChange({required bool doSeek}) => changes.add(doSeek);

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  void pushPeer(PeerPlayState s) => emitPeerState(s);
}

void main() {
  late _FakeVideoCore video;
  late _RecordingSyncCore sync;
  late PlaybackSyncBridge bridge;

  setUp(() {
    video = _FakeVideoCore();
    sync = _RecordingSyncCore();
    bridge = PlaybackSyncBridge(video: video, sync: sync)..start();
  });

  tearDown(() async {
    await bridge.dispose();
    await video.dispose();
    await sync.dispose();
  });

  test('local pause toggle notifies a non-seek change', () async {
    video.push(const PlaybackState(status: PlaybackStatus.playing, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    video.push(const PlaybackState(status: PlaybackStatus.paused, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(false));
  });

  test('a large position jump is detected as a seek', () async {
    video.push(const PlaybackState(
        status: PlaybackStatus.playing, position: Duration(seconds: 1), fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    video.push(const PlaybackState(
        status: PlaybackStatus.playing, position: Duration(seconds: 30), fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(true));
  });

  test('applying a remote peer state does not re-notify a local change', () async {
    sync.changes.clear();
    sync.pushPeer(const PeerPlayState(position: Duration(seconds: 10), paused: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // The bridge sought/played the video to follow the peer; that must NOT be
    // reported back as a local change.
    expect(sync.changes, isEmpty);
    expect(video.state.position, const Duration(seconds: 10));
  });

  test('remote paused state pauses the local video', () async {
    video.push(const PlaybackState(status: PlaybackStatus.playing, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    sync.pushPeer(const PeerPlayState(position: Duration(seconds: 5), paused: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.status, PlaybackStatus.paused);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/playback_sync_bridge_test.dart`
Expected: FAIL — `playback_sync_bridge.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Content for `lib/core/sync/playback_sync_bridge.dart`:

```dart
import 'dart:async';

import '../video/playback_state.dart';
import '../video/video_core.dart';
import 'peer_state.dart';
import 'sync_core.dart';
import 'syncplay_constants.dart';

/// Connects a [VideoCore] to a [SyncCore]. Local user changes (pause/play,
/// seek) are reported to the sync layer; remote peer states are applied to the
/// local player. An [_applyingRemote] guard prevents a remote-applied change
/// from being echoed straight back to the room.
class PlaybackSyncBridge {
  PlaybackSyncBridge({
    required this.video,
    required this.sync,
    this.seekDetectThreshold = SyncplayConstants.seekDetectThreshold,
    this.followSeekThreshold = SyncplayConstants.seekThreshold,
  });

  final VideoCore video;
  final SyncCore sync;
  final Duration seekDetectThreshold;
  final Duration followSeekThreshold;

  StreamSubscription<PlaybackState>? _videoSub;
  StreamSubscription<PeerPlayState>? _peerSub;

  bool _applyingRemote = false;
  bool? _lastPaused;
  Duration _lastPosition = Duration.zero;
  DateTime _lastTick = DateTime.now();

  void start() {
    _videoSub = video.stateStream.listen(_onLocalState);
    _peerSub = sync.peerState.listen(_onPeerState);
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;

    // Always feed the latest position to the sync layer for its heartbeat.
    sync.updateLocalState(position: s.position, paused: paused);

    if (_applyingRemote) {
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = DateTime.now();
      return;
    }

    // Pause/play transition.
    if (_lastPaused != null && paused != _lastPaused) {
      sync.notifyLocalChange(doSeek: false);
    } else {
      // Seek detection: compare actual position to where natural playback
      // would have carried us since the last tick.
      final now = DateTime.now();
      final elapsed = (_lastPaused == false)
          ? now.difference(_lastTick)
          : Duration.zero;
      final expected = _lastPosition + elapsed;
      final diff = (s.position - expected).abs();
      if (diff > seekDetectThreshold) {
        sync.notifyLocalChange(doSeek: true);
      }
    }

    _lastPaused = paused;
    _lastPosition = s.position;
    _lastTick = DateTime.now();
  }

  Future<void> _onPeerState(PeerPlayState peer) async {
    _applyingRemote = true;
    try {
      // Match pause/play.
      final localPaused = video.state.status != PlaybackStatus.playing;
      if (peer.paused && !localPaused) {
        await video.pause();
      } else if (!peer.paused && localPaused) {
        await video.play();
      }

      // Match position when the peer explicitly seeked or drifted too far.
      final diff = (video.state.position - peer.position).abs();
      if (peer.doSeek || diff > followSeekThreshold) {
        await video.seek(peer.position);
      }
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> dispose() async {
    await _videoSub?.cancel();
    await _peerSub?.cancel();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/sync/playback_sync_bridge_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/playback_sync_bridge.dart test/core/sync/playback_sync_bridge_test.dart
git commit -m "feat(sync): add PlaybackSyncBridge linking video and sync cores"
```

---

## Task 8: `SyncplayClient` — connection + TLS handshake

The concrete `SyncCore`. This task builds the socket connection, TLS upgrade, and Hello handshake. State sync is added in Task 9. No unit test (needs a live socket); verified in manual E2E (Task 14). Keep `flutter analyze` clean throughout.

**Files:**
- Create: `lib/core/sync/syncplay_client.dart`

- [ ] **Step 1: Write the connection + handshake implementation**

Content for `lib/core/sync/syncplay_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'peer_state.dart';
import 'ping_service.dart';
import 'sync_core.dart';
import 'sync_messages.dart';

/// Concrete SyncCore speaking the Syncplay text protocol over a TCP socket
/// upgraded to TLS. One JSON object per line, terminated `\r\n`.
class SyncplayClient extends SyncCore {
  Socket? _socket;
  final LineFramer _framer = LineFramer();
  final PingService _ping = PingService();

  String _username = '';
  String _room = '';
  String? _password;

  bool _loggedIn = false;

  // Latest local playback state for the heartbeat.
  Duration _localPosition = Duration.zero;
  bool _localPaused = true;

  // ignoringOnTheFly handshake counters.
  int _clientIgnore = 0;
  int _serverIgnore = 0;
  bool _pendingStateChange = false;
  bool _pendingDoSeek = false;

  // The most recent server latencyCalculation we must echo back.
  double? _serverLatencyCalculation;

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {
    _username = username;
    _room = room;
    _password = password;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.connecting),
    );

    try {
      final plain = await Socket.connect(server, port,
          timeout: const Duration(seconds: 10));
      // Attempt TLS upgrade first (public servers require it).
      _sendRaw(plain, encodeTlsRequest());
      emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.handshaking),
      );
      _attachPlainForTlsNegotiation(plain, server);
    } on SocketException catch (e) {
      emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: 'Could not reach server: ${e.message}',
      ));
    }
  }

  /// Listen on the plain socket only long enough to receive the TLS answer,
  /// then upgrade to a SecureSocket and (re)attach the main listener.
  void _attachPlainForTlsNegotiation(Socket plain, String server) {
    late StreamSubscription<List<int>> sub;
    sub = plain.listen((chunk) async {
      for (final line in _framer.addChunk(chunk)) {
        final decoded = decodeServerMessage(
            json.decode(line) as Map<dynamic, dynamic>);
        if (decoded is TlsMessage && decoded.startTls) {
          await sub.cancel();
          final secure = await SecureSocket.secure(
            plain,
            host: server,
            onBadCertificate: (_) => false,
          );
          _bindSocket(secure);
          _sendHello();
          return;
        } else if (decoded is ErrorMessage) {
          // Server doesn't support TLS — fall back to the plain socket.
          await sub.cancel();
          _bindSocket(plain);
          _sendHello();
          return;
        }
      }
    }, onError: (Object e) {
      emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: e.toString(),
      ));
    });
  }

  void _bindSocket(Socket socket) {
    _socket = socket;
    socket.listen(
      _onChunk,
      onError: (Object e) => emitConnectionState(SyncConnectionState(
        status: SyncConnectionStatus.error,
        message: e.toString(),
      )),
      onDone: () => emitConnectionState(
        const SyncConnectionState(status: SyncConnectionStatus.disconnected),
      ),
    );
  }

  void _onChunk(List<int> chunk) {
    for (final line in _framer.addChunk(chunk)) {
      if (line.isEmpty) continue;
      late ServerMessage msg;
      try {
        msg = decodeServerMessage(json.decode(line) as Map<dynamic, dynamic>);
      } on FormatException {
        continue;
      }
      _handleMessage(msg);
    }
  }

  void _sendHello() {
    _send(encodeHello(
      username: _username,
      room: _room,
      password: _password,
    ));
  }

  void _handleMessage(ServerMessage msg) {
    switch (msg) {
      case HelloMessage():
        _loggedIn = true;
        emitConnectionState(
          const SyncConnectionState(status: SyncConnectionStatus.connected),
        );
      case PresenceMessage(:final events):
        for (final e in events) {
          emitPresence(e);
        }
      case ChatServerMessage(:final message):
        emitChat(message);
      case ErrorMessage(:final message):
        emitConnectionState(SyncConnectionState(
          status: SyncConnectionStatus.error,
          message: message,
        ));
      case StateMessage():
        _handleState(msg); // implemented in Task 9
      case TlsMessage():
      case UnknownMessage():
        break;
    }
  }

  // Filled in by Task 9.
  void _handleState(StateMessage msg) {}

  void _send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(utf8.encode('${json.encode(message)}\r\n'));
  }

  void _sendRaw(Socket socket, Map<String, Object?> message) {
    socket.add(utf8.encode('${json.encode(message)}\r\n'));
  }

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {
    if (!_loggedIn) return;
    _send(encodeFile(name: name, sizeBytes: size, duration: duration));
    _send(encodeList());
  }

  @override
  void updateLocalState({required Duration position, required bool paused}) {
    _localPosition = position;
    _localPaused = paused;
  }

  @override
  void notifyLocalChange({required bool doSeek}) {
    _pendingStateChange = true;
    if (doSeek) _pendingDoSeek = true;
  }

  @override
  void sendChat(String text) {
    if (_loggedIn) _send(encodeChat(text));
  }

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _loggedIn = false;
    emitConnectionState(
      const SyncConnectionState(status: SyncConnectionStatus.disconnected),
    );
  }

  @override
  Future<void> disposeBackend() async {
    await _socket?.close();
    _socket = null;
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/sync/syncplay_client.dart
git commit -m "feat(sync): add SyncplayClient connection + TLS handshake"
```

---

## Task 9: `SyncplayClient` — State heartbeat + ignoringOnTheFly

Fill in `_handleState` so the client replies to every server `State`, applies the peer's playstate (unless its own change is mid-handshake), and runs the `ignoringOnTheFly` counter dance.

**Files:**
- Modify: `lib/core/sync/syncplay_client.dart`

- [ ] **Step 1: Replace the `_handleState` stub**

In `lib/core/sync/syncplay_client.dart`, replace:

```dart
  // Filled in by Task 9.
  void _handleState(StateMessage msg) {}
```

with:

```dart
  void _handleState(StateMessage msg) {
    // Track the server/client ignore handshake.
    if (msg.serverIgnore != null) {
      _serverIgnore = msg.serverIgnore!;
      _clientIgnore = 0;
    } else if (msg.clientIgnore != null && msg.clientIgnore == _clientIgnore) {
      _clientIgnore = 0;
    }

    // Remember the latency timestamp we must echo, and record an RTT sample
    // from the round trip if the server reflected our clock.
    if (msg.latencyCalculation != null) {
      _serverLatencyCalculation = msg.latencyCalculation;
    }

    // Apply the peer's state unless we're mid-handshake on our own change.
    final ignoringOwnChange = _clientIgnore != 0 && _serverIgnore == 0;
    if (msg.peer != null && !ignoringOwnChange) {
      // Advance position by the one-way delay if the peer is playing.
      final adjusted = msg.peer!.paused
          ? msg.peer!
          : PeerPlayState(
              position: msg.peer!.position +
                  Duration(milliseconds: (_ping.forwardDelay * 1000).round()),
              paused: msg.peer!.paused,
              doSeek: msg.peer!.doSeek,
              setBy: msg.peer!.setBy,
            );
      emitPeerState(adjusted);
    }

    _replyState();
  }

  /// Send our own State in response to the server's (the heartbeat).
  void _replyState() {
    final stateChange = _pendingStateChange;
    if (stateChange) {
      _clientIgnore += 1;
    }

    _send(encodeState(
      position: _localPosition,
      paused: _localPaused,
      doSeek: _pendingDoSeek,
      latencyCalculation: _serverLatencyCalculation,
      clientLatencyCalculation: _ping.newTimestamp(),
      clientRtt: _ping.rtt,
      clientIgnore: _clientIgnore,
      serverIgnore: _serverIgnore,
    ));

    // Reset one-shot flags; serverIgnore is cleared once echoed.
    _pendingStateChange = false;
    _pendingDoSeek = false;
    _serverIgnore = 0;
  }
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full unit suite (nothing should regress)**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/syncplay_client.dart
git commit -m "feat(sync): implement State heartbeat and ignoringOnTheFly handshake"
```

---

## Task 10: Expose file size + duration from the video layer

The sync layer's `announceFile` needs name, size (bytes), and duration. `PlaybackState` already has `fileName` and `duration`, but the player only stores the basename and the on-disk path is lost. Thread the full path and size through so `HomeScreen` can announce the file.

**Files:**
- Modify: `lib/core/video/playback_state.dart`
- Modify: `lib/core/video/media_kit_video_core.dart`
- Modify: `test/core/video/playback_state_test.dart`

- [ ] **Step 1: Add a failing test for the new `filePath` field**

Add to `test/core/video/playback_state_test.dart` inside the `PlaybackState` group:

```dart
    test('stores optional filePath and copyWith can clear it', () {
      const s = PlaybackState(filePath: r'C:\v\movie.mkv');
      expect(s.filePath, r'C:\v\movie.mkv');
      final cleared = s.copyWith(filePath: null);
      expect(cleared.filePath, isNull);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/video/playback_state_test.dart`
Expected: FAIL — `filePath` is not a parameter of `PlaybackState`.

- [ ] **Step 3: Add `filePath` to `PlaybackState`**

In `lib/core/video/playback_state.dart`:

1. Add the constructor parameter after `fileName`:
```dart
    this.fileName,
    this.filePath,
    this.errorMessage,
```

2. Add the field after `final String? fileName;`:
```dart
  final String? filePath;
```

3. Add to `copyWith` parameters (use the same sentinel pattern as `fileName`):
```dart
    Object? fileName = _unset,
    Object? filePath = _unset,
    Object? errorMessage = _unset,
```

4. Add to the `copyWith` body after the `fileName` line:
```dart
      filePath: identical(filePath, _unset) ? this.filePath : filePath as String?,
```

5. Add to `operator ==` after the `fileName` comparison:
```dart
        other.filePath == filePath &&
```

6. Add `filePath` to the `Object.hash(...)` argument list (after `fileName`).

- [ ] **Step 4: Set `filePath` in `MediaKitVideoCore.load`**

In `lib/core/video/media_kit_video_core.dart`, update the `emit` in `load` to also store the full path:

```dart
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: p.basename(filePath),
      filePath: filePath,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
    ));
    await _player.open(Media(filePath), play: false);
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test test/core/video/playback_state_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/video/playback_state.dart lib/core/video/media_kit_video_core.dart test/core/video/playback_state_test.dart
git commit -m "feat(video): expose full filePath on PlaybackState for file announce"
```

---

## Task 11: Temporary dev connect bar

A throwaway UI to enter server/room/username and connect, so two instances can join a room before the Phase 4 connect screen exists. Clearly marked TEMP.

**Files:**
- Create: `lib/ui/dev_connect_bar.dart`

- [ ] **Step 1: Write the widget**

Content for `lib/ui/dev_connect_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../core/sync/peer_state.dart';
import '../core/sync/syncplay_constants.dart';

/// TEMPORARY dev-only connect bar. Replaced by the Phase 4 connect screen.
/// Lets a human type a room + username and connect to a public server so two
/// instances can be synced during development.
class DevConnectBar extends StatefulWidget {
  const DevConnectBar({
    required this.connectionStatus,
    required this.onConnect,
    super.key,
  });

  final SyncConnectionStatus connectionStatus;
  final void Function({
    required String server,
    required int port,
    required String username,
    required String room,
  }) onConnect;

  @override
  State<DevConnectBar> createState() => _DevConnectBarState();
}

class _DevConnectBarState extends State<DevConnectBar> {
  final _server = TextEditingController(text: SyncplayConstants.defaultServer);
  final _port = TextEditingController(text: '${SyncplayConstants.defaultPort}');
  final _room = TextEditingController(text: 'meow-dev-room');
  final _user = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    _room.dispose();
    _user.dispose();
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_port.text) ?? SyncplayConstants.defaultPort;
    widget.onConnect(
      server: _server.text.trim(),
      port: port,
      username: _user.text.trim().isEmpty ? 'dev' : _user.text.trim(),
      room: _room.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connecting =
        widget.connectionStatus == SyncConnectionStatus.connecting ||
            widget.connectionStatus == SyncConnectionStatus.handshaking;
    return Material(
      color: const Color(0xFF1A1410),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            _field(_user, 'username', 120),
            _field(_room, 'room', 160),
            _field(_server, 'server', 140),
            _field(_port, 'port', 70),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: connecting ? null : _submit,
              child: Text(connecting ? 'Connecting…' : 'Connect'),
            ),
            const SizedBox(width: 12),
            Text(
              widget.connectionStatus.name,
              style: const TextStyle(color: Color(0xFFD4A574)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, double width) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: width,
        child: TextField(
          controller: c,
          style: const TextStyle(color: Color(0xFFF5E6D3)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0x88F5E6D3)),
            isDense: true,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/ui/dev_connect_bar.dart
git commit -m "feat(ui): add temporary dev connect bar for sync testing"
```

---

## Task 12: Wire sync into `HomeScreen`

Own a `SyncplayClient` and a `PlaybackSyncBridge` alongside the existing `MediaKitVideoCore`. Show the dev connect bar, connect on submit, announce the loaded file, and start the bridge.

**Files:**
- Modify: `lib/ui/home_screen.dart`

- [ ] **Step 1: Replace `home_screen.dart`**

Content for `lib/ui/home_screen.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/sync/peer_state.dart';
import '../core/sync/playback_sync_bridge.dart';
import '../core/sync/syncplay_client.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'dev_connect_bar.dart';
import 'drop_target.dart';
import 'empty_state.dart';
import 'video_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MediaKitVideoCore _core;
  late final SyncplayClient _sync;
  late final PlaybackSyncBridge _bridge;

  SyncConnectionStatus _syncStatus = SyncConnectionStatus.disconnected;
  StreamSubscription<SyncConnectionState>? _connSub;

  @override
  void initState() {
    super.initState();
    _core = MediaKitVideoCore();
    _sync = SyncplayClient();
    _bridge = PlaybackSyncBridge(video: _core, sync: _sync)..start();
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) setState(() => _syncStatus = s.status);
    });
  }

  @override
  void dispose() {
    unawaited(_connSub?.cancel());
    unawaited(_bridge.dispose());
    unawaited(_sync.dispose());
    unawaited(_core.dispose());
    super.dispose();
  }

  Future<void> _loadAndPlay(String path) async {
    await _core.load(path);
    await _core.play();
    await _announceCurrentFile();
  }

  Future<void> _announceCurrentFile() async {
    final state = _core.state;
    final path = state.filePath;
    if (path == null) return;
    var size = 0;
    try {
      size = await File(path).length();
    } on FileSystemException {
      size = 0;
    }
    _sync.announceFile(
      name: state.fileName ?? path,
      size: size,
      duration: state.duration,
    );
  }

  Future<void> _browse() async {
    final typeGroup = XTypeGroup(
      label: 'Video',
      extensions: videoExtensions.toList(),
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _loadAndPlay(file.path);
    }
  }

  void _handleDropped(String path) {
    unawaited(_loadAndPlay(path));
  }

  void _connect({
    required String server,
    required int port,
    required String username,
    required String room,
  }) {
    unawaited(_sync.connect(
      server: server,
      port: port,
      username: username,
      room: room,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          DevConnectBar(
            connectionStatus: _syncStatus,
            onConnect: _connect,
          ),
          Expanded(
            child: VideoDropTarget(
              onFileDropped: _handleDropped,
              child: StreamBuilder<PlaybackState>(
                stream: _core.stateStream,
                initialData: _core.state,
                builder: (context, snapshot) {
                  final state = snapshot.data!;
                  if (state.fileName == null) {
                    return EmptyState(onBrowse: _browse);
                  }
                  return VideoSurface(core: _core);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run full unit suite**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/home_screen.dart
git commit -m "feat(ui): wire SyncplayClient + bridge into HomeScreen with dev connect"
```

---

## Task 13: Announce file on (re)connect

If the user loads a file before connecting, the file must still be announced once the handshake completes. Announce on the `connected` transition too.

**Files:**
- Modify: `lib/ui/home_screen.dart`

- [ ] **Step 1: Announce on connect in the connection listener**

In `lib/ui/home_screen.dart`, update the `_connSub` listener in `initState`:

```dart
    _connSub = _sync.connectionState.listen((s) {
      if (mounted) setState(() => _syncStatus = s.status);
      if (s.status == SyncConnectionStatus.connected) {
        unawaited(_announceCurrentFile());
      }
    });
```

- [ ] **Step 2: Run analyze**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/ui/home_screen.dart
git commit -m "feat(ui): announce loaded file once room handshake completes"
```

---

## Task 14: Manual end-to-end verification (two instances)

**Files:** none (verification only)

- [ ] **Step 1: Build the app**

Run: `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat build windows --debug`
Expected: `Built build\windows\x64\runner\Debug\meowwatch.exe`.

- [ ] **Step 2: Launch two instances**

In two terminals run the built exe twice (two windows):
```
"D:/Repos/MeowWatch/build/windows/x64/runner/Debug/meowwatch.exe"
```

- [ ] **Step 3: Connect both to the same room**

In each window's dev connect bar: server `syncplay.pl`, port `8999`, room `meow-dev-room`, usernames `a` and `b`. Click Connect. Status should reach `connected` in both.

- [ ] **Step 4: Load the same video in both**

Drop the same local video file into both windows.

- [ ] **Step 5: Verify sync**

- Pause in window A → window B pauses within ~1s.
- Play in window A → window B plays.
- Seek in window A (←/→ or scrubber) → window B jumps to match.
- Repeat driving from window B.

Expected: play/pause/seek propagate both directions without the two clients fighting (no rapid back-and-forth seeking).

- [ ] **Step 6: Verify disconnect**

Close window A. Window B's connection status should remain `connected` (server still up); no crash.

- [ ] **Step 7: If any step failed, note specifics in `docs/phase-2-issues.md`. Otherwise continue.**

- [ ] **Step 8: Tag the milestone**

```bash
git tag phase-2-complete -m "Phase 2: two instances sync play/pause/seek via Syncplay protocol"
```

---

## Phase 2 done

Two MeowWatch instances in the same room now mirror play/pause/seek through a public Syncplay server. No chat UI, no connect screen yet (dev bar is a throwaway). Next plan: Phase 3 — Chat overlay (glass card, drag-snap-collapse, text chat over the Syncplay chat channel), which will also replace presence/chat plumbing already exposed by `SyncCore`.
