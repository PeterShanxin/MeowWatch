import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/connect/room_config.dart';

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

  test('defaults: no password, no resume', () {
    expect(base.password, isNull);
    expect(base.resumeFilePath, isNull);
    expect(base.resumePositionMs, 0);
  });

  test('copyWith overrides only named fields', () {
    final withResume =
        base.copyWith(resumeFilePath: 'D:/v.mkv', resumePositionMs: 5000);
    expect(withResume.resumeFilePath, 'D:/v.mkv');
    expect(withResume.resumePositionMs, 5000);
    expect(withResume.room, base.room);
  });
}
