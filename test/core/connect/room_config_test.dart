import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/session/session_mode.dart';

void main() {
  const base = RoomConfig(
    server: 'syncplay.pl',
    port: 8999,
    room: 'cozy-fox-42',
    username: 'lin',
  );

  test('value equality', () {
    expect(
      base,
      const RoomConfig(
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'lin',
      ),
    );
  });

  test('defaults: no password, no resume, synced session', () {
    expect(base.password, isNull);
    expect(base.resumeFilePath, isNull);
    expect(base.resumePositionMs, 0);
    expect(base.sessionMode, SessionMode.synced);
    expect(base.endpointPolicy, SyncplayEndpointPolicy.pinned);
    expect(base.copyShareCode, isFalse);
    expect(base.persistUsername, isNull);
    expect(base.persistAsUsername, 'lin');
    expect(base.persistEndpointPinned, isTrue);
  });

  test('RoomConfig.local keeps a real room identity for later sync', () {
    final local = RoomConfig.local(
      username: 'lin',
      server: 'syncplay.pl',
      port: 8999,
      room: 'sleepy-otter-counts-cozy-stars',
      resumeFilePath: 'D:/v.mkv',
      resumePositionMs: 1200,
    );
    expect(local.sessionMode, SessionMode.local);
    expect(local.room, 'sleepy-otter-counts-cozy-stars');
    expect(local.server, 'syncplay.pl');
    expect(local.port, 8999);
    expect(local.username, 'lin');
    expect(local.resumeFilePath, 'D:/v.mkv');
    expect(local.resumePositionMs, 1200);
    expect(local.endpointPolicy, SyncplayEndpointPolicy.pinned);
    expect(local.persistEndpointPinned, isTrue);
    expect(
      RoomConfig.local(
        username: 'lin',
        server: 'syncplay.pl',
        port: 8995,
        room: 'happy-otter-99',
        endpointPinned: false,
      ).endpointPolicy,
      SyncplayEndpointPolicy.discoverFromRoom,
    );
  });

  test('copyWith overrides only named fields', () {
    final withResume = base.copyWith(
      resumeFilePath: 'D:/v.mkv',
      resumePositionMs: 5000,
    );
    expect(withResume.resumeFilePath, 'D:/v.mkv');
    expect(withResume.resumePositionMs, 5000);
    expect(withResume.room, base.room);
  });
}
