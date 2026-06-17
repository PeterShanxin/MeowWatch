import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(fileName: filePath, status: PlaybackStatus.paused));
  }

  @override
  Future<void> play() async =>
      emit(state.copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async =>
      emit(state.copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> seek(Duration position) async =>
      emit(state.copyWith(position: position));

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {}

  void push(PlaybackState s) => emit(s);
}

class _RecordingSyncCore extends SyncCore {
  final List<({Duration position, bool paused})> localUpdates = [];
  final List<bool> changes = []; // doSeek values

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
  void updateLocalState({required Duration position, required bool paused}) {
    localUpdates.add((position: position, paused: paused));
  }

  @override
  void notifyLocalChange({required bool doSeek}) => changes.add(doSeek);

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  void pushPeer(PeerPlayState s) => emitPeerState(s);
}

void main() {
  late _FakeVideoCore video;
  late _RecordingSyncCore sync;
  late PlaybackSyncBridge bridge;

  setUp(() {
    video = _FakeVideoCore();
    sync = _RecordingSyncCore();
    bridge = PlaybackSyncBridge(video: video, sync: sync)..start();
  });

  tearDown(() async {
    await bridge.dispose();
    await video.dispose();
    await sync.dispose();
  });

  test('local pause toggle notifies a non-seek change', () async {
    // Only a source the load coordinator has accepted (markSourceOpen) drives
    // the heartbeat and seek/pause detection — a duration alone no longer
    // confirms it (the backend opens before the coordinator accepts).
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(false));
  });

  test(
    'a stale backend tick during the remote-apply window is not fed to the '
    'heartbeat',
    () async {
      // Confirm a source so its ticks drive the heartbeat.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);

      // A peer seeks us forward and pauses — the bridge applies it locally and
      // opens the remote-apply suppression window (during which local fallout
      // must be ignored, not echoed back to the room).
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 386),
          paused: true,
          doSeek: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      sync.localUpdates.clear();

      // A delayed libmpv tick from BEFORE the apply now lands (near 0, playing).
      // Feeding it to the heartbeat would broadcast the pre-apply position and
      // start a rewind/seek fight with the peer (the post-0.28.0 sync thrash).
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(milliseconds: 33),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.localUpdates,
        isEmpty,
        reason:
            'a stale tick within the remote-apply window must not reach the heartbeat',
      );
    },
  );

  test('a large position jump is detected as a seek', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 1),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    sync.changes.clear();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 30),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(true));
  });

  test(
    'applying a remote peer state does not re-notify a local change',
    () async {
      sync.changes.clear();
      sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 10), paused: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sync.changes, isEmpty);
      expect(video.state.position, const Duration(seconds: 10));
    },
  );

  test('remote paused transition pauses and aligns the local video', () async {
    video.push(
      const PlaybackState(status: PlaybackStatus.playing, fileName: 'a'),
    );
    await Future<void>.delayed(Duration.zero);
    // First peer state (playing) is the initial adopt; then a pause flip.
    sync.pushPeer(
      const PeerPlayState(position: Duration(seconds: 4), paused: false),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    sync.pushPeer(
      const PeerPlayState(position: Duration(seconds: 5), paused: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.status, PlaybackStatus.paused);
    expect(video.state.position, const Duration(seconds: 5));
  });

  test(
    'bridge applies each emitted peer state (filtering lives upstream)',
    () async {
      // The SyncCore only emits actionable states (see sync_follow_test); the
      // bridge applies whatever it is given.
      sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 42), paused: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(video.state.position, const Duration(seconds: 42));
    },
  );

  test('a small-drift pause flip aligns exactly for frame inspection', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 10),
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    // Peer paused 100ms away (doSeek=false). While playing, that difference is
    // harmless drift; once paused, it can be several frames at a hard cut, so
    // align exactly for "pause on this frame" moments.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(milliseconds: 10100),
        paused: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.status, PlaybackStatus.paused);
    expect(video.state.position, const Duration(milliseconds: 10100));
  });

  test('a small-drift resume flip still plays without re-seeking', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 10),
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    // Resume stays tolerant so normal play/pause doesn't cause a tiny jump when
    // the peer is only a few frames away.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(milliseconds: 10100),
        paused: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.status, PlaybackStatus.playing);
    expect(video.state.position, const Duration(seconds: 10));
  });

  // ── File-load suppression (#91) ───────────────────────────────────────────

  test(
    'loading a new file (filePath change) does not emit a seek notification',
    () async {
      // Establish baseline at non-zero position on file 'a'.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 60),
          filePath: '/videos/a.mkv',
          fileName: 'a.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.changes.clear();

      // Load a new file — different filePath, position resets to 0.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          filePath: '/videos/b.mkv',
          fileName: 'b.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.changes,
        isEmpty,
        reason: 'file load must not be classified as a seek',
      );
    },
  );

  test(
    'same basename in different directory is treated as a new file load',
    () async {
      // Establish baseline on /folderA/movie.mkv.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 60),
          filePath: '/folderA/movie.mkv',
          fileName: 'movie.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.changes.clear();

      // Same basename, different directory → filePath differs → load, not seek.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          filePath: '/folderB/movie.mkv',
          fileName: 'movie.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.changes,
        isEmpty,
        reason: 'different path with same basename must be treated as a load',
      );
    },
  );

  test(
    'reloading the same file (loading status) does not emit a seek',
    () async {
      // Establish baseline at 60s.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 60),
          filePath: '/videos/a.mkv',
          fileName: 'a.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.changes.clear();

      // Player transitions through loading when reloading the same file.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.loading,
          position: Duration.zero,
          filePath: '/videos/a.mkv',
          fileName: 'a.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          filePath: '/videos/a.mkv',
          fileName: 'a.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.changes,
        isEmpty,
        reason: 'same-file reload must not be classified as a seek',
      );
    },
  );

  test('seek within the same file still emits a seek notification', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 5),
        duration: Duration(minutes: 10),
        filePath: '/videos/a.mkv',
        fileName: 'a.mkv',
      ),
    );
    bridge.markSourceOpen('/videos/a.mkv');
    await Future<void>.delayed(Duration.zero);
    sync.changes.clear();

    // Same filePath, large position jump → real seek.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 90),
        duration: Duration(minutes: 10),
        filePath: '/videos/a.mkv',
        fileName: 'a.mkv',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sync.changes, contains(true));
  });

  test('first-ever file load (null → filePath) does not emit a seek', () async {
    // No prior push — _lastFilePath is null. Loading the first file must not
    // trigger seek detection even though position starts at 0.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration.zero,
        filePath: '/videos/movie.mkv',
        fileName: 'movie.mkv',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sync.changes, isEmpty);
  });

  test('loading and error states are NOT published to the heartbeat', () async {
    // A new/failing load sits at position 0 paused; pushing that to the room
    // would make a watching peer pause/rewind for a load that may never land.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.loading,
        position: Duration.zero,
        filePath: '/videos/new.mkv',
        fileName: 'new.mkv',
      ),
    );
    video.push(
      const PlaybackState(
        status: PlaybackStatus.error,
        position: Duration.zero,
        filePath: '/videos/new.mkv',
        fileName: 'new.mkv',
        errorMessage: 'boom',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'unconfirmed/failed loads must not drive the room heartbeat',
    );
  });

  test('a zero-duration pre-error tick is NOT published to the heartbeat', () async {
    // The instant open() returns, a bad/slow source emits `paused` at position 0
    // with no duration yet — *before* its error. It is no longer `loading`, but
    // it is not a confirmed open either; publishing it would pause/rewind a peer.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration.zero,
        filePath: '/videos/bad.mp4',
        fileName: 'bad.mp4',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'a zero-duration (unconfirmed) open must not drive the heartbeat',
    );
  });

  test('a coordinator-accepted state IS published to the heartbeat', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 3),
        duration: Duration(minutes: 10),
        filePath: '/videos/a.mkv',
        fileName: 'a.mkv',
      ),
    );
    bridge.markSourceOpen('/videos/a.mkv');
    await Future<void>.delayed(Duration.zero);

    expect(sync.localUpdates, isNotEmpty);
    expect(sync.localUpdates.last.position, const Duration(seconds: 3));
    expect(sync.localUpdates.last.paused, isTrue);
  });

  test(
    'a backend-open but coordinator-unaccepted source does NOT heartbeat',
    () async {
      // The backend reported the source open (a real duration → isPlaybackOpen),
      // but `_load` hasn't called markSourceOpen yet (it's still in _recordOpen).
      // Publishing here would broadcast a source that may be superseded before it
      // is ever announced — the race from PR #129's post-merge review.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 3),
          duration: Duration(minutes: 10),
          filePath: '/videos/a.mkv',
          fileName: 'a.mkv',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.localUpdates,
        isEmpty,
        reason:
            'a duration alone must not drive the heartbeat before the '
            'coordinator accepts the source',
      );
    },
  );

  test('an accepted live stream (no duration) drives the heartbeat after '
      'markSourceOpen', () async {
    const live = 'https://x.test/live.m3u8';
    // A live/direct stream sits at position 0 with no duration — the player pins
    // its position at 0 (position_guard) so the bridge cannot infer "open" from
    // the stream alone. Until the coordinator confirms it, it must not heartbeat.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration.zero,
        filePath: live,
        fileName: 'live.m3u8',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'an unconfirmed durationless stream must not heartbeat',
    );

    // The load coordinator accepts it: now it heartbeats even with no duration,
    // and markSourceOpen replays the current state immediately.
    bridge.markSourceOpen(live);
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.localUpdates,
      isNotEmpty,
      reason: 'a confirmed live stream heartbeats even without a duration',
    );
    sync.changes.clear();

    // A later play on the same live source is a non-seek local change.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration.zero,
        filePath: live,
        fileName: 'live.m3u8',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.changes,
      contains(false),
      reason: 'play on a confirmed live stream is a non-seek local change',
    );
  });

  test(
    'confirming a source the user already started playing re-asserts the play',
    () async {
      const live = 'https://x.test/live.m3u8';
      // The user pressed play while the source was still unconfirmed: the playing
      // tick is suppressed — not published, no change emitted.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration.zero,
          filePath: live,
          fileName: 'live.m3u8',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.localUpdates, isEmpty);
      expect(sync.changes, isEmpty);

      // Confirmation must re-assert that pending play as an intentional local
      // change, or a peer's stale paused heartbeat could win convergence and
      // pause us back / the friend never gets the play we already requested.
      bridge.markSourceOpen(live);
      await Future<void>.delayed(Duration.zero);
      expect(
        sync.localUpdates,
        isNotEmpty,
        reason: 'a confirmed source heartbeats',
      );
      expect(
        sync.changes,
        contains(false),
        reason: 'the already-started play is re-asserted as a local change',
      );
    },
  );

  test(
    'confirming a source a PEER started playing does not re-assert it as ours',
    () async {
      const live = 'https://x.test/live.m3u8';
      // Source is still loading/unconfirmed.
      video.push(
        const PlaybackState(
          status: PlaybackStatus.loading,
          filePath: live,
          fileName: 'live.m3u8',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // A peer plays us while unconfirmed → _onPeerState applies play() locally.
      sync.pushPeer(
        const PeerPlayState(position: Duration.zero, paused: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sync.changes.clear();

      // On confirmation, the peer-driven play must NOT be re-asserted as our local
      // change — the peer is already authoritative; doing so would steal authorship.
      bridge.markSourceOpen(live);
      await Future<void>.delayed(Duration.zero);
      expect(
        sync.changes,
        isEmpty,
        reason: 'a peer-forced pre-open play is not re-asserted as local',
      );
    },
  );
}
