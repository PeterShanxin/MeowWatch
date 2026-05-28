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

  StreamSubscription<PlaybackState>? _videoSub;
  StreamSubscription<PeerPlayState>? _peerSub;

  bool _applyingRemote = false;
  DateTime _remoteApplyUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _lastPaused;
  Duration _lastPosition = Duration.zero;
  DateTime _lastTick = DateTime.now();

  /// Last paused-state we saw from the peer, used to detect transitions. The
  /// server relays the room's *global* playstate on every heartbeat (~1/s); we
  /// must only act on real changes, not chase the steady-state position — that
  /// chase is what made the two clients fight and snap back to 0.
  bool? _lastPeerPaused;

  void start() {
    _videoSub = video.stateStream.listen(_onLocalState);
    _peerSub = sync.peerState.listen(_onPeerState);
  }

  void _onLocalState(PlaybackState s) {
    final paused = s.status != PlaybackStatus.playing;

    // Always feed the latest position to the sync layer for its heartbeat.
    sync.updateLocalState(position: s.position, paused: paused);

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
    // Only react to genuine transitions: the first state we ever see (adopt the
    // room), a pause<->play flip, or an explicit seek. Steady heartbeats with
    // an unchanged paused flag are ignored so we never chase position and fight.
    final firstEver = _lastPeerPaused == null;
    final pausedFlipped = _lastPeerPaused != null && peer.paused != _lastPeerPaused;
    final transition = firstEver || pausedFlipped || peer.doSeek;
    _lastPeerPaused = peer.paused;

    if (!transition) return;

    _applyingRemote = true;
    try {
      // Align to the peer's frame on every transition (join/pause/play/seek)
      // so both land on the same position; never seek on steady drift.
      await video.seek(peer.position);

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
