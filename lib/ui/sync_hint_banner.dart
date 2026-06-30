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
/// **fades out**, and swapping one notice for another cross-dissolves while the
/// incoming notice slides in over it — so a notice never hard-cuts on screen.
///
/// The entrance is driven by [_BannerPill] **itself** (it plays an intro the
/// moment it mounts), not by the [AnimatedSwitcher]. That's deliberate: a notice
/// can appear in the same frame the surrounding layout reshuffles (loading a
/// video inserts sibling overlays), which can rebuild this subtree and reset an
/// AnimatedSwitcher — making it skip its "first child" transition and hard-cut
/// the notice in. A pill that animates on mount can't be defeated that way. The
/// switcher only manages one-at-a-time + the exit fade. Honors reduce motion:
/// swaps are instant.
class SyncHintBanner extends StatelessWidget {
  const SyncHintBanner({required this.text, super.key});

  /// The notice to show, or null to show nothing (fading any current notice out).
  final String? text;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : Motion.base,
      switchInCurve: Motion.standard,
      switchOutCurve: Motion.standard,
      // Cross-dissolve only; the incoming pill supplies its own slide-in.
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: text == null
          ? const SizedBox.shrink(key: ValueKey<String>('_sync-banner-empty'))
          : _BannerPill(key: ValueKey<String>(text!), text: text!),
    );
  }
}

/// The notice pill. Animates its own entrance (fade + slide from just above) the
/// first time it mounts, so a fresh notice always reads as arriving — regardless
/// of what the parent [AnimatedSwitcher]'s state happens to be.
class _BannerPill extends StatefulWidget {
  const _BannerPill({required this.text, super.key});

  final String text;

  @override
  State<_BannerPill> createState() => _BannerPillState();
}

class _BannerPillState extends State<_BannerPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: Motion.base,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kick the entrance once, here rather than initState, so reading
    // context.reduceMotion (an InheritedWidget) is safe.
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _intro.value = 1; // present instantly
    } else {
      _intro.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final curved = CurvedAnimation(parent: _intro, curve: Motion.standard);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.6),
          end: Offset.zero,
        ).animate(curved),
        child: IgnorePointer(
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
              style: TextStyle(
                color: m.textPrimary,
                fontSize: TypeScale.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
