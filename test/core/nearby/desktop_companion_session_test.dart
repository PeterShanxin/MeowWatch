import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/chat/chat_signals.dart';
import 'package:meowwatch/core/chat/chat_store.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/nearby/desktop_companion_session.dart';
import 'package:meowwatch/core/session/session_mode.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import '../../support/scripted_video_core.dart';

final class _FakeVideo extends VideoCore implements GuardedVideoControls {
  final calls = <Object>[];
  Completer<void>? playGate;

  void open(String source, {bool playing = false}) {
    emit(
      PlaybackState(
        status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 2),
        fileName: source,
        filePath: source,
        opened: true,
      ),
    );
  }

  @override
  Future<void> load(String filePath) async => open(filePath);

  @override
  Future<void> play() async {
    calls.add('play');
    await playGate?.future;
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add(position);
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> playChecked({required void Function() checkActive}) async {
    checkActive();
    await playGate?.future;
    checkActive();
    calls.add('play');
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pauseChecked({required void Function() checkActive}) async {
    checkActive();
    await pause();
    checkActive();
  }

  @override
  Future<void> seekChecked(
    Duration position, {
    required void Function() checkActive,
  }) async {
    checkActive();
    await playGate?.future;
    checkActive();
    await seek(position);
    checkActive();
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> disposeBackend() async {}
}

final class _FakeSync extends SyncCore {
  final sent = <String>[];

  void connectedAs(String username) => emitConnectionState(
    SyncConnectionState(
      status: SyncConnectionStatus.connected,
      username: username,
    ),
  );

  void incoming(ChatMessage message) => emitChat(message);

  void react(String username, String reaction) =>
      emitChat(ChatMessage(username: username, text: encodeReaction(reaction)));

  void pushPresence(String username, PresenceKind kind) =>
      emitPresence(PresenceEvent(username: username, kind: kind));

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {
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
  void sendChat(String text) => sent.add(text);

  @override
  Future<void> disposeBackend() async {}
}

final class _Fixture {
  _Fixture({this.mode = SessionMode.synced}) {
    sync.connectedAs(username);
    chat = ChatStore(
      sync: sync,
      initialUsername: username,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    session = DesktopCompanionSession(
      video: video,
      desktopId: desktopId,
      desktopName: 'Living Room PC',
      sessionEpoch: sessionEpoch,
      registeredGeneration: generation,
      currentMode: () => mode,
      currentRoom: () => room,
      currentUsername: () => username,
      acceptedSource: () => source,
      participants: () => peers,
      currentGeneration: () => generation,
      currentMediaGeneration: () => mediaGeneration,
      currentChat: () => mode.isSynced ? chat : null,
      currentSync: () => mode.isSynced ? sync : null,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  }

  static final desktopId = _id(1);
  static final sessionEpoch = _id(2);
  final video = _FakeVideo();
  final sync = _FakeSync();
  late final ChatStore chat;
  late final DesktopCompanionSession session;
  final room = const RoomConfig(
    server: 'sync.example.test',
    port: 8999,
    room: 'sleepy-otter-secret-room',
    username: 'meow',
    password: 'server-password-must-not-leak',
  );
  final peers = <String>{'lin', 'meow'};
  SessionMode mode;
  String username = 'meow';
  String? source;
  int generation = 4;
  int mediaGeneration = 0;

  NearbyCommand command(
    String method, [
    Map<String, Object?> args = const <String, Object?>{},
    void Function()? checkActive,
  ]) => NearbyCommand.forTesting(
    id: 'command-1',
    sessionEpoch: sessionEpoch,
    method: method,
    args: args,
    checkActive: checkActive ?? () {},
  );

  Future<void> dispose() async {
    await session.dispose();
    await chat.dispose();
    await sync.dispose();
    await video.dispose();
  }
}

String _id(int byte) =>
    base64UrlEncode(List<int>.filled(16, byte)).replaceAll('=', '');

Matcher _nearbyError(String code) =>
    isA<NearbyException>().having((error) => error.code, 'code', code);

void main() {
  test('snapshot uses the mobile schema and redacts desktop secrets', () async {
    final fixture = _Fixture();
    fixture.source = r'C:\Users\me\private-folder\movie.mkv';
    fixture.video.open(fixture.source!);

    final snapshot = fixture.session.snapshot;
    final encoded = jsonEncode(snapshot);
    expect(snapshot.keys, {
      'desktop',
      'session',
      'playback',
      'participants',
      'chat',
    });
    expect(snapshot['desktop'], {
      'id': _Fixture.desktopId,
      'name': 'Living Room PC',
      'protocolVersion': 1,
      'capabilities': [
        'playback.play',
        'playback.pause',
        'playback.seek',
        'chat.send',
        'chat.reaction',
        'chat.typing',
      ],
    });
    expect(snapshot['session'], {
      'epoch': _Fixture.sessionEpoch,
      'mode': 'synced',
      'username': 'meow',
      'connection': 'connected',
      'room': 'sleepy-otter-secret-room',
      'server': 'sync.example.test',
      'port': 8999,
    });
    expect(
      (snapshot['playback']! as Map<String, Object?>),
      allOf(
        containsPair('revision', greaterThanOrEqualTo(0)),
        containsPair('sampledAtUnixMs', 1700000000000),
      ),
    );
    expect(
      (snapshot['playback']! as Map<String, Object?>)['media'],
      allOf(containsPair('title', 'movie.mkv'), containsPair('kind', 'file')),
    );
    expect(encoded, isNot(contains(r'C:\Users\me')));
    expect(encoded, isNot(contains('private-folder')));
    expect(encoded, isNot(contains('server-password-must-not-leak')));

    fixture.source =
        'https://cdn.example.test/video.m3u8?token=top-secret-token';
    fixture.video.open(fixture.source!, playing: true);
    final remote = jsonEncode(fixture.session.snapshot);
    final playback =
        fixture.session.snapshot['playback']! as Map<String, Object?>;
    expect(
      playback['media'],
      allOf(
        containsPair('title', 'cdn.example.test'),
        containsPair('kind', 'url'),
      ),
    );
    expect(remote, isNot(contains('top-secret-token')));
    expect(remote, isNot(contains('video.m3u8')));
    await fixture.dispose();
  });

  test(
    'snapshot caps chat at newest 100 and keeps participant ownership',
    () async {
      final fixture = _Fixture();
      for (var index = 0; index < 105; index++) {
        fixture.sync.incoming(ChatMessage(username: 'lin', text: 'm$index'));
      }
      await Future<void>.delayed(Duration.zero);
      fixture.chat.addSystem('lin joined the room');
      await Future<void>.delayed(Duration.zero);

      final snapshot = fixture.session.snapshot;
      final chat = snapshot['chat']! as List<Object?>;
      expect(chat, hasLength(100));
      expect((chat.first! as Map<String, Object?>)['text'], 'm6');
      expect(
        chat.last! as Map<String, Object?>,
        allOf(
          containsPair('id', isA<String>()),
          containsPair('username', 'MeowWatch'),
          containsPair('text', 'lin joined the room'),
          containsPair('receivedAtUnixMs', 1700000000000),
          containsPair('system', true),
          containsPair('isMine', false),
        ),
      );
      expect(snapshot['participants'], [
        {'username': 'meow', 'isSelf': true},
        {'username': 'lin', 'isSelf': false},
      ]);
      await fixture.dispose();
    },
  );

  test(
    'publishes bounded social event bodies and coherent snapshots',
    () async {
      final fixture = _Fixture();
      final state = fixture.session.events.firstWhere(
        (event) => event.type == 'state.snapshot',
      );
      fixture.source = 'https://cdn.example.test/movie.mkv?token=must-not-leak';
      fixture.video.open(fixture.source!);
      final streamedState = (await state).body;
      expect(streamedState, fixture.session.snapshot);
      expect(jsonEncode(streamedState), isNot(contains('must-not-leak')));

      final message = fixture.session.events.firstWhere(
        (event) => event.type == 'chat.message',
      );
      fixture.sync.incoming(const ChatMessage(username: 'lin', text: 'hello'));
      final messageBody = (await message).body;
      expect(
        messageBody,
        allOf(
          containsPair('id', isA<String>()),
          containsPair('username', 'lin'),
          containsPair('text', 'hello'),
          containsPair('receivedAtUnixMs', 1700000000000),
          containsPair('system', false),
          containsPair('isMine', false),
        ),
      );
      expect(
        (fixture.session.snapshot['chat']! as List<Object?>).last,
        containsPair('id', messageBody['id']),
      );

      final reaction = fixture.session.events.firstWhere(
        (event) => event.type == 'chat.reaction',
      );
      fixture.sync.react('lin', '👏');
      expect((await reaction).body, {'username': 'lin', 'reaction': '👏'});

      final presence = fixture.session.events.firstWhere(
        (event) => event.type == 'presence',
      );
      fixture.sync.pushPresence('zoe', PresenceKind.joined);
      expect((await presence).body, {'username': 'zoe', 'kind': 'joined'});
      expect(fixture.session.stateRevision, greaterThan(0));
      await fixture.dispose();
    },
  );

  test('local snapshot omits synced room details and social state', () async {
    final fixture = _Fixture(mode: SessionMode.local);
    fixture.source = 'movie.mkv';
    fixture.video.open(fixture.source!);

    final snapshot = fixture.session.snapshot;
    expect(snapshot['session'], {
      'epoch': _Fixture.sessionEpoch,
      'mode': 'local',
      'username': 'meow',
      'connection': 'disconnected',
    });
    expect(snapshot['chat'], isEmpty);
    expect(jsonEncode(snapshot), isNot(contains(fixture.room.password!)));
    await fixture.dispose();
  });

  test(
    'large hostile room state remains inside the wire frame limit',
    () async {
      final fixture = _Fixture();
      fixture.peers.addAll(
        List<String>.generate(300, (index) => 'peer-$index-${'界' * 140}'),
      );
      for (var index = 0; index < 100; index++) {
        fixture.sync.incoming(
          ChatMessage(username: 'peer-$index', text: '🐱' * 150),
        );
      }
      await Future<void>.delayed(Duration.zero);

      final snapshot = fixture.session.snapshot;
      final encoded = const NearbyFrameCodec().encode(
        NearbyFrame({
          'v': 1,
          'type': 'state.snapshot',
          'seq': 1,
          'sessionEpoch': _Fixture.sessionEpoch,
          'state': snapshot,
        }),
      );
      expect(encoded.length, lessThanOrEqualTo(maxFrameBytes));
      expect(snapshot['chat']! as List<Object?>, isNotEmpty);
      expect(
        (snapshot['chat']! as List<Object?>).length,
        lessThanOrEqualTo(100),
      );
      expect(
        (snapshot['participants']! as List<Object?>).length,
        lessThanOrEqualTo(256),
      );
      await fixture.dispose();
    },
  );

  test('play pause seek and chat use the existing session objects', () async {
    final fixture = _Fixture();
    fixture.source = 'movie.mkv';
    fixture.video.open(fixture.source!);
    var activeChecks = 0;
    void active() => activeChecks++;

    await fixture.session.handle(
      fixture.command('playback.play', const {}, active),
    );
    await fixture.session.handle(
      fixture.command('playback.pause', const {}, active),
    );
    await fixture.session.handle(
      fixture.command('playback.seek', {'positionMs': 999999}, active),
    );
    await fixture.session.handle(
      fixture.command('chat.send', {'text': '  hello  '}, active),
    );
    await fixture.session.handle(
      fixture.command('chat.reaction', {'reaction': '👍'}, active),
    );
    await fixture.session.handle(
      fixture.command('chat.typing', {'typing': true}, active),
    );

    expect(fixture.video.calls, ['play', 'pause', const Duration(minutes: 2)]);
    expect(fixture.sync.sent, [
      'hello',
      encodeReaction('👍'),
      encodeTyping(true),
    ]);
    expect(activeChecks, greaterThanOrEqualTo(18));
    await fixture.dispose();
  });

  test('rejects stale generation after an awaited native action', () async {
    final fixture = _Fixture();
    fixture.source = 'movie.mkv';
    fixture.video.open(fixture.source!);
    final gate = fixture.video.playGate = Completer<void>();

    final command = fixture.session.handle(fixture.command('playback.play'));
    await Future<void>.delayed(Duration.zero);
    fixture.generation++;
    gate.complete();

    await expectLater(command, throwsA(_nearbyError('session_changed')));
    expect(fixture.video.calls, isEmpty);
    await fixture.dispose();
  });

  for (final method in ['playback.play', 'playback.seek']) {
    for (final change in [
      'media reload',
      'source replacement',
      'lease revoked',
    ]) {
      test('$method does not dispatch after $change during recovery', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        fixture.source = 'same-source.mkv';
        fixture.video.open(fixture.source!);
        final gate = fixture.video.playGate = Completer<void>();
        var active = true;
        final outcome = expectLater(
          fixture.session.handle(
            fixture.command(
              method,
              method == 'playback.seek' ? {'positionMs': 3000} : const {},
              () {
                if (!active) throw const NearbyException('not_connected');
              },
            ),
          ),
          throwsA(
            _nearbyError(
              change == 'lease revoked' ? 'not_connected' : 'session_changed',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        switch (change) {
          case 'media reload':
            fixture.mediaGeneration++;
          case 'source replacement':
            fixture.source = 'new-source.mkv';
          case 'lease revoked':
            active = false;
        }
        gate.complete();
        await outcome;
        expect(fixture.video.calls, isEmpty);
        expect(fixture.video.state.status, PlaybackStatus.paused);
        expect(fixture.video.state.position, const Duration(seconds: 12));
      });
    }
  }

  test(
    'fails closed for absent media, disconnected chat, and bad commands',
    () async {
      final fixture = _Fixture();
      await expectLater(
        fixture.session.handle(fixture.command('playback.play')),
        throwsA(_nearbyError('no_media')),
      );
      await fixture.sync.disconnect();
      await expectLater(
        fixture.session.handle(fixture.command('chat.send', {'text': 'hello'})),
        throwsA(_nearbyError('not_connected')),
      );
      await expectLater(
        fixture.session.handle(
          fixture.command('chat.reaction', {'reaction': 'arbitrary'}),
        ),
        throwsA(_nearbyError('invalid_argument')),
      );
      await expectLater(
        fixture.session.handle(fixture.command('session.prepare')),
        throwsA(_nearbyError('unsupported_command')),
      );
      await fixture.dispose();
    },
  );

  test('rejects a command from a different authority epoch', () async {
    final fixture = _Fixture();
    final command = NearbyCommand.forTesting(
      id: 'old-command',
      sessionEpoch: _id(9),
      method: 'playback.play',
      args: const {},
      checkActive: () {},
    );
    await expectLater(
      fixture.session.handle(command),
      throwsA(_nearbyError('session_changed')),
    );
    await fixture.dispose();
  });

  test(
    'backend without guarded dispatch never receives nearby controls',
    () async {
      final video = ScriptedVideoCore()..openAt('movie.mkv');
      final session = DesktopCompanionSession(
        video: video,
        desktopId: _Fixture.desktopId,
        desktopName: 'Desktop',
        sessionEpoch: _Fixture.sessionEpoch,
        registeredGeneration: 1,
        currentMode: () => SessionMode.local,
        currentRoom: () => const RoomConfig(
          server: 'sync.example.test',
          port: 8997,
          room: 'Room',
          username: 'Cat',
        ),
        currentUsername: () => 'Cat',
        acceptedSource: () => 'movie.mkv',
        participants: () => const [],
        currentGeneration: () => 1,
        currentMediaGeneration: () => 1,
        currentChat: () => null,
        currentSync: () => null,
      );
      addTearDown(video.dispose);
      addTearDown(session.dispose);
      await expectLater(
        session.handle(
          NearbyCommand.forTesting(
            id: 'command',
            sessionEpoch: _Fixture.sessionEpoch,
            method: 'playback.play',
            args: const {},
            checkActive: () {},
          ),
        ),
        throwsA(_nearbyError('unsupported_command')),
      );
      expect(video.commands, isEmpty);
    },
  );
}
