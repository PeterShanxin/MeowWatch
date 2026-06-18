import 'dart:async';

import '../video/playback_state.dart';
import '../video/video_core.dart';
import 'peer_state.dart';
import 'sync_core.dart';
import 'syncplay_constants.dart';

/// Connects a [VideoCore] to a [SyncCore]. Local user changes (pause/play,
/// seek) are reported to the sync layer; remote peer states are applied to the
/// local player. An [_applyingRemote] guard prevents a remote-applied change
/// from being echoed straight back to the room.
class PlaybackSyncBridge {
  PlaybackSyncBridge({
    required this.video,
    required this.sync,
    this.seekDetectThreshold = SyncplayConstants.seekDetectThreshold,
    this.remoteApplyWindow = const Duration(milliseconds: 800),
    this.remoteSettleWindow = const Duration(seconds: 3),
    this.remoteSeekThreshold = const Duration(milliseconds: 250),
    this.remoteResumeSeekWait = const Duration(milliseconds: 200),
    this.remoteCommandWait = const Duration(milliseconds: 500),
  });

  final VideoCore video;
  final SyncCore sync;
  final Duration seekDetectThreshold;

  /// After applying a remote state we ignore local-change detection for this
  /// long. The real VideoCore emits play/pause/seek asynchronously (from the
  /// libmpv stream), so a synchronous `_applyingRemote` flag alone would be
  /// cleared before the resulting state event arrives — and the bridge would
  /// wrongly echo it back as a local change, causing the two clients to fight.
  final Duration remoteApplyWindow;

  /// Longer condition-based guard while the backend settles to a remote target.
  /// The reused media_kit/mpv engine can emit late pre-command ticks after a
  /// remote seek/pause; those must not overwrite the adopted room state.
  final Duration remoteSettleWindow;

  /// On a non-seek apply (pause/play flip or drift rewind) we only reposition
  /// if we're off by more than this — avoids latency-jitter micro-seeks.
  final Duration remoteSeekThreshold;

  /// How long a remote resume waits for the seeked position to appear before
  /// waking playback anyway. On media_kit/mpv, seek futures can stall while
  /// paused even after the position has landed; waiting forever drops the
  /// required play command.
  final Duration remoteResumeSeekWait;

  /// Remote apply commands are best-effort player requests. Their backend
  /// futures can lag behind emitted state, so the bridge never lets one future
  /// block later peer states indefinitely.
  final Duration remoteCommandWait;

  StreamSubscription<PlaybackState>? _videoSub;
  StreamSubscription<PeerPlayState>? _peerSub;
  final List<PeerPlayState> _queuedPeerStates = [];

  bool _applyingRemote = false;
  bool _drainingPeerStates = false;
  DateTime _remoteApplyUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _remoteSettleUntil = DateTime.fromMillisecondsSinceEpoch(0);
  PeerPlayState? _remoteSettleTarget;
  bool _remoteSettleRequiresPosition = false;
  DateTime _remoteFalloutUntil = DateTime.fromMillisecondsSinceEpoch(0);
  PeerPlayState? _remoteFalloutTarget;
  bool _remoteFalloutRequiresPosition = false;
  bool? _lastPaused;
  Duration _lastPosition = Duration.zero;
  DateTime _lastTick = DateTime.now();

  /// The filePath seen on the last state event. Tracks the full path (not the
  /// display name) so same-basename files from different directories are not
  /// confused. Also, the player transitions through [PlaybackStatus.loading]
  /// on every load — including a same-file reload — so either condition
  /// suffices to mark the tick as a load event rather than a user seek.
  String? _lastFilePath;

