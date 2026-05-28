import 'package:flutter/material.dart';

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

  static const _cream = Color(0xFFF5E6D3);
  static const _amber = Color(0xFFD4A574);

  @override
  Widget build(BuildContext context) {
    final durationMs = state.duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final positionMs =
        state.position.inMilliseconds.clamp(0, hasDuration ? durationMs : 1);
    final isPlaying = state.status == PlaybackStatus.playing;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onTogglePlay,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _cream,
            ),
          ),
          Text(_fmt(state.position),
              style: const TextStyle(color: _cream, fontSize: 12)),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 3,
                activeTrackColor: _amber,
                inactiveTrackColor: Color(0x55F5E6D3),
                thumbColor: _amber,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
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
              style: const TextStyle(color: _cream, fontSize: 12)),
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
