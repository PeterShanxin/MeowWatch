import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  final List<String> commands = [];
  bool emitFromPause = true;
  bool emitFromPlay = true;
  bool emitFromSeek = true;
  Completer<void>? playGate;
  Completer<void>? seekGate;

  @override
  Future<void> load(String filePath) async {
    commands.add('load:$filePath');
    emit(state.copyWith(fileName: filePath, status: PlaybackStatus.paused));
  }

  @override
  Future<void> play() async {
    commands.add('play');
    if (emitFromPlay) {
      emit(state.copyWith(status: PlaybackStatus.playing));
    }
    final gate = playGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    if (emitFromPause) {
      emit(state.copyWith(status: PlaybackStatus.paused));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inMilliseconds}ms');
    if (emitFromSeek) {
      emit(state.copyWith(position: position));
    }
    final gate = seekGate;
    if (gate != null) await gate.future;
  }

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

/// Pump the event loop until [reached] holds or [timeout] elapses.
///
/// Watchdog assertions hinge on a `Timer` that fires after a short window; a
/// fixed `Future.delayed` barely longer than that window flakes when the whole
/// suite is competing for the CPU and the timer fires late (the re-kick lands
/// just after the assertion already ran). Polling returns the moment the
/// expected state is reached, so the test stays fast while tolerating jitter.
Future<void> _pumpUntil(
  bool Function() reached, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!reached() && stopwatch.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
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

  test('a stale backend tick during the remote-apply window is not fed to the '
      'heartbeat', () async {
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
  });

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

  test('a seek landing with a pause flip is still sent as a seek', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 10),
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
        status: PlaybackStatus.paused,
        position: Duration(seconds: 90),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sync.changes, <bool>[true]);
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

  test(
    'remote resume still kicks the core when local state already says playing',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 4),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 4),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(video.commands, <String>['play']);
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

  test('remote resume seeks before waking a paused video', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(milliseconds: 395),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(milliseconds: 2900),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(video.commands, <String>['seek:2900ms', 'play']);
  });

  test(
    'remote resume does not wait forever for a stalled seek future',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      sync.localUpdates.clear();
      video.commands.clear();
      video.seekGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, <String>['seek:679000ms', 'play']);

      video.seekGate!.complete();
      await Future<void>.delayed(Duration.zero);
      video.seekGate = null;
    },
  );

  test('stalled remote resume seek does not block later peer states', () async {
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();
    video.seekGate = Completer<void>();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 680),
        paused: true,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(video.commands, <String>[
      'seek:679000ms',
      'play',
      'seek:680000ms',
      'pause',
    ]);

    video.seekGate!.complete();
    await Future<void>.delayed(Duration.zero);
    video.seekGate = null;
  });

  test(
    'remote resume re-seeks after play when paused seek has not landed',
    () async {
      await bridge.dispose();
      bridge = PlaybackSyncBridge(
        video: video,
        sync: sync,
        remoteResumeSeekWait: const Duration(milliseconds: 1),
      )..start();
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();
      video.emitFromSeek = false;
      video.seekGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(video.commands, <String>[
        'seek:679000ms',
        'play',
        'seek:679000ms',
      ]);

      video.seekGate!.complete();
      await Future<void>.delayed(Duration.zero);
      video.seekGate = null;
    },
  );

  test('remote resume fallback seek waits until playback is running', () async {
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeSeekWait: const Duration(milliseconds: 1),
      remoteCommandWait: const Duration(milliseconds: 1),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();
    video.emitFromSeek = false;
    video.emitFromPlay = false;
    video.playGate = Completer<void>();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(video.commands, <String>['seek:679000ms', 'play']);

    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(video.commands, <String>['seek:679000ms', 'play', 'seek:679000ms']);

    video.playGate!.complete();
    await Future<void>.delayed(Duration.zero);
    video.playGate = null;
  });

  test(
    'explicit peer seek is issued before a slow play can leak stale ticks',
    () async {
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
      sync.localUpdates.clear();
      video.commands.clear();
      video.playGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          doSeek: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, <String>['seek:679000ms', 'play']);

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 21),
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
            'stale pre-seek ticks must stay out of the heartbeat while '
            'remote play is still applying',
      );

      video.playGate!.complete();
      await Future<void>.delayed(Duration.zero);
      video.playGate = null;
    },
  );

  test(
    'remote resume with drift waits for the target position before settling',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      sync.localUpdates.clear();
      video.commands.clear();
      video.playGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, <String>['seek:679000ms', 'play']);

      video.playGate!.complete();
      await Future<void>.delayed(Duration.zero);
      video.playGate = null;

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 21),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 850));

      expect(
        sync.localUpdates,
        isEmpty,
        reason:
            'a remote resume that had to seek must not settle on a stale '
            'playing tick at the old position',
      );
    },
  );

  test(
    'a matching remote tick clears the settle target during the apply window',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      sync.localUpdates.clear();
      video.commands.clear();
      video.playGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, <String>['seek:679000ms', 'play']);

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 679),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.localUpdates, isEmpty);

      video.playGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 850));
      video.playGate = null;

      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
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
            'late backend fallout after the target lands must not echo an '
            'old pause/position as local input',
      );

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 700),
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
            'late pre-seek ticks ahead of a backward remote seek target must '
            'not be echoed as local playback',
      );

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 680),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.localUpdates.last,
        (position: const Duration(seconds: 680), paused: false),
        reason:
            'once the matching backend tick clears the target, later real '
            'playback ticks must resume the heartbeat without waiting for the '
            'full settle timeout',
      );
    },
  );

  test(
    'the landing tick that settles a remote seek is still suppressed',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      sync.localUpdates.clear();
      sync.changes.clear();
      video.commands.clear();
      video.emitFromPlay = false;
      video.emitFromSeek = false;

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 850));

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 679),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        sync.localUpdates,
        isEmpty,
        reason: 'the remote seek landing tick must not be echoed as local',
      );
      expect(
        sync.changes,
        isEmpty,
        reason: 'the remote seek landing tick must not be classified as ours',
      );

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(milliseconds: 679500),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.localUpdates, isNotEmpty);
    },
  );

  test(
    'remote pause is issued immediately even when the aligning seek is slow',
    () async {
      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 9),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      sync.localUpdates.clear();
      video.commands.clear();
      video.seekGate = Completer<void>();

      sync.pushPeer(
        const PeerPlayState(
          position: Duration(milliseconds: 8666),
          paused: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(video.commands, <String>['seek:8666ms', 'pause']);

      video.push(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(milliseconds: 10266),
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
            'a late playing tick from a remote pause must not resume the '
            'room heartbeat',
      );

      video.seekGate!.complete();
      await Future<void>.delayed(Duration.zero);
      video.seekGate = null;
    },
  );

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

  // ── Stalled-resume watchdog (fast pause→seek→resume freeze) ───────────────
  //
  // Field bug: a peer fires pause → seek → resume in rapid succession (all in
  // one ignoringOnTheFly handshake). We apply seek+play, but the engine ends up
  // reporting `playing` while its position is frozen at the seek target — so the
  // friend looks stuck and the advancing peer gets rewound. Nothing verified
  // that playback actually ADVANCED after a remote resume; this watchdog does.

  test(
    'a remote resume whose playback never advances is re-kicked',
    () async {
      await bridge.dispose();
      bridge = PlaybackSyncBridge(
        video: video,
        sync: sync,
        remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      )..start();
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();

      // Peer resumes to 679s: we seek + play. The fake reports `playing` at 679s
      // (status flips) but the position never climbs — the frozen-engine bug.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(video.commands, <String>['seek:679000ms', 'play']);

      // Playback never advances past the resume target. After the advance
      // window the bridge re-kicks the stalled resume instead of sitting frozen.
      // Poll rather than wait a fixed delay: the watchdog timer can fire late
      // under load, and a fixed wait barely past the window flakes (see the
      // re-kick race that surfaced when this ran inside the full suite).
      await _pumpUntil(() => video.commands.length >= 4);
      expect(
        video.commands,
        <String>['seek:679000ms', 'play', 'seek:679000ms', 'play'],
        reason:
            'a remote resume that never starts advancing must be re-kicked '
            'with a fresh seek+play',
      );
    },
  );

  test('a remote resume that begins advancing is not re-kicked', () async {
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(video.commands, <String>['seek:679000ms', 'play']);

    // Playback actually advances past the target — a healthy resume.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 680),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // No kick may follow once playback is genuinely moving.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      video.commands,
      <String>['seek:679000ms', 'play'],
      reason: 'a resume that is advancing normally must not be re-kicked',
    );
  });

  test('a remote resume that lands paused is not re-kicked', () async {
    // A genuine remote PAUSE (not a resume) must never be un-paused by the
    // watchdog: a paused player that is "not advancing" is correct, not stuck.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
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
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 20),
        paused: true,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(video.commands, <String>['pause']);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      video.commands,
      <String>['pause'],
      reason: 'a deliberately paused player must not be kicked into playing',
    );
  });

  test('a remote resume on a durationless live stream is not re-kicked', () async {
    // A confirmed live/direct stream has no duration. The position guard
    // intentionally pins its reported position (it rejects positive positions
    // without a duration), so "position not advancing" is normal there, not a
    // frozen resume. Kicking it would re-issue seek(0)+play on a live URL,
    // which can jump or stall the stream — so the watchdog must stand down.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration.zero,
        duration: Duration.zero,
        filePath: 'live',
        fileName: 'live',
      ),
    );
    bridge.markSourceOpen('live');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Peer resumes far ahead, so the resume seeks + plays like any other.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final afterResume = List<String>.from(video.commands);

    // Past the advance window, a durationless stream must NOT be re-kicked.
    await _pumpUntil(
      () => video.commands.length > afterResume.length,
      timeout: const Duration(milliseconds: 200),
    );
    expect(
      video.commands,
      afterResume,
      reason: 'a durationless live stream must not trigger the stalled-resume kick',
    );
  });

  test('a resume whose seek has not landed is not kicked to the stale position', () async {
    // The big resume seek is slow to land (e.g. a paused VOD): when the watchdog
    // fires, the player is still sitting below the target. Nothing is frozen to
    // un-stick yet, and seeking to the stale current position would yank the
    // client backwards — so the watchdog stands down and leaves the resume's own
    // re-seek and peer heartbeats to converge to the target.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeSeekWait: const Duration(milliseconds: 10),
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    // Seeks never move the reported position — the resume target never lands.
    video.emitFromSeek = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );

    // No kick: the only play is the resume's own, and nothing seeks to the
    // stale 20s position.
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 120),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      1,
      reason: 'a not-yet-landed resume is left to converge, not re-kicked',
    );
    expect(
      video.commands,
      isNot(contains('seek:20000ms')),
      reason: 'the watchdog must never seek to the stale current position',
    );
  });

  test('a watchdog kick does not override a newer peer pause', () async {
    // The watchdog fires and the kick begins, but its seek is still in flight
    // when a newer peer PAUSE arrives. The kick must not finish by playing over
    // that pause — stale resume kicks cannot override later remote state.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 but never advances — the watchdog will arm.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so we can interleave a newer pause while it is in
    // flight.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    // A newer peer pause arrives and is applied while the kick is blocked.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: true,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(video.state.status, PlaybackStatus.paused);

    // Release the kick; it must abort rather than play over the newer pause.
    video.seekGate!.complete();
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 120),
    );
    expect(
      video.state.status,
      PlaybackStatus.paused,
      reason: 'a stale resume kick must not undo a newer peer pause',
    );
  });

  test(
    'a watchdog kick does not strand the player on the stale target when a '
    'newer peer pause targets a different position',
    () async {
      // Codex PR #157 review (comment 3445396424): when a newer peer state with
      // a DIFFERENT position lands while the kick's seek is in flight, the kick
      // must not leave the player parked on the old resume target. The kick's
      // seek is issued synchronously at watchdog-fire — before any newer state —
      // so the newer state's later seek wins by wire order, and the post-seek
      // seq guard drops the stale play. (The sibling test above pauses at the
      // same 679s target, so it cannot tell a stranded player from a correct one;
      // this one pauses at 30s to make the position invariant observable.)
      await bridge.dispose();
      bridge = PlaybackSyncBridge(
        video: video,
        sync: sync,
        remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      )..start();
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();

      // Resume lands at 679 and parks there — the watchdog will fire.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Gate the kick's seek so a newer pause can interleave while it is in
      // flight.
      video.seekGate = Completer<void>();
      await _pumpUntil(
        () => video.commands.length > 2,
        timeout: const Duration(milliseconds: 200),
      );

      // A newer peer pause targets a DIFFERENT position (30s, not the 679s
      // resume target). It is applied while the kick is blocked, moving the
      // player to 30s/paused.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 30),
          paused: true,
          setBy: 'peer',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(video.state.position, const Duration(seconds: 30));
      expect(video.state.status, PlaybackStatus.paused);

      // Release the kick; it must abort, leaving the newer pause untouched —
      // neither stranding the player back on 679s nor playing over the pause.
      video.seekGate!.complete();
      await _pumpUntil(
        () => video.commands.where((c) => c == 'play').length >= 2,
        timeout: const Duration(milliseconds: 120),
      );
      expect(
        video.state.position,
        const Duration(seconds: 30),
        reason: 'a stale resume kick must not strand the player back on 679s',
      );
      expect(
        video.state.status,
        PlaybackStatus.paused,
        reason: 'a stale resume kick must not play over a newer peer pause',
      );
    },
  );

  test('a local seek during the resume window stands the watchdog down', () async {
    // The watchdog detects a frozen engine by the position staying put. A local
    // user action moves the position, so it is not a freeze — the watchdog must
    // not re-seek to the peer target and undo the user's seek.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Peer resumes to 679; it lands and we play, arming the watchdog.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(video.commands, <String>['seek:679000ms', 'play']);
    video.commands.clear();

    // Before playback advances, the local user seeks back to 20s, still playing.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );

    // The watchdog must stand down — no re-seek to the peer target.
    await _pumpUntil(
      () => video.commands.isNotEmpty,
      timeout: const Duration(milliseconds: 120),
    );
    expect(
      video.commands,
      isEmpty,
      reason: 'a local seek moved the position, so the resume is not frozen',
    );
  });

  test('a slow seek that lands mid-window then freezes is still re-kicked', () async {
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeSeekWait: const Duration(milliseconds: 10),
      remoteResumeAdvanceWait: const Duration(milliseconds: 60),
    )..start();
    // The resume seek is slow: it does not move the reported position when the
    // watchdog is armed (the player still sits at the old spot).
    video.emitFromSeek = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    // Let the resume path run to its play (one play so far).
    await _pumpUntil(
      () => video.commands.contains('play'),
      timeout: const Duration(milliseconds: 200),
    );

    // The slow seek finally lands at the target, but the engine freezes there:
    // playing, position == target, not advancing.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );

    // A landed-then-frozen resume is still frozen: the watchdog must re-kick
    // (a second play), not treat the late seek's jump as real progress.
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 300),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      greaterThanOrEqualTo(2),
      reason: 'a seek that lands then freezes at the target is still frozen',
    );
  });

  test('a watchdog kick aborts when the bridge is disposed mid-seek', () async {
    // The user leaves the room after the watchdog fires but while the kick's
    // seek is still in flight. The bridge is disposed and its VideoCore returns
    // to the pool; the stale kick must not seek/play that shared player in the
    // lobby or the next room.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 and parks there — the watchdog will fire.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(video.commands, <String>['seek:679000ms', 'play']);

    // Gate the kick's seek so we can dispose while it is in flight.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    // The bridge is disposed while the kick waits on its seek.
    await bridge.dispose();

    // Release the kick; it must abort rather than play the disposed/pooled player.
    video.seekGate!.complete();
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 120),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      1,
      reason: 'a kick must not play after the bridge is disposed',
    );
  });

  test('a persistent local pause during the kick stands it down', () async {
    // Codex PR #157 review (comment 3445411229): if the user pauses while the
    // kick's seek is still awaiting, `_peerStateSeq` is unchanged (it only tracks
    // PEER states), so the seq guard alone would let the kick play over the
    // user's pause. The kick settles, then stands down on a pause that PERSISTS:
    // a player no longer `playing` is not a frozen resume to un-stick. (A
    // transient seek-pause that clears is handled by the sibling test below.)
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 and parks there (frozen) — the watchdog will fire.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so a local pause can land while it is in flight.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    // The user pauses locally while the kick's seek is blocked. This updates the
    // live player state but does NOT bump `_peerStateSeq`.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Release the kick; it must respect the local pause, not play over it.
    video.seekGate!.complete();
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 120),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      1,
      reason: 'a kick must not play over a local pause',
    );
    expect(
      video.state.status,
      PlaybackStatus.paused,
      reason: 'the user-requested pause must stand',
    );
  });

  test('a transient pause from the kick own seek is not mistaken for a user '
      'pause', () async {
    // Codex PR #157 review (comment 3445431801): the kick's own seek landing can
    // briefly report `paused` (backend fallout) even though no user paused.
    // Reading status in that instant would abort the unstick and leave the
    // resume frozen — the original bug. The kick must wait for the truth to
    // settle: a transient pause clears back to playing, so the unstick proceeds.
    // (A pause that PERSISTS is the user's — see the sibling test above.)
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 and parks there (frozen) — the watchdog will fire.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so we can stage the transient pause around it.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    // The seek landing transiently reports paused — backend fallout, NOT a user
    // action (it does not bump `_peerStateSeq` and it does not persist).
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Release the kick; it enters the settle wait with status momentarily paused.
    video.seekGate!.complete();
    await Future<void>.delayed(Duration.zero);

    // The transient clears: the engine reports playing again within the settle.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );

    // The unstick must still happen — a transient seek-pause is not a user pause.
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 200),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      2,
      reason: 'a transient seek-pause must not abort the unstick',
    );
  });

  test('a persistent local pause during the kick is published to the room',
      () async {
    // Codex PR #157 review (comment 3445483184): a local pause landing while the
    // kick holds `_applyingRemote` is suppressed by `_onLocalState`, and a still
    // player may never emit another tick — so the room would keep the stale
    // peer-driven "playing" forever. When the kick stands down on a settled
    // pause it must publish that pause so the room follows (a beat later).
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 and parks (frozen) — the watchdog arms.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so the local pause lands while the kick holds the
    // remote-apply guard.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    sync.localUpdates.clear();
    sync.changes.clear();

    // The user pauses; the tick is suppressed in the moment (`_applyingRemote`).
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'the pause is suppressed while the kick holds the apply guard',
    );

    // Release the kick; it settles, finds a persistent pause, stands down — and
    // must publish that pause so the room does not keep the stale "playing".
    video.seekGate!.complete();
    await _pumpUntil(
      () => sync.localUpdates.any((u) => u.paused),
      timeout: const Duration(milliseconds: 200),
    );
    expect(
      sync.localUpdates.any((u) => u.paused),
      isTrue,
      reason: 'a stood-down kick must publish the local pause to the room',
    );
  });

  test('a backward local seek during the kick is published to the room',
      () async {
    // Codex PR #157 review (comment 3445494456): a local action during the kick
    // is suppressed by `_onLocalState` (the kick holds `_applyingRemote`). Round 8
    // fixed this for a pause; a backward SEEK while still `playing` was still lost
    // — the settle guard only stood down on `status != playing`, so a playing seek
    // fell through to `play()`, which re-asserted the target AND never told the
    // room. The kick must stand down on ANY settled divergence from the target and
    // publish the true state, sending the seek via `doSeek` so the peer follows.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Resume lands at 679 and parks (frozen) — the watchdog arms.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so the user's backward seek lands while the kick holds
    // the remote-apply guard.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    sync.localUpdates.clear();
    sync.changes.clear();

    // The user scrubs backward to 100s, still playing. Suppressed in the moment
    // (`_applyingRemote` held by the kick).
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 100),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'the seek is suppressed while the kick holds the apply guard',
    );

    // Release the kick; it settles, sees the position moved off the target,
    // stands down, and publishes the seek so the room follows.
    video.seekGate!.complete();
    await _pumpUntil(
      () => sync.localUpdates.isNotEmpty,
      timeout: const Duration(milliseconds: 200),
    );
    expect(
      sync.localUpdates.any(
        (u) => u.position == const Duration(seconds: 100) && !u.paused,
      ),
      isTrue,
      reason: 'a stood-down kick must publish the settled local seek to the room',
    );
    expect(
      sync.changes,
      contains(true),
      reason: 'the backward seek is published as a seek (doSeek: true)',
    );
    expect(
      video.state.position,
      const Duration(seconds: 100),
      reason: 'the kick must not yank the player back to the resume target',
    );
  });

  test('a resume whose seek lands after the advance window then freezes is '
      'still re-kicked', () async {
    // Codex PR #157 review (comment 3445494454): the freeze check fired once at a
    // fixed delay and returned if the seek was still below the target. A slow seek
    // that lands AFTER that single check — then freezes at the target — was never
    // re-examined, and SyncplayClient has already adopted the peer position, so
    // steady heartbeats need not emit another resume to apply. The watch must keep
    // looking until the resume advances, proves frozen, or is superseded.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeSeekWait: const Duration(milliseconds: 5),
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    // The resume seek does not move the reported position (emitFromSeek=false),
    // so the first advance check sees the player still parked BELOW the target.
    video.emitFromSeek = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    // Let the resume path issue its seek + play (one play so far).
    await _pumpUntil(
      () => video.commands.contains('play'),
      timeout: const Duration(milliseconds: 200),
    );

    // Outlast the first advance window WITHOUT the seek having landed (still 20s).
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The slow seek finally lands at the target and the engine freezes there:
    // playing, position == target, not advancing.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );

    // A one-shot check (fired and gave up while below the target) misses this; a
    // persistent watch catches the late freeze and re-kicks (a second play).
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 400),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      greaterThanOrEqualTo(2),
      reason: 'a seek that lands after the first check then freezes must still '
          'be re-kicked',
    );
  });

  test('the kick own forward recovery is not reported to the room as a seek',
      () async {
    // Codex PR #157 review (comment 3445612966): if the kick's own seek+play
    // unfreezes playback and it advances PAST the target before the kick reads
    // the settled state, that forward progress is the watchdog's recovery — not a
    // user seek. Publishing `notifyLocalChange(doSeek: true)` here would advertise
    // our own recovery as a local seek and bounce the peer back to our frame (the
    // rewind we are fixing). A forward advance must NOT be published; the normal
    // tick stream carries the advancing position once the apply guard clears.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Frozen resume at 679 → the watchdog arms and fires.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so we can stage the recovery while it is in flight.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    // The kick's seek unfreezes playback, which creeps just past the target —
    // a small forward advance consistent with natural playback, NOT a seek.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 679500),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    sync.localUpdates.clear();
    sync.changes.clear();

    // Release the kick; it settles on a forward-advanced (recovered) player.
    video.seekGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      sync.changes,
      isNot(contains(true)),
      reason: 'the kick own forward recovery must not be sent as a local seek',
    );
    expect(
      sync.localUpdates.any(
        (u) => u.position == const Duration(milliseconds: 679500),
      ),
      isFalse,
      reason: 'a forward advance is carried by the normal heartbeat, not '
          'republished by the kick',
    );
  });

  test('a backward resume seek that lands after the window then freezes is '
      'still re-kicked', () async {
    // Codex PR #157 review (comment 3445612967): when the peer resume is a
    // BACKWARD seek, the player sits ABOVE the target until the seek lands — the
    // opposite side from a forward resume. The re-arm must not read that stale
    // ahead-of-target position as an advance and exit; otherwise a slow backward
    // seek that lands then freezes is missed (SyncplayClient has already adopted
    // the peer state, so heartbeats won't re-arm us). Re-arm while the target has
    // not been reached, on either side of it.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeSeekWait: const Duration(milliseconds: 5),
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    // Player is well AHEAD; the backward resume seek is slow to land
    // (emitFromSeek=false keeps the reported position put at 679).
    video.emitFromSeek = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 679),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Peer resumes BACKWARD to 100s; the seek does not move the position yet.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 100),
        paused: false,
        setBy: 'peer',
      ),
    );
    await _pumpUntil(
      () => video.commands.contains('play'),
      timeout: const Duration(milliseconds: 200),
    );

    // Outlast the first window with the seek still un-landed (position 679, ABOVE
    // the 100s target).
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The slow backward seek finally lands at the target and freezes there.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 100),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );

    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 400),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      greaterThanOrEqualTo(2),
      reason: 'a backward resume seek that lands late then freezes must be '
          're-kicked',
    );
  });

  test('a forward local seek during the kick is published to the room',
      () async {
    // Codex PR #157 review (comment 3445641016): the mirror of the recovery case.
    // A forward scrub during the kick is suppressed by `_onLocalState` (the kick
    // holds `_applyingRemote`); a LARGE jump past the target is a real seek, not
    // the watchdog's own creep, and the peer only follows a forward jump via the
    // explicit doSeek path. The kick must publish a forward jump that exceeds
    // plausible playback since it began (`elapsed + seekDetectThreshold`).
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      remoteResumeSeekWait: const Duration(milliseconds: 40),
    )..start();
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    // Frozen resume at 679 → the watchdog arms and fires.
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Gate the kick's seek so the forward scrub lands while the kick holds the
    // remote-apply guard.
    video.seekGate = Completer<void>();
    await _pumpUntil(
      () => video.commands.length > 2,
      timeout: const Duration(milliseconds: 200),
    );

    sync.localUpdates.clear();
    sync.changes.clear();

    // The user scrubs FORWARD to 880s (far past the 679 target), still playing —
    // a deliberate jump, well beyond anything playback could have produced.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 880),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'the seek is suppressed while the kick holds the apply guard',
    );

    // Release the kick; it settles, sees a jump beyond plausible playback, and
    // publishes it as a seek so the room follows.
    video.seekGate!.complete();
    await _pumpUntil(
      () => sync.localUpdates.isNotEmpty,
      timeout: const Duration(milliseconds: 200),
    );
    expect(
      sync.localUpdates.any(
        (u) => u.position == const Duration(seconds: 880) && !u.paused,
      ),
      isTrue,
      reason: 'a large forward seek during the kick must be published to the room',
    );
    expect(
      sync.changes,
      contains(true),
      reason: 'a forward seek is published via the explicit doSeek path',
    );
    expect(
      video.state.position,
      const Duration(seconds: 880),
      reason: 'the kick must not pull the player back to the resume target',
    );
  });

  // ── Dropped-play freeze (the 2026-06-20 field regression) ─────────────────
  //
  // A fast pause→backseek→resume can leave the reused engine SEEKED but still
  // PAUSED: the play command is dropped, so the engine never reports `playing`
  // and never advances. The original watchdog only fired on a player still
  // claiming `playing`, so this paused freeze sat forever (the friend's video
  // stuck while the advancing peer rewound in a sawtooth). The bridge must treat
  // "parked on the resume target, never started playing" as a freeze and force a
  // fresh seek+play.

  test(
    'a remote resume that lands paused and never advances is force re-kicked',
    () async {
      await bridge.dispose();
      bridge = PlaybackSyncBridge(
        video: video,
        sync: sync,
        remoteResumeAdvanceWait: const Duration(milliseconds: 30),
      )..start();
      // The resume's play is DROPPED: play() is issued but never flips the engine
      // to playing — it stays paused at the seek frame (the field freeze).
      video.emitFromPlay = false;
      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 20),
          duration: Duration(minutes: 10),
          filePath: 'a',
          fileName: 'a',
        ),
      );
      bridge.markSourceOpen('a');
      await Future<void>.delayed(Duration.zero);
      video.commands.clear();

      // Peer resumes to 679: we seek + (dropped) play. The engine stays paused at
      // 679 — never reports playing, never advances.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(seconds: 679),
          paused: false,
          setBy: 'peer',
        ),
      );
      await _pumpUntil(() => video.commands.contains('play'));
      expect(video.commands, <String>['seek:679000ms', 'play']);

      // After the advance window the bridge force re-kicks the frozen-paused
      // resume with a fresh seek+play instead of leaving the friend stuck.
      await _pumpUntil(
        () => video.commands.where((c) => c == 'play').length >= 2,
        timeout: const Duration(milliseconds: 500),
      );
      expect(
        video.commands.where((c) => c == 'play').length,
        greaterThanOrEqualTo(2),
        reason:
            'a resume that lands paused and never advances must be force re-kicked '
            'with a fresh play (the dropped-play field freeze)',
      );
    },
  );

  test('an already-playing resume that freezes is settled, not force-degraded',
      () async {
    // Codex PR #163 (comment 3447291106): when the engine is ALREADY playing and
    // a peer seek/rewind arrives, the seek emits the only `playing` tick before
    // the watchdog arms and the follow-up play() is a no-op that emits nothing. A
    // frozen clock here must be classified by the engine's LIVE `playing` status
    // (settle: re-assert play), NOT misread as a dropped play and force-degraded
    // to a republished stand-down.
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    // Already playing; play() is a no-op that emits nothing (already playing).
    video.emitFromPlay = false;
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
    video.commands.clear();
    sync.localUpdates.clear();

    // Peer rewinds/seeks to 679 while playing; the seek emits playing@679 and the
    // engine then freezes there (clock stuck, still reporting playing).
    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 400),
    );
    expect(
      video.commands.where((c) => c == 'play').length,
      greaterThanOrEqualTo(2),
      reason: 'a frozen-clock resume is re-asserted (settle), not left stuck',
    );
    // Settle re-asserts play and never republishes a stand-down; a force-degrade
    // would have published a paused:false (playing) stand-down to the room.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
      sync.localUpdates,
      isEmpty,
      reason: 'a frozen clock must not be force-degraded into a republished '
          'stand-down (it is settled by re-asserting play)',
    );
  });

  test('a force re-kicked resume stops kicking once playback advances', () async {
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 30),
    )..start();
    video.emitFromPlay = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );
    // Wait for the first force re-kick (frozen-paused → fresh play).
    await _pumpUntil(
      () => video.commands.where((c) => c == 'play').length >= 2,
      timeout: const Duration(milliseconds: 500),
    );

    // Playback now genuinely advances past the target — the kick took.
    video.push(
      const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 681),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    final playsAtRecovery = video.commands.where((c) => c == 'play').length;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(
      video.commands.where((c) => c == 'play').length,
      playsAtRecovery,
      reason: 'once playback advances past the target the watchdog must stop kicking',
    );
  });

  test('a resume that can never start is bounded and degrades to paused', () async {
    // A truly dead engine (force seek+play never takes) must not be re-kicked
    // forever. After a bounded number of attempts the bridge stands down and
    // publishes the truthful paused state so the room stops chasing a frozen
    // "playing" and both sides settle paused (the user can resume by hand).
    await bridge.dispose();
    bridge = PlaybackSyncBridge(
      video: video,
      sync: sync,
      remoteResumeAdvanceWait: const Duration(milliseconds: 20),
    )..start();
    video.emitFromPlay = false;
    video.push(
      const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 20),
        duration: Duration(minutes: 10),
        filePath: 'a',
        fileName: 'a',
      ),
    );
    bridge.markSourceOpen('a');
    await Future<void>.delayed(Duration.zero);
    video.commands.clear();
    sync.localUpdates.clear();

    sync.pushPeer(
      const PeerPlayState(
        position: Duration(seconds: 679),
        paused: false,
        setBy: 'peer',
      ),
    );

    // Let every bounded kick run out.
    await _pumpUntil(
      () => sync.localUpdates.any((u) => u.paused),
      timeout: const Duration(milliseconds: 600),
    );
    final plays = video.commands.where((c) => c == 'play').length;
    expect(
      plays,
      lessThanOrEqualTo(6),
      reason: 'force re-kicks must be bounded, never an infinite play loop',
    );
    expect(
      sync.localUpdates.any((u) => u.paused),
      isTrue,
      reason: 'a resume that can never start must degrade to a truthful paused '
          'state so the room stops chasing it',
    );
  });

  group('adoptOpenSource (live Local -> Synced switch, #252)', () {
    const open = PlaybackState(
      status: PlaybackStatus.paused,
      position: Duration(minutes: 5),
      duration: Duration(hours: 2),
      fileName: 'a.mkv',
      filePath: '/videos/a.mkv',
      opened: true,
    );

    test(
      'a bridge over an already-running player publishes nothing until it '
      'adopts the source',
      () async {
        video.push(open);
        await pumpEventQueue();
        video.push(open.copyWith(status: PlaybackStatus.playing));
        await pumpEventQueue();

        expect(
          sync.localUpdates,
          isEmpty,
          reason: 'this is the #252 regression: with no confirmed source the '
              'heartbeat reports a permanent 0:00/paused',
        );
        expect(sync.changes, isEmpty);
      },
    );

    test('adopting seeds the heartbeat and asserts the position as a seek', () async {
      video.push(open);
      await pumpEventQueue();

      bridge.adoptOpenSource('/videos/a.mkv');

      expect(sync.localUpdates.last.position, const Duration(minutes: 5));
      expect(sync.localUpdates.last.paused, isTrue);
      expect(
        sync.changes,
        [true],
        reason: 'a Syncplay room only moves on a signalled change, so the '
            'switch must assert its position with doSeek — otherwise a peer '
            'joining later converges to 0:00 instead of to us',
      );
    });

    test('adopting a playing source reports it as playing', () async {
      video.push(open.copyWith(status: PlaybackStatus.playing));
      await pumpEventQueue();

      bridge.adoptOpenSource('/videos/a.mkv');

      expect(sync.localUpdates.last.paused, isFalse);
      expect(sync.changes, [true]);
    });

    test('after adopting, local play/pause and seeks are published', () async {
      video.push(open);
      await pumpEventQueue();
      bridge.adoptOpenSource('/videos/a.mkv');
      sync.changes.clear();

      video.push(open.copyWith(status: PlaybackStatus.playing));
      await pumpEventQueue();
      expect(sync.changes, [false], reason: 'the play flip must reach the room');

      video.push(
        open.copyWith(
          status: PlaybackStatus.playing,
          position: const Duration(minutes: 20),
        ),
      );
      await pumpEventQueue();
      expect(sync.changes, [false, true], reason: 'and so must the seek');
    });

    test('adopting does not seed the bookkeeping as a jump from 0:00', () async {
      video.push(open);
      await pumpEventQueue();
      bridge.adoptOpenSource('/videos/a.mkv');
      sync.changes.clear();

      // A steady tick at the adopted position is ordinary playback, not a seek —
      // proof the detector was seeded from the player, not from zero.
      video.push(open.copyWith(position: const Duration(minutes: 5)));
      await pumpEventQueue();
      expect(sync.changes, isEmpty);
    });

    test('a source that is not the one open is not adopted', () async {
      video.push(open);
      await pumpEventQueue();

      bridge.adoptOpenSource('/videos/other.mkv');

      expect(sync.localUpdates, isEmpty);
      expect(sync.changes, isEmpty);
    });

    test('an errored source is not adopted', () async {
      video.push(open.copyWith(status: PlaybackStatus.error));
      await pumpEventQueue();

      bridge.adoptOpenSource('/videos/a.mkv');

      expect(sync.localUpdates, isEmpty);
      expect(sync.changes, isEmpty);
    });
  });

  test(
    'markSourceOpen re-applies a room seek that landed before the file opened',
    () async {
      // Product Check 6: the joiner connects first. The server's first State
      // carries doSeek, the empty player cannot hold it, then _load resets to
      // 0:00. Later heartbeats have doSeek=false, so decideFollow returns
      // apply=false and the joiner stays at 0. Re-applying on confirm is what
      // actually puts them on the room position.
      sync.pushPeer(
        const PeerPlayState(
          position: Duration(minutes: 5),
          paused: true,
          doSeek: true,
          setBy: 'host',
        ),
      );
      await pumpEventQueue();
      video.commands.clear();

      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          duration: Duration(hours: 2),
          fileName: 'a.mkv',
          filePath: '/videos/a.mkv',
          opened: true,
        ),
      );
      await pumpEventQueue();
      bridge.markSourceOpen('/videos/a.mkv');
      await pumpEventQueue();

      expect(
        video.commands,
        contains('seek:300000ms'),
        reason: 'opening the file must land the room position that arrived '
            'while the player was empty — otherwise FOLLOW apply=false at 0s',
      );
      expect(video.state.position, const Duration(minutes: 5));
    },
  );

  test(
    'markSourceOpen applies a room position FOLLOW never applied (no doSeek)',
    () async {
      // Debian SOP #6: syncplay.pl's first State to the joiner has
      // doSeek=false, both paused, local 0 / global 309. decideFollow returns
      // apply=false, so peerState never fires and _lastPeer stays null. The
      // client still cached the room on lastObservedRoomState; opening the
      // file must land it, and must not publish 0:00 as a local change.
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 309),
        paused: true,
        doSeek: false,
        setBy: 'host',
      );

      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          duration: Duration(minutes: 25),
          fileName: 'a.mkv',
          filePath: '/videos/a.mkv',
          opened: true,
        ),
      );
      await pumpEventQueue();
      video.commands.clear();
      sync.localUpdates.clear();
      sync.changes.clear();

      bridge.markSourceOpen('/videos/a.mkv');
      await pumpEventQueue();

      expect(
        video.commands,
        contains('seek:309000ms'),
        reason: 'a doSeek=false room at 309s must still land once the file opens',
      );
      expect(video.state.position, const Duration(seconds: 309));
      expect(
        sync.changes,
        isEmpty,
        reason: 'the joiner must not publish 0:00 and overwrite the room',
      );
    },
  );

  test(
    'markSourceOpen retries the room seek once duration becomes known',
    () async {
      sync.lastObservedRoomState = const PeerPlayState(
        position: Duration(seconds: 309),
        paused: true,
        doSeek: false,
        setBy: 'host',
      );
      video.emitFromSeek = false;

      video.push(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration.zero,
          duration: Duration.zero,
          fileName: 'a.mkv',
          filePath: '/videos/a.mkv',
          opened: true,
        ),
      );
      await pumpEventQueue();
      bridge.markSourceOpen('/videos/a.mkv');
      await pumpEventQueue();

      expect(video.commands, contains('seek:309000ms'));
      expect(
        video.state.position,
        Duration.zero,
        reason: 'position_guard equivalent: no duration yet, the seek cannot land',
      );
      expect(sync.changes, isEmpty);

      video.emitFromSeek = true;
      video.commands.clear();
      video.push(
        video.state.copyWith(duration: const Duration(minutes: 25)),
      );
      await pumpEventQueue();

      expect(
        video.commands,
        contains('seek:309000ms'),
        reason: 'once duration is known the rejected open seek must be retried',
      );
      expect(video.state.position, const Duration(seconds: 309));
      expect(sync.changes, isEmpty);
    },
  );
}
