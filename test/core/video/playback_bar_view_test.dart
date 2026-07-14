import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_bar_view.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A core whose state can be driven directly, so the bar-view projection can
/// be exercised against arbitrary tick patterns (sub-second position churn vs
/// changes the bar actually displays).
class TickingVideoCore extends VideoCore {
  void push(PlaybackState next) => emit(next);

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
  late TickingVideoCore core;

  setUp(() {
    core = TickingVideoCore();
  });

  tearDown(() async {
    await core.dispose();
  });

  group('VideoCore.barViewStream', () {
    test('sub-second position ticks do not emit new bar views', () async {
      final views = <PlaybackBarView>[];
      final sub = core.barViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        fileName: 'demo.mkv',
        duration: const Duration(minutes: 30),
        position: const Duration(seconds: 5),
      ));
      // The mpv position firehose inside one displayed second: the MM:SS label
      // and the slider's visible fraction don't change, so nothing may emit.
      for (var ms = 5050; ms < 6000; ms += 50) {
        core.push(core.state.copyWith(position: Duration(milliseconds: ms)));
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 1);
      expect(views.single.positionSeconds, 5);
    });

    test('crossing a second boundary emits exactly one new view', () async {
      final views = <PlaybackBarView>[];
      final sub = core.barViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        duration: const Duration(minutes: 30),
        position: const Duration(milliseconds: 5900),
      ));
      core.push(core.state.copyWith(
        position: const Duration(milliseconds: 6001),
      ));
      core.push(core.state.copyWith(
        position: const Duration(milliseconds: 6500),
      ));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 2);
      expect(views.last.positionSeconds, 6);
    });

    test('status, duration, and volume changes emit', () async {
      final views = <PlaybackBarView>[];
      final sub = core.barViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        duration: const Duration(minutes: 30),
      ));
      core.push(core.state.copyWith(status: PlaybackStatus.paused));
      core.push(core.state.copyWith(duration: const Duration(minutes: 90)));
      core.push(core.state.copyWith(volume: 0.5));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 4);
      expect(views[1].status, PlaybackStatus.paused);
      expect(views[2].duration, const Duration(minutes: 90));
      expect(views[3].volume, 0.5);
    });

    test('fileName/error churn the bar does not display stays silent',
        () async {
      final views = <PlaybackBarView>[];
      final sub = core.barViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        fileName: 'a.mkv',
      ));
      core.push(core.state.copyWith(fileName: 'b.mkv', filePath: r'C:\b.mkv'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 1);
    });

    test('is a single cached stream object across accesses', () {
      // StreamBuilder resubscribes when handed a different stream object,
      // which would reset distinct()'s memory on every parent rebuild and let
      // the next raw tick through as a "first" event.
      expect(core.barViewStream, same(core.barViewStream));
    });

    test('barView getter mirrors the current state projection', () {
      core.push(core.state.copyWith(
        status: PlaybackStatus.paused,
        position: const Duration(milliseconds: 42750),
        duration: const Duration(minutes: 2),
        volume: 0.8,
      ));
      final view = core.barView;
      expect(view.status, PlaybackStatus.paused);
      expect(view.positionSeconds, 42);
      expect(view.duration, const Duration(minutes: 2));
      expect(view.volume, 0.8);
    });
  });

  group('PlaybackBarView', () {
    test('position getter rebuilds a whole-second Duration', () {
      final view = PlaybackBarView.of(const PlaybackState(
        position: Duration(milliseconds: 12999),
      ));
      expect(view.position, const Duration(seconds: 12));
    });

    test('equal projections compare equal within the same second', () {
      final a = PlaybackBarView.of(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 7100),
        duration: Duration(minutes: 10),
        volume: 1.0,
      ));
      final b = PlaybackBarView.of(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 7900),
        duration: Duration(minutes: 10),
        volume: 1.0,
      ));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different displayed fields compare unequal', () {
      const base = PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 7),
        duration: Duration(minutes: 10),
        volume: 1.0,
      );
      final a = PlaybackBarView.of(base);
      expect(
        PlaybackBarView.of(base.copyWith(status: PlaybackStatus.paused)),
        isNot(a),
      );
      expect(
        PlaybackBarView.of(
          base.copyWith(position: const Duration(seconds: 8)),
        ),
        isNot(a),
      );
      expect(
        PlaybackBarView.of(
          base.copyWith(duration: const Duration(minutes: 11)),
        ),
        isNot(a),
      );
      expect(PlaybackBarView.of(base.copyWith(volume: 0.5)), isNot(a));
    });
  });
}
