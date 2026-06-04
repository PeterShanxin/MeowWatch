import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';

/// Volume button with on-hover vertical slider.
///
/// - Hover anywhere over the widget → vertical slider floats above the icon.
/// - Move cursor away → slider hides after a short debounce.
/// - Tap the icon → mute/unmute via [onToggleMute].
/// - Drag slider → [onSetVolume] (0.0–1.0).
///
/// A single [MouseRegion] wraps both the slider panel and the icon so there
/// is no hover-seam flicker between the two halves.
class VolumeControl extends StatefulWidget {
  const VolumeControl({
    required this.volume,
    required this.onSetVolume,
    required this.onToggleMute,
    super.key,
  });

  final double volume;
  final ValueChanged<double> onSetVolume;
  final VoidCallback onToggleMute;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  bool _sliderVisible = false;
  Timer? _hideTimer;
  static const _hideDelay = Duration(milliseconds: 150);

  void _onEnter(_) {
    _hideTimer?.cancel();
    if (!_sliderVisible) setState(() => _sliderVisible = true);
  }

  void _onExit(_) {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _sliderVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  IconData get _icon {
    if (widget.volume <= 0.0) return Icons.volume_off_rounded;
    if (widget.volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_sliderVisible)
            Container(
              width: 36,
              height: 120,
              margin: const EdgeInsets.only(bottom: Spacing.xs),
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              decoration: BoxDecoration(
                color: m.scrim.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: m.accent,
                    inactiveTrackColor: m.textPrimary.withValues(alpha: 0.33),
                    thumbColor: m.accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: widget.volume.clamp(0.0, 1.0),
                    onChanged: widget.onSetVolume,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: widget.onToggleMute,
            icon: Icon(_icon, color: m.textPrimary),
          ),
        ],
      ),
    );
  }
}
