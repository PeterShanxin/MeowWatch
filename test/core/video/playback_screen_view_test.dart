import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/playback_screen_view.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A core whose state can be driven directly, so the screen-view projection can
/// be exercised against arbitrary tick patterns (position churn vs real
/// transitions).
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

  group('VideoCore.screenViewStream', () {
    test('position-only ticks do not emit new screen views', () async {
      final views = <PlaybackScreenView>[];
      final sub = core.screenViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        fileName: 'demo.mkv',
        filePath: r'C:\videos\demo.mkv',
        duration: const Duration(minutes: 30),
      ));
      // The mpv position firehose: many ticks, nothing else changing.
      for (var i = 1; i <= 50; i++) {
        core.push(core.state.copyWith(position: Duration(milliseconds: i * 100)));
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 1);
      expect(views.single.fileName, 'demo.mkv');
      expect(views.single.status, PlaybackStatus.playing);
    });

    test('duration/volume-only changes also stay silent', () async {
      final views = <PlaybackScreenView>[];
      final sub = core.screenViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        fileName: 'demo.mkv',
      ));
      core.push(core.state.copyWith(duration: const Duration(minutes: 90)));
      core.push(core.state.copyWith(volume: 0.5));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 1);
    });

    test('status, file, and error transitions emit', () async {
      final views = <PlaybackScreenView>[];
      final sub = core.screenViewStream.listen(views.add);

      core.push(core.state.copyWith(
        status: PlaybackStatus.playing,
        fileName: 'a.mkv',
        filePath: r'C:\a.mkv',
      ));
      core.push(core.state.copyWith(status: PlaybackStatus.paused));
      core.push(core.state.copyWith(fileName: 'b.mkv', filePath: r'C:\b.mkv'));
      core.push(core.state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: 'boom',
      ));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(views.length, 4);
      expect(views[1].status, PlaybackStatus.paused);
      expect(views[2].fileName, 'b.mkv');
      expect(views[3].status, PlaybackStatus.error);
      expect(views[3].errorMessage, 'boom');
    });

    test('is a single cached stream object across accesses', () {
      // StreamBuilder resubscribes whenever it's handed a different stream
      // object, which would reset distinct()'s memory on every parent
      // setState and let the next position tick through as a "first" event.
      expect(core.screenViewStream, same(core.screenViewStream));
    });

    test('screenView getter mirrors the current state projection', () {
      core.push(core.state.copyWith(
        status: PlaybackStatus.paused,
        fileName: 'demo.mkv',
        filePath: r'C:\videos\demo.mkv',
        position: const Duration(seconds: 42),
      ));
      final view = core.screenView;
      expect(view.status, PlaybackStatus.paused);
      expect(view.fileName, 'demo.mkv');
      expect(view.filePath, r'C:\videos\demo.mkv');
      expect(view.errorMessage, isNull);
    });
  });

  group('PlaybackScreenView equality', () {
    test('equal projections compare equal regardless of position', () {
      final a = PlaybackScreenView.of(const PlaybackState(
        status: PlaybackStatus.playing,
        fileName: 'x.mkv',
        position: Duration(seconds: 1),
      ));
      final b = PlaybackScreenView.of(const PlaybackState(
        status: PlaybackStatus.playing,
        fileName: 'x.mkv',
        position: Duration(seconds: 99),
      ));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different coarse fields compare unequal', () {
      final a = PlaybackScreenView.of(
        const PlaybackState(status: PlaybackStatus.playing, fileName: 'x.mkv'),
      );
      final b = PlaybackScreenView.of(
        const PlaybackState(status: PlaybackStatus.paused, fileName: 'x.mkv'),
      );
      expect(a, isNot(b));
    });
  });
}