  /// The `filePath` the load coordinator (`HomeScreen._load`) has *accepted*,
  /// set via [markSourceOpen]. This is the **sole** "source confirmed" signal the
  /// heartbeat gates on. The backend reporting a source open ([isPlaybackOpen] —
  /// a real duration, or the demuxer-params `opened` latch) happens several steps
  /// *before* the coordinator accepts it: `_load` still awaits `_recordOpen`
  /// (file-size/DB) before calling [markSourceOpen] and announcing the file. If a
  /// newer load starts in that window the generation guard skips the old source's
  /// announce/chat, but a heartbeat keyed off `isPlaybackOpen` would already have
  /// paused/rewound peers for that unannounced, superseded source. Gating only on
  /// this coordinator marker keeps the heartbeat silent until the exact accepted
  /// source is confirmed — and it is what carries a live/direct stream that never
  /// reports a duration (the player pins its position at 0 via
  /// `position_guard.dart`, so the bridge cannot infer "open" from the stream
  /// alone). Re-validated against the live `filePath` on every tick, so a stale
  /// marker can't open a different source.
  String? _confirmedOpenSource;

  /// Whether the most recent *pre-open* `playing` tick (one suppressed because
  /// the source wasn't confirmed yet) came from a remote apply — a peer heartbeat
  /// playing us via [_onPeerState] — rather than local input. [markSourceOpen]
  /// re-asserts a pending play only when it was local; re-asserting a peer-driven
  /// one would stamp the peer's play as ours and could rewind/steal authorship.
  bool _preOpenPlayRemote = false;

  void start() {
    _videoSub = video.stateStream.listen(_onLocalState);
    _peerSub = sync.peerState.listen(_queuePeerState);
  }

  void _queuePeerState(PeerPlayState peer) {
    if (_drainingPeerStates) {
      _queuedPeerStates.add(peer);
      return;
    }

    _drainingPeerStates = true;
    unawaited(_drainPeerStates(peer));
  }

  Future<void> _drainPeerStates(PeerPlayState peer) async {
    var next = peer;
    while (true) {
      try {
        await _onPeerState(next);
      } catch (_) {
        // Keep later peer states flowing even if one backend command fails.
      }
      if (_queuedPeerStates.isEmpty) {
        _drainingPeerStates = false;
        return;
      }
      next = _queuedPeerStates.removeAt(0);
    }
  }

