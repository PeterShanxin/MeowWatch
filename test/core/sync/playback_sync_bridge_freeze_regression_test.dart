import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/app_log.dart';
import 'package:meowwatch/core/debug/debug_log.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// A logger whose every call throws — models the field condition where the
/// process-wide [DebugLog]'s IOSink was in a transient bad state during a rapid
/// pause/seek/resume burst (2026-06-21 field freeze).
class _ThrowingLog extends DebugLog {
  _ThrowingLog() : super(File('unused_throwing_log_does_not_open'));

  @override
  void call(String line) => throw StateError('diagnostic sink in a bad state');
}

/// A VideoCore that logs through [appLog] BEFORE recording/emitting — exactly
/// like the real [MediaKitVideoCore], whose `play()`/`seek()`/`pause()` are NOT
/// async and call `appLog('trace: ...')` synchronously before the libmpv call.
/// That ordering is what made a throwing logger turn a player command into a
/// SYNCHRONOUS throw in the field (the existing test fakes never logged, so they
/// could not reproduce the freeze).
class _LoggingVideoCore extends VideoCore {
  final List<String> commands = [];

  @override
  Future<void> load(String filePath) async {}

  @override
  Future<void> play() {
    appLog('trace: play');
    commands.add('play');
    emit(state.copyWith(status: PlaybackStatus.playing));
    return Future<void>.value();
  }

  @override
  Future<void> pause() {
    appLog('trace: pause');
    commands.add('pause');
    emit(state.copyWith(status: PlaybackStatus.paused));
    return Future<void>.value();
  }

  @override
  Future<void> seek(Duration position) {
    appLog('trace: seek ${position.inMilliseconds}ms');
    commands.add('seek:${position.inMilliseconds}ms');
    emit(state.copyWith(position: position));
    return Future<void>.value();
  }

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {}

  void push(PlaybackState s) => emit(s);
}

class _RecordingSyncCore extends SyncCore {
  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  void pushPeer(PeerPlayState s) => emitPeerState(s);
}

void main() {
  test(
    'a throwing diagnostic logger never freezes peer-state apply (field freeze '
    '2026-06-21)',
    () async {
      final video = _LoggingVideoCore();
      final sync = _RecordingSyncCore();
      final bridge = PlaybackSyncBridge(video: video, sync: sync)..start();
      addTearDown(() async {
        await bridge.dispose();
        await video.dispose();
        await sync.dispose();
        installAppLog(null);
      });

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);

      // The diagnostic sink goes bad right before the burst — every appLog throws.
      installAppLog(_ThrowingLog());

      // A peer resume whose command issuing logs (and the logger throws). In the
      // field this threw synchronously out of video.play(), then the drain loop's
      // own error log threw too, leaving `_drainingPeerStates` stuck true.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          doSeek: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      video.commands.clear();

      // A later peer back-seek MUST still be applied — the bridge must not have
      // frozen all future sync because a log call threw.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 600),
          paused: false,
          doSeek: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        video.commands,
        contains('seek:600000ms'),
        reason:
            'a throwing logger must not leak the drain flag and freeze later '
            'peer-state delivery',
      );
    },
  );
}
