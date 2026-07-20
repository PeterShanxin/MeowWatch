import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/resolved_media.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// Records every [load] call so the base-class [VideoCore.loadResolved]
/// default (delegate to `load(media.pageUrl)`) can be asserted.
class RecordingVideoCore extends VideoCore {
  final List<String> loadedSources = [];

  @override
  Future<void> load(String filePath) async {
    loadedSources.add(filePath);
    emit(state.copyWith(
      fileName: filePath,
      filePath: filePath,
      status: PlaybackStatus.paused,
      duration: const Duration(minutes: 30),
    ));
  }

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
  late RecordingVideoCore core;

  setUp(() {
    core = RecordingVideoCore();
  });

  tearDown(() async {
    await core.dispose();
  });

  test('default loadResolved delegates to load(pageUrl)', () async {
    const media = ResolvedMedia(
      pageUrl: 'https://www.youtube.com/watch?v=abc123',
      videoUrl: 'https://cdn.example/video.m4s?token=secret',
      audioUrl: 'https://cdn.example/audio.m4s?token=secret',
      httpHeaders: {'Referer': 'https://www.youtube.com/'},
    );
    await core.loadResolved(media);
    expect(core.loadedSources, ['https://www.youtube.com/watch?v=abc123']);
  });

  test('default loadResolved never hands the resolved stream URL to load',
      () async {
    const media = ResolvedMedia(
      pageUrl: 'https://www.bilibili.com/video/BV1',
      videoUrl: 'https://upos.example/stream.m4s',
    );
    await core.loadResolved(media);
    expect(
      core.loadedSources.any((s) => s.contains('upos.example')),
      isFalse,
    );
    expect(core.state.fileName, 'https://www.bilibili.com/video/BV1');
  });
}