  /// Called by the load coordinator once [awaitOpenResult] has accepted [source]
  /// (including a paused live/direct stream that will never report a duration).
  /// From now on that source's ticks drive the heartbeat. We immediately re-run
  /// the current state through the gate: an accepted durationless stream may not
  /// emit another tick until the user plays, so without this the heartbeat would
  /// keep broadcasting the *previous* file's cached state until then.
  void markSourceOpen(String source) {
    _confirmedOpenSource = source;
    _onLocalState(video.state);
    // If the user pressed play while this source was still unconfirmed, that
    // play tick was suppressed (not published, no change emitted) and the replay
    // above sees it as a file-load event rather than a pause→play flip. Re-assert
    // the play as an intentional local change so the room follows our play
    // instead of a peer's stale paused heartbeat winning convergence and pausing
    // us back. Only for a *local* play: a peer-forced pre-open play
    // ([_preOpenPlayRemote]) belongs to the peer, who is already authoritative —
    // re-asserting it as ours would rewind or steal authorship. A source
    // confirmed while `paused` (the normal load) needs nothing.
    if (video.state.filePath == source &&
        video.state.status == PlaybackStatus.playing &&
        !_preOpenPlayRemote) {
      sync.notifyLocalChange(doSeek: false);
    }
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;
    final now = DateTime.now();

    // A reload re-enters `loading`; require the coordinator to re-confirm before
    // the source's ticks rejoin the heartbeat.
    if (s.status == PlaybackStatus.loading) _confirmedOpenSource = null;

    // A source feeds the heartbeat only once the load coordinator has accepted
    // *this exact* source ([markSourceOpen] → [_confirmedOpenSource]). We do NOT
    // confirm on the backend's own open signal ([isPlaybackOpen]): that fires
    // before the coordinator finishes accepting (across `_load`'s `_recordOpen`
    // await), so a superseded source could heartbeat to peers before it is ever
    // announced — see [_confirmedOpenSource]. `error` and `loading` are likewise
    // never published: a new/failing/loading source sits at position 0, and
    // broadcasting that would make a watching peer pause/rewind for a load that
    // may never land (e.g. an unreachable URL). Keep the seek-detection
    // bookkeeping so the next real tick isn't read as a seek, but don't publish
    // until confirmed.
    final source = s.filePath;
    final confirmed = source != null && source == _confirmedOpenSource;
    final settlingRemote = _isSettlingRemoteState(s, now);
    final lateRemoteFallout = _isLateRemoteFallout(s, now);

    if (!confirmed ||
        s.status == PlaybackStatus.loading ||
        s.status == PlaybackStatus.error) {
      // Record whether a pre-open *play* was remote-applied (peer heartbeat,
      // inside the remote-apply window) vs local, so markSourceOpen re-asserts
      // only a genuinely local play. Non-play ticks clear it — nothing to assert.
      _preOpenPlayRemote =
          s.status == PlaybackStatus.playing &&
          (_applyingRemote ||
              now.isBefore(_remoteApplyUntil) ||
              settlingRemote ||
              lateRemoteFallout);
      _lastFilePath = s.filePath;
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = now;
      return;
    }

    final suppressed =
        _applyingRemote ||
        now.isBefore(_remoteApplyUntil) ||
        settlingRemote ||
        lateRemoteFallout;

    // Feed local playback to the heartbeat only when this tick is NOT fallout
    // from a remote apply. SyncplayClient already adopts the peer target before
    // emitting peerState; overwriting that cache with a delayed/stale media_kit
    // tick during the suppression window makes the next heartbeat report the
    // pre-apply position, and the peer then rewinds/seeks to it — the post-0.28.0
    // sync thrash, surfaced by the reused engine (#137) emitting more out-of-order
    // ticks. The seek-detection bookkeeping below still runs so the next real tick
    // isn't misread as a seek.
    if (!suppressed) {
      sync.updateLocalState(position: s.position, paused: paused);
    }

    // Suppress seek detection on a file-load event: a different filePath means a
    // new (or different) file was opened — catching the position-reset-to-0 that
    // would otherwise look like a seek. (The `loading` tick is already handled
    // above.)
    final isLoadEvent = s.filePath != _lastFilePath;
    if (isLoadEvent) {
      _lastFilePath = s.filePath;
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = DateTime.now();
      return;
    }

    if (suppressed) {
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = DateTime.now();
      return;
    }

    // Seek detection: compare actual position to where natural playback would
    // have carried us since the last tick. A real seek can also produce a
    // transient play/pause flip from the backend, so a large position jump wins.
    final hadPreviousTick = _lastPaused != null;
    final elapsed = (_lastPaused == false)
        ? now.difference(_lastTick)
        : Duration.zero;
    final expected = _lastPosition + elapsed;
    final diff = (s.position - expected).abs();
    if (hadPreviousTick && diff > seekDetectThreshold) {
      sync.notifyLocalChange(doSeek: true);
    } else if (hadPreviousTick && paused != _lastPaused) {
      sync.notifyLocalChange(doSeek: false);
    }

    _lastPaused = paused;
    _lastPosition = s.position;
    _lastTick = now;
  }

  bool _isSettlingRemoteState(PlaybackState s, DateTime now) {
    final target = _remoteSettleTarget;
    if (target == null) return false;
    if (_matchesRemoteTarget(s, target)) {
      _remoteFalloutTarget = target;
      _remoteFalloutRequiresPosition = _remoteSettleRequiresPosition;
      _remoteFalloutUntil = now.add(remoteApplyWindow + remoteCommandWait);
      _remoteSettleTarget = null;
      _remoteSettleRequiresPosition = false;
      return true;
    }
    if (now.isBefore(_remoteSettleUntil)) return true;
    _remoteSettleTarget = null;
    _remoteSettleRequiresPosition = false;
    return false;
  }

