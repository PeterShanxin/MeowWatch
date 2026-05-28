import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/video/media_kit_video_core.dart';
import '../core/video/playback_state.dart';
import 'action_feedback_overlay.dart';
import 'playback_action.dart';
import 'playback_bar.dart';

class VideoSurface extends StatefulWidget {
  const VideoSurface({required this.core, super.key});

  final MediaKitVideoCore core;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  late final VideoController _controller;
  final FocusNode _focus = FocusNode();

  PlaybackAction? _lastAction;
  int _actionTrigger = 0;

  bool _barVisible = true;
  Timer? _hideTimer;

  static const _hideDelay = Duration(seconds: 3);

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
    _focus.dispose();
    super.dispose();
  }

  /// Flash a transient feedback icon over the video.
  void _flash(PlaybackAction action) {
    setState(() {
      _lastAction = action;
      _actionTrigger++;
    });
  }

  /// Reveal the bottom bar and (re)start the idle countdown that hides it.
  void _revealBar() {
    if (!_barVisible) setState(() => _barVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      // Keep the bar up while paused — there's nothing to watch, and the user
      // likely wants the scrubber.
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

  void _handleTap() {
    _focus.requestFocus();
    _togglePlay();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Space toggles once per physical press (ignore key-repeat so holding it
    // doesn't strobe play/pause). Arrows fire on press AND repeat so holding
    // them seeks/adjusts volume continuously, like a normal media player.
    final isPress = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isPress && !isRepeat) return KeyEventResult.ignored;

    final core = widget.core;
    final s = core.state;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (isPress) _togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      core.seek(_clampSeek(s.position + const Duration(seconds: 5), s.duration));
      if (isPress) _flash(PlaybackAction.seekForward);
      _revealBar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      core.seek(_clampSeek(s.position - const Duration(seconds: 5), s.duration));
      if (isPress) _flash(PlaybackAction.seekBackward);
      _revealBar();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      core.setVolume((s.volume + 0.05).clamp(0.0, 1.0));
      if (isPress) _flash(PlaybackAction.volumeUp);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      core.setVolume((s.volume - 0.05).clamp(0.0, 1.0));
      if (isPress) _flash(PlaybackAction.volumeDown);
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.black,
                child: Video(
                  controller: _controller,
                  // Disable built-in controls — we render our own overlays so
                  // they don't intercept taps or clash with the Cozy palette.
                  controls: (_) => const SizedBox.shrink(),
                ),
              ),
              ActionFeedbackOverlay(
                action: _lastAction,
                trigger: _actionTrigger,
              ),
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
