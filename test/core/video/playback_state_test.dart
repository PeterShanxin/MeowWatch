import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_state.dart';

void main() {
  group('PlaybackState', () {
    test('defaults to idle, position zero, duration zero', () {
      const state = PlaybackState();
      expect(state.status, PlaybackStatus.idle);
      expect(state.position, Duration.zero);
      expect(state.duration, Duration.zero);
      expect(state.volume, 1.0);
      expect(state.fileName, isNull);
    });

    test('copyWith updates only specified fields', () {
      const initial = PlaybackState();
      final updated = initial.copyWith(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 5),
      );
      expect(updated.status, PlaybackStatus.playing);
      expect(updated.position, const Duration(seconds: 5));
      expect(updated.duration, Duration.zero);
      expect(updated.volume, 1.0);
    });

    test('equal states are equal', () {
      const a = PlaybackState(status: PlaybackStatus.playing);
      const b = PlaybackState(status: PlaybackStatus.playing);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('states with differing fields are not equal', () {
      const a = PlaybackState(status: PlaybackStatus.playing);
      const b = PlaybackState(status: PlaybackStatus.paused);
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('copyWith can explicitly clear nullable fields', () {
      const initial = PlaybackState(
        fileName: 'movie.mkv',
        errorMessage: 'boom',
      );
      final cleared = initial.copyWith(fileName: null, errorMessage: null);
      expect(cleared.fileName, isNull);
      expect(cleared.errorMessage, isNull);
    });

    test('copyWith leaves nullable fields untouched when omitted', () {
      const initial = PlaybackState(
        fileName: 'movie.mkv',
        errorMessage: 'boom',
      );
      final updated = initial.copyWith(status: PlaybackStatus.playing);
      expect(updated.fileName, 'movie.mkv');
      expect(updated.errorMessage, 'boom');
    });
  });
}
