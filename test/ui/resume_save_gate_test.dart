import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/resume_save_gate.dart';

/// Pure logic for coordinating HomeScreen's periodic resume-position saves
/// (#206): serialize writes (never two in flight at once) and skip a write
/// whose (file, position, duration) exactly match the last one that
/// succeeded, so a paused room doesn't hammer SQLite with identical values
/// every tick. `force` (leave/dispose) bypasses both checks.
void main() {
  group('ResumeSaveGate', () {
    test('unchanged paused state does not write a second time', () async {
      final gate = ResumeSaveGate();
      var writes = 0;
      Future<void> attempt() => gate.attempt(
        filePath: '/movie.mp4',
        positionMs: 1000,
        durationMs: 60000,
        write: () async {
          writes++;
          return true;
        },
      );

      await attempt();
      await attempt(); // identical snapshot — should be skipped

      expect(writes, 1);
    });

    test('a position change writes again', () async {
      final gate = ResumeSaveGate();
      var writes = 0;
      Future<void> attempt(int positionMs) => gate.attempt(
        filePath: '/movie.mp4',
        positionMs: positionMs,
        durationMs: 60000,
        write: () async {
          writes++;
          return true;
        },
      );

      await attempt(1000);
      await attempt(2000);

      expect(writes, 2);
    });

    test('a source change writes again even with the same position', () async {
      final gate = ResumeSaveGate();
      var writes = 0;
      Future<void> attempt(String filePath) => gate.attempt(
        filePath: filePath,
        positionMs: 1000,
        durationMs: 60000,
        write: () async {
          writes++;
          return true;
        },
      );

      await attempt('/movie-a.mp4');
      await attempt('/movie-b.mp4');

      expect(writes, 2);
    });

    test(
      'a slow in-flight save blocks the next tick from overlapping it',
      () async {
        final gate = ResumeSaveGate();
        var writes = 0;
        final firstWriteStarted = Completer<void>();
        final releaseFirstWrite = Completer<void>();

        final first = gate.attempt(
          filePath: '/movie.mp4',
          positionMs: 1000,
          durationMs: 60000,
          write: () async {
            writes++;
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
            return true;
          },
        );

        await firstWriteStarted.future;
        expect(gate.isSaving, isTrue);

        // A second tick lands while the first write is still in flight — even
        // with a different position, it must be a no-op, not a second
        // overlapping write.
        await gate.attempt(
          filePath: '/movie.mp4',
          positionMs: 2000,
          durationMs: 60000,
          write: () async {
          writes++;
          return true;
        },
        );
        expect(writes, 1);

        releaseFirstWrite.complete();
        await first;
        expect(gate.isSaving, isFalse);

        // Now that the first write finished, a genuinely new tick can save.
        await gate.attempt(
          filePath: '/movie.mp4',
          positionMs: 2000,
          durationMs: 60000,
          write: () async {
          writes++;
          return true;
        },
        );
        expect(writes, 2);
      },
    );

    test('force bypasses the unchanged-skip so a final save always writes', () async {
      final gate = ResumeSaveGate();
      var writes = 0;
      Future<void> attempt({bool force = false}) => gate.attempt(
        filePath: '/movie.mp4',
        positionMs: 1000,
        durationMs: 60000,
        force: force,
        write: () async {
          writes++;
          return true;
        },
      );

      await attempt();
      await attempt(force: true); // identical snapshot, but forced

      expect(writes, 2);
    });

    test(
      'a write that hit no row (recordOpen still in flight) is not treated '
      'as saved (#208 review)',
      () async {
        final gate = ResumeSaveGate();
        var rowExists = false;
        var realWrites = 0;
        Future<void> attempt() => gate.attempt(
          filePath: '/movie.mp4',
          positionMs: 1000,
          durationMs: 60000,
          write: () async {
            // Mirrors DriftHistoryStore.updatePosition: silently no-ops
            // (returns false) until _recordOpen has inserted the row.
            if (!rowExists) return false;
            realWrites++;
            return true;
          },
        );

        await attempt(); // row missing — must NOT become the saved baseline
        rowExists = true;
        await attempt(); // identical snapshot, but nothing was persisted yet
        expect(realWrites, 1, reason: 'retry must backfill once the row exists');
        await attempt(); // now genuinely saved — skipped
        expect(realWrites, 1);
      },
    );

    test(
      'a throwing write still resets the single-flight guard (finally, not '
      'best-effort)',
      () async {
        final gate = ResumeSaveGate();

        await expectLater(
          gate.attempt(
            filePath: '/movie.mp4',
            positionMs: 1000,
            durationMs: 60000,
            write: () async => throw StateError('db exploded'),
          ),
          throwsStateError,
        );

        // The guard must not be left stuck true by the throwing path — a
        // subsequent attempt must be free to run.
        expect(gate.isSaving, isFalse);
        var writes = 0;
        await gate.attempt(
          filePath: '/movie.mp4',
          positionMs: 1000,
          durationMs: 60000,
          write: () async {
          writes++;
          return true;
        },
        );
        expect(writes, 1);
      },
    );
  });
}
