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
    this.remoteSeekThreshold = const Duration(milliseconds: 250),
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

  /// On a non-seek apply (pause/play flip or drift rewind) we only reposition
  /// if we're off by more than this — avoids latency-jitter micro-seeks.
  final Duration remoteSeekThreshold;

  StreamSubscription<PlaybackState>? _videoSub;
  StreamSubscription<PeerPlayState>? _peerSub;

  bool _applyingRemote = false;
  DateTime _remoteApplyUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _lastPaused;
  Duration _lastPosition = Duration.zero;
  DateTime _lastTick = DateTime.now();

  /// The filePath seen on the last state event. Tracks the full path (not the
  /// display name) so same-basename files from different directories are not
  /// confused. Also, the player transitions through [PlaybackStatus.loading]
  /// on every load — including a same-file reload — so either condition
  /// suffices to mark the tick as a load event rather than a user seek.
  String? _lastFilePath;

  /// Whether the current source has been confirmed open for the heartbeat. A
  /// live/direct stream may *never* report a duration, so gating each tick on
  /// [isPlaybackOpen] alone would mute it forever even after [VideoCore.load]
  /// accepted it. Instead we latch "open" per source on the first positive
  /// evidence — a real duration / `ended`, or playback that has advanced past
  /// zero (frames are flowing) — and from then on publish its ticks. Cleared
  /// when the source changes or reloads so a new/failing load can't ride the
  /// previous source's latch.
  bool _sourceOpen = false;

  void start() {
    _videoSub = video.stateStream.listen(_onLocalState);
    _peerSub = sync.peerState.listen(_onPeerState);
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;

    // A new source (filePath change) or a reload (`loading`) must re-prove that
    // it opened before its ticks rejoin the heartbeat — clear the open latch.
    if (s.filePath != _lastFilePath || s.status == PlaybackStatus.loading) {
      _sourceOpen = false;
    }
    // Latch the current source open on positive evidence: a real duration /
    // `ended` ([isPlaybackOpen]), or playback advanced past zero — a live/direct
    // stream with no duration still delivers frames. Once latched, its later
    // paused/playing ticks keep driving the heartbeat (mirrors the live-stream
    // acceptance in `awaitOpenResult`).
    if (isPlaybackOpen(s) ||
        (s.status == PlaybackStatus.playing && s.position > Duration.zero)) {
      _sourceOpen = true;
    }

    // Until the source is confirmed open — and never for an `error` — keep it out
    // of the outgoing heartbeat: a new/failing/loading source sits at position 0,
    // and the zero-duration pre-error tick a bad source emits the instant
    // `open()` returns sits there too. Publishing any of them would make a
    // watching peer pause/rewind for a load that may never land (e.g. an
    // unreachable URL). Keep the seek-detection bookkeeping so the next real tick
    // isn't read as a seek, but don't publish until then.
    if (!_sourceOpen || s.status == PlaybackStatus.error) {
      _lastFilePath = s.filePath;
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = DateTime.now();
      return;
    }

    // Feed the latest playable position to the sync layer for its heartbeat.
    sync.updateLocalState(position: s.position, paused: paused);

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

    final suppressed =
        _applyingRemote || DateTime.now().isBefore(_remoteApplyUntil);
    if (suppressed) {
      _lastPaused = paused;
      _lastPosition = s.position;
      _lastTick = DateTime.now();
      return;
    }

    // Pause/play transition.
    if (_lastPaused != null && paused != _lastPaused) {
      sync.notifyLocalChange(doSeek: false);
    } else {
      // Seek detection: compare actual position to where natural playback
      // would have carried us since the last tick.
      final now = DateTime.now();
      final elapsed =
          (_lastPaused == false) ? now.difference(_lastTick) : Duration.zero;
      final expected = _lastPosition + elapsed;
      final diff = (s.position - expected).abs();
      if (diff > seekDetectThreshold) {
        sync.notifyLocalChange(doSeek: true);
      }
    }

    _lastPaused = paused;
    _lastPosition = s.position;
    _lastTick = DateTime.now();
  }

  Future<void> _onPeerState(PeerPlayState peer) async {
    // The SyncCore only emits states that genuinely require a local change
    // (the convergence/anti-fight decision lives in decideFollow), so the
    // bridge applies each one: align position, then match play/pause.
    _applyingRemote = true;
    try {
      // Seek only on an explicit peer seek, or when we've drifted materially
      // from the room. A pause/play flip where we're already frame-aligned
      // (within the threshold) skips the seek, so network jitter never causes
      // a visible micro-jump backward. This mirrors real Syncplay, which only
      // repositions on a genuine seek or correction.
      final drift = (peer.position - video.state.position).abs();
      if (peer.doSeek || drift > remoteSeekThreshold) {
        await video.seek(peer.position);
      }

      final localPaused = video.state.status != PlaybackStatus.playing;
      if (peer.paused && !localPaused) {
        await video.pause();
      } else if (!peer.paused && localPaused) {
        await video.play();
      }
    } finally {
      _applyingRemote = false;
      // Keep suppressing local-change detection briefly so the async player
      // state events triggered above are not echoed back as local changes.
      _remoteApplyUntil = DateTime.now().add(remoteApplyWindow);
    }
  }

  Future<void> dispose() async {
    await _videoSub?.cancel();
    await _peerSub?.cancel();
  }
}