  bool _isLateRemoteFallout(PlaybackState s, DateTime now) {
    final target = _remoteFalloutTarget;
    if (target == null) return false;
    if (!now.isBefore(_remoteFalloutUntil)) {
      _remoteFalloutTarget = null;
      _remoteFalloutRequiresPosition = false;
      return false;
    }

    final paused = s.status != PlaybackStatus.playing;
    if (paused != target.paused) return true;
    if (!_remoteFalloutRequiresPosition) return false;
    if (target.paused) {
      return (s.position - target.position).abs() > remoteSeekThreshold;
    }
    return s.position < target.position - remoteSeekThreshold;
  }

  bool _matchesRemoteTarget(PlaybackState s, PeerPlayState target) {
    final paused = s.status != PlaybackStatus.playing;
    if (paused != target.paused) return false;
    if (!_remoteSettleRequiresPosition) return true;
    return (s.position - target.position).abs() <= remoteSeekThreshold;
  }

  Future<void> _waitForCommand(Future<void> command) async {
    try {
      await command.timeout(remoteCommandWait);
    } catch (_) {
      // Player command futures are not the source of truth here; backend state
      // events are. Keep peer-state draining alive even if media_kit is late or
      // reports a transient command failure.
    }
  }

  Future<bool> _waitForPosition(Duration position) async {
    if ((video.state.position - position).abs() <= remoteSeekThreshold) {
      return true;
    }

    final completer = Completer<bool>();
    late final StreamSubscription<PlaybackState> sub;
    Timer? timer;

    void complete(bool value) {
      if (completer.isCompleted) return;
      timer?.cancel();
      unawaited(sub.cancel());
      completer.complete(value);
    }

    sub = video.stateStream.listen((state) {
      if ((state.position - position).abs() <= remoteSeekThreshold) {
        complete(true);
      }
    });
    timer = Timer(remoteResumeSeekWait, () => complete(false));

    return completer.future;
  }

  Future<void> _onPeerState(PeerPlayState peer) async {
    // The SyncCore only emits states that genuinely require a local change
    // (the convergence/anti-fight decision lives in decideFollow), so the
    // bridge applies each one: align position, then match play/pause.
    _applyingRemote = true;
    _remoteApplyUntil = DateTime.now().add(remoteApplyWindow);
    try {
      // Seek on an explicit peer seek, when a peer pauses (frame inspection
      // needs the exact paused frame), or when we've drifted materially from
      // the room. Resume/play flips stay thresholded so network jitter does not
      // cause a visible micro-jump during normal watching.
      final drift = (peer.position - video.state.position).abs();
      final shouldSeek =
          peer.doSeek ||
          (peer.paused && drift > Duration.zero) ||
          drift > remoteSeekThreshold;
      _remoteSettleTarget = peer;
      _remoteSettleRequiresPosition = shouldSeek;
      _remoteSettleUntil = DateTime.now().add(remoteSettleWindow);
      _remoteFalloutTarget = null;
      _remoteFalloutRequiresPosition = false;

      Future<void>? seekDone;
      if (shouldSeek) {
        seekDone = video.seek(peer.position);
        unawaited(_waitForCommand(seekDone));
      }

      Future<void>? pauseDone;
      if (!peer.paused) {
        var landedBeforePlay = true;
        if (shouldSeek) {
          landedBeforePlay = await _waitForPosition(peer.position);
        }
        await _waitForCommand(video.play());
        if (shouldSeek && !landedBeforePlay) {
          unawaited(_waitForCommand(video.seek(peer.position)));
        }
        seekDone = null;
      } else {
        pauseDone = video.pause();
      }
      if (seekDone != null) {
        await _waitForCommand(seekDone);
      }
      if (pauseDone != null) {
        await _waitForCommand(pauseDone);
      }
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> dispose() async {
    await _videoSub?.cancel();
    await _peerSub?.cancel();
  }
}
