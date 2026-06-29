import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/reduce_motion.dart';
import '../core/theme/tokens/motion.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';

/// The slot that shows the transient over-video notice ("friend joined", "you're
/// in sync", a file mismatch, the waiting hint, …). There's only ever one at a
/// time; pass the current [text], or null when there's nothing to say.
///
/// Every change animates: a new notice **slides down + fades in**, the old one
/// **slides up + fades out**, and swapping one notice for another cross-fades
/// between them — so a notice never hard-cuts on or off the screen. Honors reduce
/// motion: swaps are instant.
class SyncHintBanner extends StatelessWidget {
  const SyncHintBanner({required this.text, super.key});

  /// The notice to show, or null to show nothing (animating any current notice
  /// out).
  final String? text;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : Motion.base,
      switchInCurve: Motion.standard,
      switchOutCurve: Motion.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          // Drops in from above and the outgoing notice reverses (slides back
          // up) as it fades. The travel is a full pill-height so that even a
          // swap from one notice straight to another — overlapping opaque pills
          // in the same slot — reads as a clear in/out move, not an in-place
          // text flip (#178 follow-up).
          position: Tween<Offset>(
            begin: const Offset(0, -1.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: text == null
          ? const SizedBox.shrink(key: ValueKey<String>('_sync-banner-empty'))
          : _BannerPill(key: ValueKey<String>(text!), text: text!),
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return IgnorePointer(
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
          text,
          style: TextStyle(color: m.textPrimary, fontSize: TypeScale.label),
        ),
      ),
    );
  }
}
