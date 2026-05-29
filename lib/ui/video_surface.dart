import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/meow_theme.dart';
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
    this.currentTheme,
    this.onThemeChanged,
    super.key,
  });

  final MediaKitVideoCore core;
  final MeowThemeId? currentTheme;
  final ValueChanged<MeowThemeId>? onThemeChanged;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  late final VideoController _controller;
  final FocusNode _focus = FocusNode();

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

  // Bottom control bar auto-hide.
  bool _barVisible = true;
  Timer? _hideTimer;

  bool _isFullscreen = false;

  static const _hideDelay = Duration(seconds: 3);
  static const _seekLinger = Duration(milliseconds: 600);
  static const _volumeLinger = Duration(milliseconds: 900);
  static const _seekStep = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _controller = VideoController(widget.core.player);
    _focus.requestFocus();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekHideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _flash(PlaybackAction action) {
    setState(() {
      _lastAction = action;
      _actionTrigger++;
    });
  }

  void _revealBar() {
    if (!_barVisible) setState(() => _barVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted) return;
      if (widget.core.state.status == PlaybackStatus.playing) {
        setState(() => _barVisible = false);
      }
    });
  }

  void _togglePlay() {
    final willPlay = widget.core.state.status != PlaybackStatus.playing;
    widget.core.togglePlay();
    _flash(willPlay ? PlaybackAction.play : PlaybackAction.pause);
    _revealBar();
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
    _revealBar();
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
        onHover: (_) => _revealBar(),
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
                        _barVisible || state.status != PlaybackStatus.playing;
                    return AnimatedOpacity(
                      opacity: visible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: PlaybackBar(
                        state: state,
                        onSeek: widget.core.seek,
                        onTogglePlay: _togglePlay,
                        currentTheme: widget.currentTheme,
                        onThemeChanged: widget.onThemeChanged,
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
