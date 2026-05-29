import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';

/// Transient volume level indicator shown while the user adjusts volume:
/// a speaker icon, a horizontal level bar, and the percentage.
class VolumeIndicator extends StatelessWidget {
  const VolumeIndicator({required this.volume, super.key});

  /// Volume in the range 0.0–1.0.
  final double volume;

  IconData get _icon {
    if (volume <= 0.0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final pct = (volume.clamp(0.0, 1.0) * 100).round();
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: m.scrim.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 26, color: m.textPrimary),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: volume.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: m.textPrimary.withValues(alpha: 0.33),
                    valueColor: AlwaysStoppedAnimation<Color>(m.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: Text(
                  '$pct%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: m.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
