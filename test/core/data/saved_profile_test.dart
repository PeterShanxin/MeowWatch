import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/saved_profile.dart';

void main() {
  final used = DateTime(2026, 5, 29, 13);
  final base = SavedProfile(
    id: 1,
    name: 'cozy-fox-42',
    server: 'syncplay.pl',
    port: 8999,
    room: 'cozy-fox-42',
    username: 'lin',
    password: null,
    lastUsedAt: used,
  );

  test('value equality', () {
    expect(
      base,
      SavedProfile(
        id: 1,
        name: 'cozy-fox-42',
        server: 'syncplay.pl',
        port: 8999,
        room: 'cozy-fox-42',
        username: 'lin',
        password: null,
        lastUsedAt: used,
      ),
    );
  });

  test('copyWith updates lastUsedAt', () {
    final later = DateTime(2026, 6, 1);
    expect(base.copyWith(lastUsedAt: later).lastUsedAt, later);
    expect(base.copyWith(lastUsedAt: later).room, base.room);
  });
}
