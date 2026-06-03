import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/tokens/motion.dart';
import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'action_feedback_overlay.dart';
import 'playback_action.dart';
import 'playback_bar.dart';
import 'seek_indicator.dart';
import 'volume_indicator.dart';

class VideoSurface extends StatefulWidget {
  const VideoSurface({
    required this.core,
    this.focusNode,
    required this.isUiIdle,
    required this.onUserInteraction,
    super.key,
  });

  final MediaKitVideoCore core;

  /// Optional external focus node so the parent can restore keyboard focus to
  /// the player (e.g. after the chat collapses) — keeping Tab/space reliable.
  final FocusNode? focusNode;

  final bool isUiIdle;
  final VoidCallback onUserInteraction;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  // Owned by the core (created eagerly there so the very first open() has its
  // video output wired). VideoSurface just references it — never disposes it.
  late final VideoController _controller = widget.core.videoController;
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  // Play/pause center flash.
  PlaybackAction? _lastAction;
  int _actionTrigger = 0;

  // Held-seek indicator (null direction => hidden).
  bool? _seekForward;
  int _seekSeconds = 0;
  Timer? _seekHideTimer;

  // Volume indicator (null => hidden).
  double? _volumeShown;
  Timer? _volumeHideTimer;
  double _lastUnmutedVolume = 1.0;

  bool _isFullscreen = false;

  static const _seekLinger = Duration(milliseconds: 600);
  static const _volumeLinger = Duration(milliseconds: 900);
  static const _seekStep = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _seekHideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _ownFocus?.dispose();
    // Always leave the app windowed when the player surface goes away — don't
    // trust the local flag, which can desync if fullscreen is toggled via OS
    // window controls. A no-op when already windowed.
    unawaited(windowManager.setFullScreen(false));
    super.dispose();
  }

  void _flash(PlaybackAction action) {
    setState(() {
      _lastAction = action;
      _actionTrigger++;
    });
  }

  void _handleUserInteraction() {
    widget.onUserInteraction();
  }

  void _togglePlay() {
    final willPlay = widget.core.state.status != PlaybackStatus.playing;
    widget.core.togglePlay();
    _flash(willPlay ? PlaybackAction.play : PlaybackAction.pause);
    _handleUserInteraction();
  }

  Future<void> _toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    await windowManager.setFullScreen(_isFullscreen);
  }

  void _handleTap() {
    _focus.requestFocus();
    _togglePlay();
  }

  void _onSeekKey({required bool forward, required bool isPress}) {
    final core = widget.core;
    final s = core.state;
    final delta = forward ? _seekStep : -_seekStep;
    core.seek(_clampSeek(s.position + delta, s.duration));

    _seekHideTimer?.cancel();
    setState(() {
      if (_seekForward != forward || isPress) {
        // New hold (or direction flip) restarts the accumulator.
        _seekForward = forward;
        _seekSeconds = _seekStep.inSeconds;
      } else {
        _seekSeconds += _seekStep.inSeconds;
      }
    });
    _handleUserInteraction();
  }

  void _onVolumeKey(bool up) {
    final core = widget.core;
    final next = (core.state.volume + (up ? 0.05 : -0.05)).clamp(0.0, 1.0);
    core.setVolume(next);
    _volumeHideTimer?.cancel();
    setState(() => _volumeShown = next);
    _volumeHideTimer = Timer(_volumeLinger, () {
      if (mounted) setState(() => _volumeShown = null);
    });
    // Volume keys are consumed here (KeyEventResult.handled), so the ancestor
    // idle-reset hook never sees them — wake the UI directly, like play/seek.
    _handleUserInteraction();
  }

  void _toggleMute() {
    final core = widget.core;
    if (core.state.volume > 0.0) {
      _lastUnmutedVolume = core.state.volume;
      core.setVolume(0.0);
    } else {
      core.setVolume(_lastUnmutedVolume > 0.0 ? _lastUnmutedVolume : 1.0);
    }
    _handleUserInteraction();
  }

  void _onSeekReleased() {
    _seekHideTimer?.cancel();
    _seekHideTimer = Timer(_seekLinger, () {
      if (mounted) setState(() => _seekForward = null);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isPress = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    final isRelease = event is KeyUpEvent;
    final key = event.logicalKey;

    if (isRelease) {
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowLeft) {
        _onSeekReleased();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!isPress && !isRepeat) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space) {
      if (isPress) _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _onSeekKey(forward: true, isPress: isPress);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _onSeekKey(forward: false, isPress: isPress);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _onVolumeKey(true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _onVolumeKey(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Clamp [target] to `[Duration.zero, duration]`. If [duration] is zero
  /// (unknown yet) only clamp the lower bound.
  Duration _clampSeek(Duration target, Duration duration) {
    if (target < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && target > duration) return duration;
    return target;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      autofocus: true,
      child: MouseRegion(
        onHover: (_) => _handleUserInteraction(),
        child: GestureDetector(
          onTap: _handleTap,
          onDoubleTap: _toggleFullscreen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.black,
                child: Video(
                  controller: _controller,
                  controls: (_) => const SizedBox.shrink(),
                ),
              ),
              ActionFeedbackOverlay(
                action: _lastAction,
                trigger: _actionTrigger,
              ),
              if (_seekForward != null)
                SeekIndicator(forward: _seekForward!, seconds: _seekSeconds),
              if (_volumeShown != null) VolumeIndicator(volume: _volumeShown!),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: StreamBuilder<PlaybackState>(
                  stream: widget.core.stateStream,
                  initialData: widget.core.state,
                  builder: (context, snapshot) {
                    final state = snapshot.data!;
                    final visible =
                        !widget.isUiIdle || state.status != PlaybackStatus.playing;
                    return AnimatedOpacity(
                      opacity: visible ? 1.0 : 0.0,
                      duration: Motion.base,
                      child: PlaybackBar(
                        state: state,
                        onSeek: widget.core.seek,
                        onTogglePlay: _togglePlay,
                        onToggleMute: _toggleMute,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
