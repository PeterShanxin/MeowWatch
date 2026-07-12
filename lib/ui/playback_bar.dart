import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/reduce_motion.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/video/playback_state.dart';
import 'instant_tap_icon.dart';
import 'volume_control.dart';

/// Scrubber slider metrics at interaction progress [t] (0 = at rest, 1 =
/// actively scrubbing). The thumb, track, and overlay all grow a little while
/// the bar is dragged or clicked, so the progress bar feels responsive under the
/// finger.
({double thumb, double track, double overlay}) scrubberMetrics(double t) => (
      thumb: 6 + 3 * t,
      track: 3 + 2 * t,
      overlay: 12 + 6 * t,
    );

/// Bottom overlay bar: current time, a draggable scrubber, total duration,
/// a play/pause button, a volume control (hover-to-slider, tap-to-mute), and a
/// windowed/fullscreen toggle. Auto-hide behaviour is owned by the parent.
class PlaybackBar extends StatefulWidget {
  const PlaybackBar({
    required this.state,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onSetVolume,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    super.key,
  });

  final PlaybackState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onSetVolume;

  /// Whether the window is currently fullscreen — picks the toggle's icon.
  final bool isFullscreen;

  /// Toggle between windowed and fullscreen.
  final VoidCallback onToggleFullscreen;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar> {
  bool _dragging = false;

  void _setDragging(bool v) {
    if (_dragging != v) setState(() => _dragging = v);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final state = widget.state;
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs =
        state.position.inMilliseconds.clamp(0, hasDuration ? durationMs : 1);
    final isPlaying = state.status == PlaybackStatus.playing;
    final reduceMotion = context.reduceMotion;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          Spacing.sm, Spacing.xxl, Spacing.lg, Spacing.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [m.scrim.withValues(alpha: 0.80), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          InstantTapIcon(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: m.textPrimary,
            semanticLabel: isPlaying ? 'Pause' : 'Play',
            onPressed: widget.onTogglePlay,
          ),
          Text(_fmt(state.position),
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.body)),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _dragging ? 1.0 : 0.0),
              duration: reduceMotion ? Duration.zero : Motion.fast,
              curve: Motion.standard,
              builder: (context, t, child) {
                final s = scrubberMetrics(t);
                return SliderTheme(
                  data: SliderThemeData(
                    trackHeight: s.track,
                    activeTrackColor: m.accent,
                    inactiveTrackColor: m.textPrimary.withValues(alpha: 0.33),
                    thumbColor: m.accent,
                    thumbShape:
                        RoundSliderThumbShape(enabledThumbRadius: s.thumb),
                    overlayShape:
                        RoundSliderOverlayShape(overlayRadius: s.overlay),
                  ),
                  child: Slider(
                    value: hasDuration ? positionMs.toDouble() : 0,
                    max: hasDuration ? durationMs.toDouble() : 1,
                    onChanged: hasDuration
                        ? (v) => widget.onSeek(Duration(milliseconds: v.round()))
                        : null,
                    onChangeStart:
                        hasDuration ? (_) => _setDragging(true) : null,
                    onChangeEnd:
                        hasDuration ? (_) => _setDragging(false) : null,
                  ),
                );
              },
            ),
          ),
          Text(_fmt(state.duration),
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.body)),
          VolumeControl(
            volume: state.volume,
            onSetVolume: widget.onSetVolume,
            onToggleMute: widget.onToggleMute,
          ),
          InstantTapIcon(
            icon: widget.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            color: m.textPrimary,
            semanticLabel:
                widget.isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
            onPressed: widget.onToggleFullscreen,
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
