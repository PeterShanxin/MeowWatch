import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/session/session_mode.dart';
import 'package:meowwatch/core/session/session_services.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';
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
  test('local session holds no sync, bridge, or chat', () {
    final session = SessionServices.local();
    expect(session.mode, SessionMode.local);
    expect(session.sync, isNull);
    expect(session.bridge, isNull);
    expect(session.chat, isNull);
    expect(session.isSynced, isFalse);
  });

  test('forMode local never constructs multiplayer hosts', () {
    final session = SessionServices.forMode(
      mode: SessionMode.local,
      video: _FakeVideoCore(),
    );
    expect(session.sync, isNull);
    expect(session.bridge, isNull);
    expect(session.chat, isNull);
  });

  test('startSynced reuses a lobby-joined client', () async {
    final existing = SyncplayClient();
    final session = SessionServices.local();
    session.startSynced(video: _FakeVideoCore(), client: existing);
    expect(identical(session.sync, existing), isTrue);
    await session.dispose();
  });

  test('startSynced then stopToLocal tears the trio down', () async {
    final session = SessionServices.local();
    session.startSynced(video: _FakeVideoCore());
    expect(session.mode, SessionMode.synced);
    expect(session.sync, isNotNull);
    expect(session.bridge, isNotNull);
    expect(session.chat, isNotNull);

    await session.stopToLocal();
    expect(session.mode, SessionMode.local);
    expect(session.sync, isNull);
    expect(session.bridge, isNull);
    expect(session.chat, isNull);
  });

  test('repeated start/stop does not leave hosts behind', () async {
    final session = SessionServices.local();
    final video = _FakeVideoCore();
    for (var i = 0; i < 3; i++) {
      session.startSynced(video: video);
      expect(session.sync, isNotNull);
      await session.stopToLocal();
      expect(session.sync, isNull);
    }
  });

  test('synced session owns the live trio', () async {
    final session = SessionServices.synced(video: _FakeVideoCore());
    expect(session.mode, SessionMode.synced);
    expect(session.sync, isNotNull);
    expect(session.bridge, isNotNull);
    expect(session.chat, isNotNull);
    await session.dispose();
  });
}
