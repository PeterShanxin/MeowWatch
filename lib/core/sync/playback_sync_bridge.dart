import 'dart:async';

import '../debug/app_log.dart';
import '../video/playback_state.dart';
import '../video/source_announce.dart';
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
    this.remoteResumeAdvanceWait = const Duration(seconds: 2),
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

  /// After applying a remote resume we expect playback to actually start moving.
  /// If, within this window, the player still reports `playing` but its position
  /// has not advanced past the resume target, the engine is frozen (a fast
  /// pause→seek→resume can leave media_kit/mpv unpaused-but-stalled at the seek
  /// frame). The bridge then re-kicks the resume (seek+play). Long enough not to
  /// trip on a slow decode start, far shorter than the ~60s freezes seen in the
  /// field.
  final Duration remoteResumeAdvanceWait;

  StreamSubscription<PlaybackState>? _videoSub;
  StreamSubscription<PeerPlayState>? _peerSub;
  StreamSubscription<PlaybackState>? _resumeSeekSub;
  /// Last room state the bridge was told to apply. The product join order
  /// (connect, then load) delivers the server's first State while the
  /// player is still empty; `_load` then resets to 0:00 and later heartbeats
  /// have `doSeek=false`, so [decideFollow] returns apply=false. Remembering
  /// the room here — and [SyncCore.lastObservedRoomState] even when FOLLOW
  /// never applied — lets [markSourceOpen] land it once the file is actually
  /// open.
  PeerPlayState? _lastPeer;
  /// True while [markSourceOpen] has asked the player to land on [_lastPeer]
  /// (or [SyncCore.lastObservedRoomState]) and that seek has not yet stuck.
  /// Outbound publishes stay suppressed so a joiner at 0:00 cannot overwrite
  /// the room.
  bool _awaitingOpenSeek = false;
  /// One retry is reserved for the case where the first open seek ran before
  /// the player reported a duration: media_kit's position guard drops non-zero
  /// ticks until duration is known, so the playhead would otherwise stay at 0.
  bool _openSeekNeedsDuration = false;
  Timer? _resumeSeekTimer;
  Timer? _advanceWatchTimer;
  final List<PeerPlayState> _queuedPeerStates = [];

  bool _applyingRemote = false;
  bool _drainingPeerStates = false;
  // Set once [dispose] runs. An in-flight stalled-resume kick whose seek is
  // still awaiting must not seek/play afterwards: the bridge is gone and its
  // pooled VideoCore may already be driving the lobby or the next room.
  bool _disposed = false;
  // Bumped each time a peer state is applied. A stalled-resume kick captures the
  // sequence of the resume that spawned it and bails before it would override a
  // newer peer state that landed while its seek was still in flight.
  int _peerStateSeq = 0;

  // Bounds the force-kicks for a dropped-play freeze (the 2026-06-20 field
  // regression: the play command is lost and the engine sits PAUSED at the seek
  // frame). The watchdog reads the engine's live status when it fires — `paused`
  // at the target means the play was dropped (force a fresh seek+play), `playing`
  // at the target means a frozen clock (the gentler settle path) — so no history
  // flag is needed. [_kicksLeft] just stops a truly dead engine from being
  // force-kicked forever; it degrades to a truthful paused state instead.
  int _kicksLeft = 0;
  DateTime _remoteApplyUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _remoteSettleUntil = DateTime.fromMillisecondsSinceEpoch(0);
  PeerPlayState? _remoteSettleTarget;
  bool _remoteSettleRequiresPosition = false;
  DateTime _remoteFalloutUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _remoteFalloutStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
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

  /// Adopt a source that was already open *before this bridge existed*.
  ///
  /// The live Local -> Synced switch (#252) builds the Syncplay trio around a
  /// player that is already running, so [markSourceOpen] — the only other way a
  /// source is ever confirmed — fired long ago, against a bridge that no longer
  /// exists. Without this the fresh bridge sits at `_confirmedOpenSource == null`
  /// and suppresses every outbound publish: the new client heartbeats a permanent
  /// `0:00 / paused` and none of our play/pause/seek is ever announced. The room
  /// can still drive us (the peer-state path never consults the marker), so the
  /// session ends up drivable but not driving — the exact asymmetry reported in
  /// #252.
  ///
  /// Adoption also does one thing a plain [markSourceOpen] cannot: it publishes
  /// the current position as an explicit local change (`doSeek`). A Syncplay
  /// room's authoritative playstate only moves when a client *signals* a change,
  /// so without the assert the room would sit at 0:00 with no setter and a peer
  /// joining later would converge to 0:00 rather than to us. That is the same
  /// state a synced-from-the-start session publishes when its Continue-Watching
  /// resume seek lands before the room is joined — precisely the equivalence the
  /// switch is supposed to deliver.
  void adoptOpenSource(String source) {
    final s = video.state;
    // Reuse the connect-time announce gate: adopt only a source that is still
    // the one the load coordinator accepted and has not since errored.
    if (!canAnnounceOnConnect(
      currentPath: s.filePath,
      acceptedPath: source,
      status: s.status,
    )) {
      return;
    }
    final paused = s.status != PlaybackStatus.playing;
    _confirmedOpenSource = source;
    // Seed the seek-detection bookkeeping from where the player already is, so
    // the next tick reads as ordinary playback rather than a jump from 0:00.
    _lastFilePath = s.filePath;
    _lastPaused = paused;
    _lastPosition = s.position;
    _lastTick = DateTime.now();
    _preOpenPlayRemote = false;
    sync.updateLocalState(position: s.position, paused: paused);
    sync.notifyLocalChange(doSeek: true);
  }

  void _queuePeerState(PeerPlayState peer) {
    _lastPeer = peer;
    if (_drainingPeerStates) {
      _queuedPeerStates.add(peer);
      return;
    }

    _drainingPeerStates = true;
    unawaited(_drainPeerStates(peer));
  }

  Future<void> _drainPeerStates(PeerPlayState peer) async {
    // EXCEPTION SAFETY IS LOAD-BEARING HERE. `_drainingPeerStates` gates ALL
    // future peer-state delivery — a state that arrives while it is true just
    // queues (see [_queuePeerState]). So if this drain ever exits WITHOUT clearing
    // the flag, the bridge silently stops applying sync for the rest of the
    // session: the engine drifts free while the room still thinks we are in sync.
    // That is exactly the 2026-06-21 field freeze — a throwing diagnostic logger
    // (an IOSink in a transient bad state during a rapid pause/seek/resume burst)
    // escaped the per-error `appLog` below, unwound this loop, and left the flag
    // stuck true forever. Two guards make that impossible: the flag is reset in a
    // `finally` no throw can skip, and the per-error log is itself wrapped so a
    // failing logger can never abort the drain.
    try {
      var next = peer;
      while (true) {
        try {
          await _onPeerState(next);
        } catch (e, st) {
          // Keep later peer states flowing even if one backend command fails —
          // but never SILENTLY: a dropped seek/play here is exactly the
          // resume-freeze root cause, and swallowing it left the field bug
          // invisible for months. The log itself must never escape (above).
          try {
            appLog('sync bridge: peer-state apply error: $e\n$st');
          } catch (_) {
            // A logging failure must not unwind the drain and leak the flag.
          }
        }
        if (_queuedPeerStates.isEmpty) return;
        next = _queuedPeerStates.removeAt(0);
      }
    } finally {
      _drainingPeerStates = false;
    }
  }

  /// Called by the load coordinator once [awaitOpenResult] has accepted [source]
  /// (including a paused live/direct stream that will never report a duration).
  /// From now on that source's ticks drive the heartbeat. If the room already
  /// sent a playstate (the joiner connected before this load), re-apply it so
  /// the file opens at the room position rather than 0:00. Otherwise replay the
  /// current local state: an accepted durationless stream may not emit another
  /// tick until the user plays, so without this the heartbeat would keep
  /// broadcasting the *previous* file's cached state until then.
  void markSourceOpen(String source) {
    _confirmedOpenSource = source;
    final pending = _roomToApply();
    if (pending != null && _roomDiffersFromLocal(pending, video.state)) {
      // The room already told us where to be — usually while this source was
      // still loading, and often via heartbeats with doSeek=false that
      // decideFollow never applied. Later heartbeats will not catch us up, so
      // without this re-apply a joiner that loads after connect stays at 0:00
      // (Check 6). Skip the local replay: publishing 0:00/paused here would
      // pause the room and stamp the joiner as setBy.
      _applyRoomOnOpen(pending);
      return;
    }
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

  PeerPlayState? _roomToApply() {
    final pending = _lastPeer ?? sync.lastObservedRoomState;
    if (pending == null || pending.setBy == null) return null;
    return pending;
  }

  bool _roomDiffersFromLocal(PeerPlayState room, PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;
    if (room.paused != paused) return true;
    return (room.position - s.position).abs() > remoteSeekThreshold;
  }

  void _applyRoomOnOpen(PeerPlayState pending) {
    _awaitingOpenSeek = true;
    _openSeekNeedsDuration =
        pending.position > Duration.zero && video.state.duration <= Duration.zero;
    appLog(
      'sync bridge: apply room pos=${pending.positionSeconds}s '
      'setBy=${pending.setBy} on source open',
    );
    _queuePeerState(
      PeerPlayState(
        position: pending.position,
        paused: pending.paused,
        doSeek: true,
        setBy: pending.setBy,
      ),
    );
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;
    final now = DateTime.now();

    // A reload re-enters `loading`; require the coordinator to re-confirm before
    // the source's ticks rejoin the heartbeat.
    if (s.status == PlaybackStatus.loading) {
      _confirmedOpenSource = null;
      _awaitingOpenSeek = false;
      _openSeekNeedsDuration = false;
    }

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

    if (_awaitingOpenSeek && confirmed) {
      final room = _roomToApply();
      if (room == null || !_roomDiffersFromLocal(room, s)) {
        _awaitingOpenSeek = false;
        _openSeekNeedsDuration = false;
        // Landed: feed the heartbeat the room position, but do not advertise a
        // local change — that would stamp the joiner as setBy at 0:00 or at
        // the catch-up frame.
        sync.updateLocalState(position: s.position, paused: paused);
        _lastFilePath = s.filePath;
        _lastPaused = paused;
        _lastPosition = s.position;
        _lastTick = now;
        return;
      }
      if (_openSeekNeedsDuration && s.duration > Duration.zero) {
        _openSeekNeedsDuration = false;
        _applyRoomOnOpen(room);
      } else if (s.duration <= Duration.zero &&
          s.opened &&
          !_openSeekNeedsDuration) {
        // Durationless live/direct: the room position cannot land. Stop
        // waiting so we do not mute the heartbeat forever.
        _awaitingOpenSeek = false;
      }
      if (_awaitingOpenSeek) {
        _lastFilePath = s.filePath;
        _lastPaused = paused;
        _lastPosition = s.position;
        _lastTick = now;
        return;
      }
    }

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
      _remoteFalloutStartedAt = now;
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
    final progressSlop = seekDetectThreshold > remoteSeekThreshold
        ? seekDetectThreshold
        : remoteSeekThreshold;
    final plausibleProgress =
        now.difference(_remoteFalloutStartedAt) + progressSlop;
    final minPosition = target.position - remoteSeekThreshold;
    final maxPosition = target.position + plausibleProgress;
    return s.position < minPosition || s.position > maxPosition;
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

  /// Wait until the player reports `playing` again, up to [remoteResumeSeekWait].
  /// The stalled-resume kick's own seek can briefly report `paused` as backend
  /// fallout; only a pause that PERSISTS past this settle is a real user/peer
  /// stand-down. Returns the moment `playing` is observed, or after the window.
  Future<void> _waitForPlaying() async {
    if (video.state.status == PlaybackStatus.playing) return;

    final completer = Completer<void>();
    late final StreamSubscription<PlaybackState> sub;
    Timer? timer;

    void complete() {
      if (completer.isCompleted) return;
      timer?.cancel();
      unawaited(sub.cancel());
      completer.complete();
    }

    sub = video.stateStream.listen((state) {
      if (state.status == PlaybackStatus.playing) complete();
    });
    timer = Timer(remoteResumeSeekWait, complete);

    return completer.future;
  }

  void _cancelResumeSeek() {
    _resumeSeekTimer?.cancel();
    _resumeSeekTimer = null;
    unawaited(_resumeSeekSub?.cancel());
    _resumeSeekSub = null;
  }

  void _seekWhenPlaying(Duration position) {
    _cancelResumeSeek();
    if (video.state.status == PlaybackStatus.playing) {
      unawaited(_waitForCommand(video.seek(position)));
      return;
    }

    late final StreamSubscription<PlaybackState> sub;
    Timer? timer;

    void cancelWait() {
      timer?.cancel();
      timer = null;
      if (identical(_resumeSeekSub, sub)) {
        _resumeSeekSub = null;
        _resumeSeekTimer = null;
      }
      unawaited(sub.cancel());
    }

    sub = video.stateStream.listen((state) {
      if (state.status != PlaybackStatus.playing) return;
      cancelWait();
      unawaited(_waitForCommand(video.seek(position)));
    });
    timer = Timer(remoteSettleWindow, cancelWait);
    _resumeSeekSub = sub;
    _resumeSeekTimer = timer;
  }

  void _cancelAdvanceWatch() {
    _advanceWatchTimer?.cancel();
    _advanceWatchTimer = null;
  }

  /// How many [remoteResumeAdvanceWait] windows the stalled-resume watch re-arms
  /// across while the resume seek has not landed. Bounds the watch so a seek that
  /// never lands cannot keep it alive forever, while giving a slow-but-real seek
  /// several windows to arrive and reveal a freeze.
  static const int _maxAdvanceChecks = 4;

  /// How many times a never-started resume (the dropped-play freeze) is force
  /// re-kicked with a fresh seek+play before standing down to a truthful paused
  /// state. Kept small on purpose: a genuine dropped play recovers on the FIRST
  /// nudge (this is the engine equivalent of the user's pause-wait-resume
  /// workaround, which takes in one go once the rapid churn has settled), so two
  /// attempts is ample for recovery. The cap also bounds the one case the
  /// paused-at-target shape cannot tell apart from a dropped play — a user who
  /// pauses within `remoteSeekThreshold` of a peer resume, before the clock
  /// advances (the same sub-threshold ambiguity tracked in #161). There the force
  /// re-kick briefly fights the real pause; a small cap keeps that to ~one short
  /// window before the watchdog stands down and lets the pause propagate.
  static const int _maxKicks = 2;

  /// Arm the stalled-resume watchdog after applying a remote resume. A fast
  /// pause→seek→resume (three peer states inside one handshake) can leave the
  /// reused media_kit/mpv engine reporting `playing` while its clock is frozen
  /// at the seek frame — the friend looks stuck and the advancing peer gets
  /// rewound.
  ///
  /// The freeze signature is the player still claiming to be playing while
  /// parked on the resume [target]. Keying on proximity to the target — rather
  /// than the position relative to where the resume was applied — is what keeps
  /// the watchdog correct across every interleaving: healthy playback advances
  /// past the target; a local user seek moves the position elsewhere; a slow
  /// seek that has not landed yet sits below it; and a slow seek that lands then
  /// freezes parks exactly on it. Only the last is stuck, so only a player on
  /// the target is re-kicked (to that same target, which is therefore a no-op
  /// re-assert that cannot stomp a position). Durationless live streams (whose
  /// position is intentionally pinned) and resumes superseded by a newer peer
  /// state are skipped.
  ///
  /// The check re-arms while the seek is still below the target, so a slow seek
  /// that lands *after* the first window — then freezes on it — is still caught
  /// instead of being missed once and forgotten (Codex PR #157, comment
  /// 3445494454). SyncplayClient has already adopted the peer position, so steady
  /// heartbeats need not emit another resume to re-arm us; the watch must outlast
  /// the landing on its own. The re-arm is bounded so a never-landing seek (left
  /// to the resume path's own re-seek and the next peer state) cannot spin
  /// forever.
  void _watchResumeAdvances(Duration target, int seq) {
    _cancelAdvanceWatch();
    _scheduleAdvanceCheck(target, seq, _maxAdvanceChecks);
  }

  /// One [remoteResumeAdvanceWait] tick of the stalled-resume watch; re-arms
  /// itself (bounded by [checksLeft]) while the resume seek has not landed yet.
  void _scheduleAdvanceCheck(Duration target, int seq, int checksLeft) {
    _advanceWatchTimer = Timer(remoteResumeAdvanceWait, () {
      _advanceWatchTimer = null;
      // The bridge was torn down (the cancel raced the timer firing), or a newer
      // peer state has been applied since this resume and owns the current
      // intent — either way this watch is stale.
      if (_disposed || seq != _peerStateSeq) return;
      final s = video.state;
      // A durationless live/direct stream intentionally holds its reported
      // position (position_guard rejects positive positions without a
      // duration), so a non-advancing position is normal there, not a frozen
      // resume. Re-issuing seek(0)+play on a live URL can jump or stall it, so
      // only the stalled-resume kick applies to sources with a real duration.
      if (s.duration <= Duration.zero) return;
      final delta = s.position - target;
      final atTarget = delta.abs() <= remoteSeekThreshold;
      // Parked on the resume target and not advancing is the freeze. The engine's
      // LIVE status when the watchdog fires tells the two shapes apart, with no
      // history flag: `paused` at the target means the play command was dropped
      // (the 2026-06-20 field freeze — force a fresh seek+play), `playing` at the
      // target means a frozen clock (the gentler settle path).
      if (atTarget) {
        final droppedPlay = s.status != PlaybackStatus.playing;
        // Exhausted the bounded force-kicks and the engine is STILL paused at the
        // target — and this check is a full advance window after the last play, so
        // a late recovery would already have shown as advancement above. Only now
        // stand down to a truthful paused state so the room stops chasing a frozen
        // "playing" (Codex 3447272582).
        if (droppedPlay && _kicksLeft <= 0) {
          sync.updateLocalState(position: s.position, paused: true);
          sync.notifyLocalChange(doSeek: false);
          return;
        }
        unawaited(_kickStalledResume(target, seq, droppedPlay));
        return;
      }
      // Off the target: the resume seek has not landed yet — a forward resume sits
      // BELOW the target, a backward one ABOVE it — or playback has genuinely
      // advanced past it. Re-arm regardless of side and of play/pause (Codex
      // comment 3445612967), bounded, so a late landing that then freezes is still
      // caught while healthy playback simply exhausts the bound without a kick.
      if (checksLeft > 1) {
        _scheduleAdvanceCheck(target, seq, checksLeft - 1);
      }
    });
  }

  /// Un-stick a frozen remote resume by re-issuing seek+play from where the
  /// player is now. By the time this fires the rapid pause/seek churn has long
  /// settled (this is the engine equivalent of the user's pause-wait-resume
  /// workaround), so the fresh play takes. Runs inside the remote-apply guard so
  /// the kick is never echoed back to the room as a local change.
  Future<void> _kickStalledResume(Duration target, int seq, bool droppedPlay) async {
    if (_disposed) return;
    final kickStart = DateTime.now();
    _applyingRemote = true;
    _remoteApplyUntil = kickStart.add(remoteApplyWindow);
    try {
      // Re-seek to the peer's resume target. By the time the watchdog fires the
      // player is already parked on `target` (the freeze signature), so this is
      // a no-op reposition whose real job is to nudge the frozen demuxer; using
      // `target` rather than a re-read of the live position keeps it a no-op even
      // against the threshold slop. Crucially the seek is issued synchronously in
      // the same task as the watchdog's seq check, so it can never be ordered
      // after a newer peer state: one that lands while this seek is in flight
      // issues its own later seek (which wins) and bumps `_peerStateSeq`.
      await _waitForCommand(video.seek(target));
      if (_disposed || seq != _peerStateSeq) return;

      if (droppedPlay) {
        // The engine was PAUSED at the target when the watchdog fired — the play
        // command was dropped and the resume never took (the field freeze). There
        // is no real local action to respect, so FORCE the play. Bounded by
        // [_kicksLeft]: always re-arm to confirm it actually advances now; once the
        // attempts run out, the watchdog check stands down to a truthful paused
        // state so the room stops chasing a frozen "playing".
        await _waitForCommand(video.play());
        if (_disposed || seq != _peerStateSeq) return;
        _kicksLeft -= 1;
        // Always re-arm — even after the LAST attempt — so the play has a full
        // advance window to prove it worked before we ever stand down. The next
        // watchdog check publishes the paused fallback only if it STILL sees no
        // advancement (Codex 3447272582); a recovery that starts late shows up as
        // advancement there and is left to normal sync.
        _watchResumeAdvances(target, seq);
        return;
      }

      // The engine was PLAYING at the target — a frozen clock, or a real local
      // action the user took during the resume. This settle path resolves the
      // resume and never re-arms.
      // Don't judge intent in the instant after our own seek: that seek can
      // transiently report `paused` (backend fallout), which must not be mistaken
      // for a real pause. Wait for the truth to settle — a transient clears back
      // to `playing`; a genuine user/peer pause persists.
      await _waitForPlaying();
      if (_disposed || seq != _peerStateSeq) return;
      // Only one settled shape is the freeze we re-assert play on: still `playing`
      // AND still parked on the resume target. Anything else means the truth
      // settled to a real local action the user took during the kick — a pause, or
      // a seek away from the target — which `_onLocalState` SUPPRESSED because the
      // kick holds `_applyingRemote`. A still player may never re-emit it, so the
      // room would otherwise keep the stale peer-driven "playing"/position. Stand
      // down and publish the settled local state so the room follows it (a beat
      // later) instead of fighting a state the user has left — the minimal unstick
      // hands back to normal sync. (A disposed/superseded kick already returned.)
      final s = video.state;
      final playing = s.status == PlaybackStatus.playing;
      final delta = s.position - target;
      final atTarget = delta.abs() <= remoteSeekThreshold;
      if (playing && atTarget) {
        // The freeze we came to fix: still parked on the target. Re-assert play.
        await _waitForCommand(video.play());
        return;
      }
      if (playing && delta > remoteSeekThreshold) {
        // Player is ahead of the target. Two very different causes look identical
        // in a single snapshot, so tell them apart by magnitude:
        //  - the kick's own seek+play unfroze the engine and natural playback
        //    crept forward (RECOVERY) — publishing this with doSeek would
        //    advertise our own recovery as a local seek and bounce the peer back
        //    to our frame, the very rewind we are fixing (Codex 3445612966); or
        //  - the user scrubbed FORWARD during the kick (a real SEEK the peer only
        //    follows via the explicit doSeek path: Codex 3445641016).
        // Natural playback since the kick began can carry us at most `elapsed`
        // past the target, so a jump beyond `elapsed + seekDetectThreshold` is a
        // deliberate forward seek; anything within it is recovery.
        final elapsed = DateTime.now().difference(kickStart);
        if (delta <= elapsed + seekDetectThreshold) {
          // Recovery — leave it to the ongoing tick stream + `_onLocalState`,
          // which broadcast the advancing position once the apply guard clears.
          return;
        }
        // A real forward seek — fall through to publish it with doSeek.
      }
      // The settled truth is a real local action the kick must not fight: a pause
      // (a still player that may never re-emit), a seek BACK below the target, or
      // a forward seek past plausible playback — whose doSeek the apply-window
      // bookkeeping swallowed. `_onLocalState` suppressed it while the kick held
      // `_applyingRemote`, so publish it here — the room follows a beat later
      // instead of keeping the stale peer-driven "playing"/position.
      sync.updateLocalState(position: s.position, paused: !playing);
      // A position that moved off the target is a user seek — peers only follow a
      // jump (back OR forward) via the explicit doSeek path. A pause still on the
      // target is a plain play/pause flip.
      sync.notifyLocalChange(doSeek: !atTarget);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _onPeerState(PeerPlayState peer) async {
    // The SyncCore only emits states that genuinely require a local change
    // (the convergence/anti-fight decision lives in decideFollow), so the
    // bridge applies each one: align position, then match play/pause.
    final seq = ++_peerStateSeq;
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
      _cancelResumeSeek();

      Future<void>? seekDone;
      if (shouldSeek) {
        seekDone = video.seek(peer.position);
        unawaited(_waitForCommand(seekDone));
      }

      Future<void>? pauseDone;
      if (!peer.paused) {
        // Arm the advance watchdog FIRST, before the fragile seek-wait/play. The
        // field freeze dropped the play command BEFORE the watchdog was armed
        // (the old arming sat AFTER play()), leaving the resume with no recovery
        // at all. Arming up front guarantees a frozen resume is always re-kicked,
        // however the play is lost. Reset the per-resume force-kick budget too.
        _kicksLeft = _maxKicks;
        _watchResumeAdvances(peer.position, seq);
        var landedBeforePlay = true;
        if (shouldSeek) {
          // Best-effort wait for the seek to land; never let it skip the play.
          try {
            landedBeforePlay = await _waitForPosition(peer.position);
          } catch (_) {
            landedBeforePlay = false;
          }
        }
        await _waitForCommand(video.play());
        if (shouldSeek && !landedBeforePlay) {
          _seekWhenPlaying(peer.position);
        }
        seekDone = null;
      } else {
        pauseDone = video.pause();
        // A deliberate pause is not a stalled resume — stand the watchdog down.
        _cancelAdvanceWatch();
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
    _disposed = true;
    _cancelAdvanceWatch();
    _resumeSeekTimer?.cancel();
    await _resumeSeekSub?.cancel();
    await _videoSub?.cancel();
    await _peerSub?.cancel();
  }
}
