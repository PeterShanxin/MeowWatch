import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_messages.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

/// Repro for the production sync failure: the follower decides `apply=true`
/// (the FOLLOW notification fires) but its VIDEO never receives play/pause/seek.
///
/// Unlike the existing bridge tests — which call `emitPeerState` on a *fake*
/// SyncCore — this drives the **real** [SyncplayClient._handleState] (via
/// [SyncplayClient.debugHandleMessage]) through the **real** [PlaybackSyncBridge]
/// into a fake [VideoCore]. If the real client→bridge→video path is sound in
/// pure Dart, the fake video records `play`; if it reproduces production, it
/// records nothing.
class _FakeVideoCore extends VideoCore {
  final List<String> commands = [];

  @override
  Future<void> load(String filePath) async {
    commands.add('load:$filePath');
    emit(state.copyWith(fileName: filePath, status: PlaybackStatus.paused));
  }

  @override
  Future<void> play() async {
    commands.add('play');
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    emit(state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inMilliseconds}ms');
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {}
}

void main() {
  test('real client _handleState peer play drives the bridge video', () async {
    final video = _FakeVideoCore();
    final client = SyncplayClient();
    final bridge = PlaybackSyncBridge(video: video, sync: client)..start();

    client.debugMarkLoggedIn('p2');
    // Local: paused at 0 (just loaded, like the follower in the real test).
    client.updateLocalState(position: Duration.zero, paused: true);

    // p1 presses play: global playing at 0.522s, set by the peer.
    client.debugHandleMessage(
      const StateMessage(
        peer: PeerPlayState(
          position: Duration(milliseconds: 522),
          paused: false,
          doSeek: false,
          setBy: 'p1',
        ),
      ),
    );

    // Let the broadcast controller deliver to the bridge listener.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      video.commands,
      contains('play'),
      reason: 'follower video must receive play() when a peer plays',
    );

    await bridge.dispose();
    await client.dispose();
  });

  test(
    'peer apply commands video before the heartbeat reply continues',
    () async {
      final video = _FakeVideoCore();
      final client = SyncplayClient();
      final bridge = PlaybackSyncBridge(video: video, sync: client)..start();

      client.debugMarkLoggedIn('p2');
      client.updateLocalState(position: Duration.zero, paused: true);

      client.debugHandleMessage(
        const StateMessage(
          peer: PeerPlayState(
            position: Duration(milliseconds: 522),
            paused: false,
            doSeek: false,
            setBy: 'p1',
          ),
        ),
      );

      expect(
        video.commands,
        contains('play'),
        reason:
            'peer apply must not depend on a later stream microtask after the '
            'client has already adopted the peer state into its cache',
      );

      await bridge.dispose();
      await client.dispose();
    },
  );
}
