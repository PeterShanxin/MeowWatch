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

  /// The fileName seen on the last state event. Loading a new file changes this
  /// value; we treat the transition as a load event (not a seek) and skip seek
  /// detection for that tick — the position jump to 0 is not user intent.
  String? _lastFileName;

  void start() {
    _videoSub = video.stateStream.listen(_onLocalState);
    _peerSub = sync.peerState.listen(_onPeerState);
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;

    // Always feed the latest position to the sync layer for its heartbeat.
    sync.updateLocalState(position: s.position, paused: paused);

    // A new file was loaded. Reset baselines so the position jump to 0 is not
    // mistaken for a backward seek — the user didn't seek, they just opened a
    // file. Skip all change detection for this tick.
    if (s.fileName != _lastFileName) {
      _lastFileName = s.fileName;
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
