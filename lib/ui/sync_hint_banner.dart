import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/reduce_motion.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';

/// The pill shown over the video for a transient sync notice ("friend joined",
/// "you're in sync", a file mismatch, …). It slides down a touch and fades in
/// with a gentle [Motion.springy] settle when it first appears, so a notice
/// never hard-cuts onto the screen.
///
/// Key it on its text at the call site (`SyncHintBanner(key: ValueKey(text), …)`)
/// so a new notice re-mounts and replays the entrance. Honors reduce motion:
/// when on, it is present immediately, fully settled, with no slide.
class SyncHintBanner extends StatefulWidget {
  const SyncHintBanner({required this.text, super.key});

  final String text;

  @override
  State<SyncHintBanner> createState() => _SyncHintBannerState();
}

class _SyncHintBannerState extends State<SyncHintBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.base);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: Motion.springy);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c.value = 1; // instant, fully settled
    } else if (_c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) {
          final t = _curve.value;
          return Opacity(
            // springy can overshoot past 1; opacity must stay in range.
            opacity: t.clamp(0.0, 1.0),
            // Starts ~12px above and drops into place (springy dips slightly
            // past 0 then settles).
            child: Transform.translate(
              offset: Offset(0, (t - 1) * 12),
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: m.background.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: m.border),
          ),
          child: Text(
            widget.text,
            style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
          ),
        ),
      ),
    );
  }
}
