// Two-client integration repro against the live server. Builds two full
// client+bridge stacks with ticking fake players in the same room, has A press
// play, and logs all protocol traffic + follow decisions so we can see why the
// clients fight. Run:
//   <flutter>/bin/flutter test tool/sync_two_client.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// Fake player that advances position in real time while playing, like libmpv.
class TickingVideoCore extends VideoCore {
  Timer? _timer;

  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(
      fileName: filePath,
      filePath: filePath,
      status: PlaybackStatus.paused,
      duration: const Duration(minutes: 42),
    ));
  }

  // Mimic libmpv: state changes land asynchronously, not synchronously.
  @override
  Future<void> play() async {
    if (state.status == PlaybackStatus.playing) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    emit(state.copyWith(status: PlaybackStatus.playing));
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (state.status == PlaybackStatus.playing) {
        emit(state.copyWith(
            position: state.position + const Duration(milliseconds: 250)));
      }
    });
  }

  @override
  Future<void> pause() async {
    if (state.status == PlaybackStatus.paused) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {
    _timer?.cancel();
  }
}

void main() {
  test('two clients in a room — observe sync behaviour', () async {
    final logs = <String>[];
    void log(String who, String line) {
      logs.add('$who $line');
    }

    final videoA = TickingVideoCore();
    final videoB = TickingVideoCore();
    final syncA = SyncplayClient(onLog: (l) => log('A:', l));
    final syncB = SyncplayClient(onLog: (l) => log('B:', l));
    final bridgeA = PlaybackSyncBridge(video: videoA, sync: syncA)..start();
    final bridgeB = PlaybackSyncBridge(video: videoB, sync: syncB)..start();

    videoA.stateStream.listen((s) =>
        log('A.video', 'pos=${s.position.inMilliseconds / 1000}s ${s.status.name}'));
    videoB.stateStream.listen((s) =>
        log('B.video', 'pos=${s.position.inMilliseconds / 1000}s ${s.status.name}'));

    const room = 'meow-twoclient-test';
    await syncA.connect(
        server: 'syncplay.pl', port: 8999, username: 'A', room: room);
    await syncB.connect(
        server: 'syncplay.pl', port: 8999, username: 'B', room: room);

    await Future<void>.delayed(const Duration(seconds: 3));
    await videoA.load('movie.mkv');
    await videoB.load('movie.mkv');
    syncA.announceFile(
        name: 'movie.mkv', size: 1000, duration: const Duration(minutes: 42));
    syncB.announceFile(
        name: 'movie.mkv', size: 1000, duration: const Duration(minutes: 42));

    await Future<void>.delayed(const Duration(seconds: 2));
    log('TEST', '--- A presses play ---');
    await videoA.play();

    await Future<void>.delayed(const Duration(seconds: 4));
    log('TEST', '--- B presses pause ---');
    await videoB.pause();

    await Future<void>.delayed(const Duration(seconds: 3));
    log('TEST',
        '--- after B pause: A=${videoA.state.position.inMilliseconds / 1000}s '
        '${videoA.state.status.name}, B=${videoB.state.position.inMilliseconds / 1000}s '
        '${videoB.state.status.name} ---');

    log('TEST', '--- B seeks to 100s ---');
    await videoB.seek(const Duration(seconds: 100));

    await Future<void>.delayed(const Duration(seconds: 3));
    log('TEST', '--- final: A=${videoA.state.position.inMilliseconds / 1000}s '
        '${videoA.state.status.name}, B=${videoB.state.position.inMilliseconds / 1000}s '
        '${videoB.state.status.name} ---');

    await bridgeA.dispose();
    await bridgeB.dispose();
    await syncA.dispose();
    await syncB.dispose();
    await videoA.dispose();
    await videoB.dispose();

    // ignore: avoid_print
    print(logs.join('\n'));
  }, timeout: const Timeout(Duration(seconds: 40)));
}
