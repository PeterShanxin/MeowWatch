import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/watch_context.dart';

void main() {
  group('WatchContext', () {
    test('local key is the local sentinel', () {
      expect(const WatchContext.local().key, kLocalWatchContextKey);
      expect(const WatchContext.local().storedRoom, isNull);
      expect(const WatchContext.local().storedServer, isNull);
      expect(const WatchContext.local().storedPort, isNull);
    });

    test('synced key includes server, port, and trimmed room', () {
      final ctx = WatchContext.synced(
        server: ' syncplay.pl ',
        port: 8999,
        room: ' cozy-fox-42 ',
      );
      expect(ctx.key, 'synced|syncplay.pl|8999|cozy-fox-42');
      expect(ctx.storedRoom, 'cozy-fox-42');
      expect(ctx.storedServer, 'syncplay.pl');
      expect(ctx.storedPort, 8999);
    });

    test('same room on two servers are distinct', () {
      final a = WatchContext.synced(
        server: 'syncplay.pl',
        port: 8999,
        room: 'movie',
      );
      final b = WatchContext.synced(
        server: 'other.example',
        port: 8999,
        room: 'movie',
      );
      expect(a.key, isNot(b.key));
    });
  });

  group('migrateHistoryContextKey', () {
    test('roomless row becomes local', () {
      expect(migrateHistoryContextKey(), kLocalWatchContextKey);
      expect(migrateHistoryContextKey(room: ''), kLocalWatchContextKey);
      expect(migrateHistoryContextKey(room: '   '), kLocalWatchContextKey);
    });

    test('row with a room becomes synced, even without endpoint', () {
      expect(
        migrateHistoryContextKey(room: 'bouncy-snail'),
        'synced||0|bouncy-snail',
      );
    });

    test('watchContextForSession is local or this room endpoint', () {
      expect(
        watchContextForSession(
          local: true,
          server: 'syncplay.pl',
          port: 8999,
          room: 'cozy',
        ),
        const WatchContext.local(),
      );
      expect(
        watchContextForSession(
          local: false,
          server: 'syncplay.pl',
          port: 8999,
          room: 'cozy',
        ).key,
        'synced|syncplay.pl|8999|cozy',
      );
    });

    test('row with room + endpoint keeps that endpoint', () {
      expect(
        migrateHistoryContextKey(
          room: 'bouncy-snail',
          server: 'syncplay.pl',
          port: 8999,
        ),
        'synced|syncplay.pl|8999|bouncy-snail',
      );
    });
  });
}
