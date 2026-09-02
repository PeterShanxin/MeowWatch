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

  void push(PlaybackState s) => emit(s);
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

  test('peer apply starts the video command path synchronously', () async {
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
      contains('seek:522ms'),
      reason:
          'peer apply must enter the video command path before the client '
          'continues with its heartbeat reply',
    );

    await Future<void>.delayed(Duration.zero);

    expect(
      video.commands,
      contains('play'),
      reason: 'resume playback follows once the required seek completes',
    );

    await bridge.dispose();
    await client.dispose();
  });

  test('a frozen peer stops driving the rewind sawtooth', () async {
    // Layer 2 end-to-end (the 2026-06-20 field regression). The peer claims
    // `playing` but is FROZEN at 500s. We keep advancing past it, so every
    // heartbeat we are >rewindThreshold (4s) ahead — the old rule rewound us to
    // 500 on EVERY heartbeat, an unwatchable sawtooth. Once the client detects
    // the peer is stalled it must stop rewinding and let us keep playing.
    final logs = <String>[];
    final client = SyncplayClient(onLog: logs.add);
    client.debugMarkLoggedIn('p2');

    var localSec = 505;
    for (var i = 0; i < 12; i++) {
      // We are playing and steadily advancing well ahead of the frozen peer.
      client.updateLocalState(
          position: Duration(seconds: localSec), paused: false);
      client.debugHandleMessage(
        const StateMessage(
          peer: PeerPlayState(
            position: Duration(seconds: 500),
            paused: false,
            doSeek: false,
            setBy: 'p1',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      localSec += 5;
    }

    final follow = logs.where((l) => l.startsWith('FOLLOW')).toList();
    expect(
      follow.any((l) => l.contains('apply=true')),
      isTrue,
      reason: 'the first heartbeats, before the stall is detected, do rewind — '
          'proving the sawtooth would otherwise run',
    );
    expect(
      follow.last,
      stringContainsInOrder(['stalled=true', 'apply=false']),
      reason: 'a peer detected frozen must no longer be chased with a rewind',
    );
    final rewinds = follow.where((l) => l.contains('apply=true')).length;
    expect(
      rewinds,
      lessThan(follow.length),
      reason: 'the rewind must not fire on every heartbeat — the sawtooth stops '
          'once the peer is stalled',
    );

    await client.dispose();
  });

  test(
    'a doSeek=false room at 309s is cached and the first catch-up applies',
    () async {
      final video = _FakeVideoCore();
      final logs = <String>[];
      final client = SyncplayClient(onLog: logs.add);
      final bridge = PlaybackSyncBridge(video: video, sync: client)..start();
      addTearDown(() async {
        await bridge.dispose();
        await client.dispose();
      });

      client.debugMarkLoggedIn('SmokeB');
      client.updateLocalState(position: Duration.zero, paused: true);

      client.debugHandleMessage(
        const StateMessage(
          peer: PeerPlayState(
            position: Duration(seconds: 309),
            paused: true,
            doSeek: false,
            setBy: 'SmokeA',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        client.lastObservedRoomState?.position,
        const Duration(seconds: 309),
        reason: 'the room must be remembered even when the State has no doSeek',
      );
      expect(
        logs.where((l) => l.startsWith('FOLLOW') && l.contains('apply=true')),
        isNotEmpty,
        reason: 'a joiner far behind a named setter must catch up once',
      );

      // Simulate the product load that resets to 0 after that first State.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          duration: Duration(minutes: 25),
          fileName: 'mw-long.webm',
          filePath: '/videos/mw-long.webm',
          opened: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();

      bridge.markSourceOpen('/videos/mw-long.webm');
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, contains('seek:309000ms'));
      expect(video.state.position, const Duration(seconds: 309));
    },
  );
}
