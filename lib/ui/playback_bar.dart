import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/video/playback_state.dart';
import 'volume_control.dart';

/// Bottom overlay bar: current time, a draggable scrubber, total duration,
/// a play/pause button, and a volume control (hover-to-slider, tap-to-mute).
/// Auto-hide behaviour is owned by the parent.
class PlaybackBar extends StatelessWidget {
  const PlaybackBar({
    required this.state,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onSetVolume,
    super.key,
  });

  final PlaybackState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onSetVolume;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs =
        state.position.inMilliseconds.clamp(0, hasDuration ? durationMs : 1);
    final isPlaying = state.status == PlaybackStatus.playing;

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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onTogglePlay,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: m.textPrimary,
            ),
          ),
          Text(_fmt(state.position),
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.body)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: m.accent,
                inactiveTrackColor: m.textPrimary.withValues(alpha: 0.33),
                thumbColor: m.accent,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: hasDuration ? positionMs.toDouble() : 0,
                max: hasDuration ? durationMs.toDouble() : 1,
                onChanged: hasDuration
                    ? (v) => onSeek(Duration(milliseconds: v.round()))
                    : null,
              ),
            ),
          ),
          Text(_fmt(state.duration),
              style: TextStyle(color: m.textPrimary, fontSize: TypeScale.body)),
          VolumeControl(
            volume: state.volume,
            onSetVolume: onSetVolume,
            onToggleMute: onToggleMute,
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
