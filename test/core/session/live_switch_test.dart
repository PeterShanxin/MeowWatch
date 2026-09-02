import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/data/watch_context.dart';
import 'package:meowwatch/core/session/session_mode.dart';
import 'package:meowwatch/core/session/session_services.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> disposeBackend() async {}
}

void main() {
  const identity = (
    server: 'syncplay.pl',
    port: 8999,
    room: 'sleepy-otter-counts-cozy-stars',
  );

  test('A. Local Start keeps a real room identity and no sync hosts', () {
    final config = RoomConfig.local(
      username: 'lin',
      server: identity.server,
      port: identity.port,
      room: identity.room,
    );
    final session = SessionServices.local();
    expect(config.sessionMode, SessionMode.local);
    expect(config.room, identity.room);
    expect(session.sync, isNull);
    expect(session.bridge, isNull);
    expect(session.chat, isNull);
    expect(SessionChrome.forMode(config.sessionMode).chat, isFalse);
  });

  test('B. Local ON → OFF keeps the same room and starts the trio', () {
    final config = RoomConfig.local(
      username: 'lin',
      server: identity.server,
      port: identity.port,
      room: identity.room,
    );
    final session = SessionServices.local();
    session.startSynced(video: _FakeVideoCore());
    expect(session.mode, SessionMode.synced);
    expect(session.sync, isNotNull);
    expect(config.room, identity.room);
    expect(SessionChrome.forMode(session.mode).chat, isTrue);
  });

  test('C. Local OFF → ON keeps the same room and drops the trio', () async {
    final session = SessionServices.synced(video: _FakeVideoCore());
    await session.stopToLocal();
    expect(session.mode, SessionMode.local);
    expect(session.sync, isNull);
    expect(session.bridge, isNull);
    expect(session.chat, isNull);
    expect(SessionChrome.forMode(session.mode).syncBanners, isFalse);
  });

  test('D. repeated Local ↔ synced does not leave hosts behind', () async {
    final session = SessionServices.local();
    final video = _FakeVideoCore();
    for (var i = 0; i < 4; i++) {
      session.startSynced(video: video);
      expect(session.sync, isNotNull);
      await session.stopToLocal();
      expect(session.sync, isNull);
    }
  });

  test('history key stays with the room across effective-mode flips', () {
    final local = watchContextForSession(
      local: true,
      server: identity.server,
      port: identity.port,
      room: identity.room,
    );
    expect(local.isLocal, isTrue);
    expect(local.storedServer, identity.server);
    expect(local.storedPort, identity.port);
    expect(local.storedRoom, identity.room);
    final synced = watchContextForSession(
      local: false,
      server: identity.server,
      port: identity.port,
      room: identity.room,
    );
    expect(synced.isSynced, isTrue);
    expect(local.key, synced.key);
    expect(local.key, 'synced|syncplay.pl|8999|sleepy-otter-counts-cozy-stars');
  });
}
