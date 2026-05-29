import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/video/playback_state.dart';

/// Bottom overlay bar: current time, a draggable scrubber, total duration,
/// and a play/pause button. Auto-hide behaviour is owned by the parent.
class PlaybackBar extends StatelessWidget {
  const PlaybackBar({
    required this.state,
    required this.onSeek,
    required this.onTogglePlay,
    super.key,
  });

  final PlaybackState state;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs =
        state.position.inMilliseconds.clamp(0, hasDuration ? durationMs : 1);
    final isPlaying = state.status == PlaybackStatus.playing;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [m.scrim.withValues(alpha: 0.80), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onTogglePlay,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: m.textPrimary,
            ),
          ),
          Text(_fmt(state.position),
              style: TextStyle(color: m.textPrimary, fontSize: 12)),
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
              style: TextStyle(color: m.textPrimary, fontSize: 12)),
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
