import 'package:flutter/material.dart';

import '../../core/data/history_collapse.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/history_mode.dart';
import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/opacities.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/shadows.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../brand/meow_logo.dart';
import '../brand/meow_logo_mark.dart';
import '../chat/chat_bubble.dart';
import '../connect/history_format.dart';
import '../empty_state.dart';
import '../launch/launch_reveal.dart';
import '../launch/launch_tips.dart';
import '../motion/pressable_scale.dart';
import '../motion/reveal_in.dart';
import '../staggered_reflow_list.dart';

/// 8-digit ARGB hex for a token swatch label, e.g. `#FF1A1410`.
String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

/// A framed panel: titled, optionally described, holding one scale's specimen.
/// Cards sit in a centered max-width column so the gallery reads like a page,
/// not a window-wide debug dump.
class GallerySection extends StatelessWidget {
  const GallerySection({
    super.key,
    required this.title,
    required this.child,
    this.description,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.lg),
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: t.caption.copyWith(
              color: c.accent,
              letterSpacing: 2,
              fontWeight: TypeScale.semibold,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(description!, style: t.caption.copyWith(color: c.textDim)),
          ],
          const SizedBox(height: Spacing.lg),
          child,
        ],
      ),
    );
  }
}

/// One labelled token swatch: a tile of [child] with a name (+ optional sub).
class _Swatch extends StatelessWidget {
  const _Swatch({required this.tile, required this.name, this.sub});
  final Widget tile;
  final String name;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final c = context.meow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        const SizedBox(height: Spacing.sm),
        Text(name, style: t.caption.copyWith(color: c.textPrimary)),
        if (sub != null)
          Text(sub!, style: t.caption.copyWith(color: c.textDim)),
      ],
    );
  }
}

class ColorSpecimen extends StatelessWidget {
  const ColorSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final swatches = <(String, Color)>[
      ('background', c.background),
      ('surface', c.surface),
      ('accent', c.accent),
      ('textPrimary', c.textPrimary),
      ('textDim', c.textDim),
      ('border', c.border),
      ('myBubble', c.myBubble),
      ('peerBubble', c.peerBubble),
      ('online', c.online),
      ('scrim', c.scrim),
    ];
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.lg,
      children: [
        for (final (name, color) in swatches)
          _Swatch(
            name: name,
            sub: _hex(color),
            tile: Container(
              width: 96,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.border),
              ),
            ),
          ),
      ],
    );
  }
}

class TypeSpecimen extends StatelessWidget {
  const TypeSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final c = context.meow;
    final rows = <(String, String, TextStyle)>[
      ('caption', '11', t.caption),
      ('body', '13', t.body),
      ('label', '15', t.label),
      ('title', '18', t.title),
      ('heading', '24', t.heading),
      ('display', '30', t.display),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    '${rows[i].$1} ${rows[i].$2}',
                    style: t.caption.copyWith(color: c.textDim),
                  ),
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Text(
                    'The quick brown fox',
                    style: rows[i].$3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RadiusSpecimen extends StatelessWidget {
  const RadiusSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('xs', Radii.xs),
      ('sm', Radii.sm),
      ('md', Radii.md),
      ('lg', Radii.lg),
      ('xl', Radii.xl),
      ('pill', Radii.pill),
    ];
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.lg,
      children: [
        for (final (name, r) in steps)
          _Swatch(
            name: '$name · ${r.toInt()}',
            tile: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.myBubble,
                border: Border.all(color: c.accent),
                borderRadius: BorderRadius.circular(r),
              ),
            ),
          ),
      ],
    );
  }
}

class SpacingSpecimen extends StatelessWidget {
  const SpacingSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    const steps = <double>[
      Spacing.xxs,
      Spacing.xs,
      Spacing.sm,
      Spacing.md,
      Spacing.lg,
      Spacing.xl,
      Spacing.xxl,
      Spacing.xxxl,
    ];
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.md,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final s in steps)
          _Swatch(
            name: s.toInt().toString(),
            tile: Container(width: s, height: 40, color: c.accent),
          ),
      ],
    );
  }
}

class IconSpecimen extends StatelessWidget {
  const IconSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('16', IconSizes.sm),
      ('20', IconSizes.md),
      ('24', IconSizes.lg),
      ('32', IconSizes.xl),
    ];
    return Wrap(
      spacing: Spacing.xl,
      runSpacing: Spacing.md,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final (name, s) in steps)
          _Swatch(
            name: name,
            tile: Icon(Icons.pets, size: s, color: c.accent),
          ),
        const _Swatch(
          name: 'react · 20',
          tile: Text('🐾', style: TextStyle(fontSize: Glyphs.react)),
        ),
        const _Swatch(
          name: 'burst · 34',
          tile: Text('🐾', style: TextStyle(fontSize: Glyphs.burst)),
        ),
      ],
    );
  }
}

class OpacitySpecimen extends StatelessWidget {
  const OpacitySpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('dim', Opacities.dim),
      ('scrim', Opacities.scrim),
      ('disabled', Opacities.disabled),
      ('pressed', Opacities.pressed),
      ('hover', Opacities.hover),
    ];
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.lg,
      children: [
        for (final (name, a) in steps)
          _Swatch(
            name: name,
            sub: a.toStringAsFixed(2),
            tile: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.accent.withValues(alpha: a),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
      ],
    );
  }
}

/// The motion design system, live: durations race so 120 vs 320ms is legible,
/// easings race so the acceleration slope is legible (each with its curve
/// thumbnail), and the raw token chips name them. Drives the real [Motion]
/// tokens + Flutter [Curves], so editing a token moves these.
class MotionSpecimen extends StatelessWidget {
  const MotionSpecimen({super.key});

  // Easing racers share one duration so only the *slope* differs between them.
  // Demo timing only (not a shipped token) — long enough that the curve reads.
  static const Duration _easingRace = Duration(milliseconds: 720);

  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final c = context.meow;

    Widget subhead(String text) => Text(
      text.toUpperCase(),
      style: t.caption.copyWith(
        color: c.textPrimary,
        letterSpacing: 1.5,
        fontWeight: TypeScale.semibold,
      ),
    );

    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.myBubble,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: t.caption.copyWith(color: c.textPrimary)),
    );

    Widget durationLeading(String label) =>
        Text(label, style: t.caption.copyWith(color: c.textDim));

    Widget easingLeading(Curve curve, String name, String bezier) => Row(
      children: [
        _EasingCurveThumb(curve: curve),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: TypeScale.semibold,
                ),
              ),
              Text(bezier, style: t.caption.copyWith(color: c.textDim)),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        subhead('Durations'),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: Motion.xfast,
          curve: Motion.standard,
          leading: durationLeading('xfast · ${Motion.xfast.inMilliseconds}ms'),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: Motion.fast,
          curve: Motion.standard,
          leading: durationLeading('fast · ${Motion.fast.inMilliseconds}ms'),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: Motion.base,
          curve: Motion.standard,
          leading: durationLeading('base · ${Motion.base.inMilliseconds}ms'),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: Motion.slow,
          curve: Motion.standard,
          leading: durationLeading('slow · ${Motion.slow.inMilliseconds}ms'),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: Motion.expressive,
          curve: Motion.standard,
          leading: durationLeading(
            'expressive · ${Motion.expressive.inMilliseconds}ms',
          ),
        ),
        const SizedBox(height: Spacing.xl),
        subhead('Easings'),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: _easingRace,
          curve: Motion.standard,
          leadingWidth: 168,
          leading: easingLeading(
            Motion.standard,
            'easeOutCubic',
            '(.215, .61, .355, 1)',
          ),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: _easingRace,
          curve: Motion.symmetric,
          leadingWidth: 168,
          leading: easingLeading(
            Motion.symmetric,
            'easeInOut',
            '(.42, 0, .58, 1)',
          ),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: _easingRace,
          curve: Motion.emphasized,
          leadingWidth: 168,
          leading: easingLeading(
            Motion.emphasized,
            'emphasized',
            'M3 emphasized',
          ),
        ),
        const SizedBox(height: Spacing.md),
        _MotionRacer(
          duration: _easingRace,
          curve: Motion.emphasizedAccelerate,
          leadingWidth: 168,
          leading: easingLeading(
            Motion.emphasizedAccelerate,
            'emphasizedAccel',
            '(.3, 0, .8, .15)',
          ),
        ),
        const SizedBox(height: Spacing.xl),
        // The overshoot / wind-up curves (springy, elasticPop, anticipate) are
        // shown live in the Motion · principles section, where the transform is
        // built for overshoot; here they're named so the token list is complete.
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.md,
          children: [
            chip('xfast · ${Motion.xfast.inMilliseconds}ms'),
            chip('fast · ${Motion.fast.inMilliseconds}ms'),
            chip('base · ${Motion.base.inMilliseconds}ms'),
            chip('slow · ${Motion.slow.inMilliseconds}ms'),
            chip('expressive · ${Motion.expressive.inMilliseconds}ms'),
            chip('stagger · ${Motion.stagger.inMilliseconds}ms'),
            chip('reveal · ${Motion.reveal.inMilliseconds}ms'),
            chip('standard · easeOutCubic'),
            chip('symmetric · easeInOut'),
            chip('emphasized · easeInOutCubicEmphasized'),
            chip('emphasizedAccelerate · (.3, 0, .8, .15)'),
            chip('springy · (.34, 1.26, .64, 1)'),
            chip('elasticPop · (.2, 1.5, .4, 1)'),
            chip('anticipate · (.36, 0, .66, -.3)'),
          ],
        ),
      ],
    );
  }
}

/// A dot looping back and forth along a rail over [duration] with [curve] — so a
/// duration token's speed (or an easing's slope) is visible at a glance.
class _MotionRacer extends StatefulWidget {
  const _MotionRacer({
    required this.duration,
    required this.curve,
    required this.leading,
    this.leadingWidth = 120,
  });

  final Duration duration;
  final Curve curve;
  final Widget leading;
  final double leadingWidth;

  @override
  State<_MotionRacer> createState() => _MotionRacerState();
}

class _MotionRacerState extends State<_MotionRacer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat(reverse: true);
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    const dot = 14.0;
    return Row(
      children: [
        SizedBox(width: widget.leadingWidth, child: widget.leading),
        const SizedBox(width: Spacing.lg),
        Expanded(
          child: SizedBox(
            height: 16,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 7,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _t,
                  builder: (context, child) => Align(
                    alignment: Alignment(_t.value * 2 - 1, 0),
                    child: child,
                  ),
                  child: Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.accent,
                      boxShadow: [
                        BoxShadow(
                          color: c.accent.withValues(alpha: Opacities.pressed),
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small framed plot of an easing [curve] (progress vs time), sampled from the
/// real Flutter [Curve] so the thumbnail always matches what ships.
class _EasingCurveThumb extends StatelessWidget {
  const _EasingCurveThumb({required this.curve});

  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Container(
      width: 46,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      child: CustomPaint(
        painter: _EasingCurvePainter(curve: curve, color: c.accent),
      ),
    );
  }
}

class _EasingCurvePainter extends CustomPainter {
  _EasingCurvePainter({required this.curve, required this.color});

  final Curve curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.0;
    final w = size.width - inset * 2;
    final h = size.height - inset * 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path();
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final y = curve.transform(x);
      final px = inset + x * w;
      final py = inset + (1 - y) * h; // y grows upward
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EasingCurvePainter old) =>
      old.curve != curve || old.color != color;
}

/// The Disney motion principles that map to this app's UI, each a live looping
/// specimen driving the real [Motion] character curves — so "anticipation",
/// "overshoot" and "squash" are running code, not vibes. Honors reduce motion:
/// the loops hold their settled end-state, which is itself the lesson (reduce
/// motion drops the character).
class MotionPrinciplesSpecimen extends StatelessWidget {
  const MotionPrinciplesSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrincipleTile(
          title: 'Anticipation',
          blurb: 'A tiny wind-up before the move.',
          // Motion.anticipate dips backward first, then drives forward.
          child: _CurveLoop(
            curve: Motion.anticipate,
            duration: Motion.slow,
            builder: (context, t) => Align(
              alignment: Alignment(-0.8 + t * 1.6, 0),
              child: const _AccentDot(),
            ),
          ),
        ),
        _PrincipleTile(
          title: 'Overshoot',
          blurb: 'Follow-through that settles past the mark.',
          // Motion.springy overshoots its target (interior) then settles back.
          child: _CurveLoop(
            curve: Motion.springy,
            duration: Motion.slow,
            builder: (context, t) => Align(
              alignment: Alignment(-0.8 + t * 1.2, 0),
              child: const _AccentDot(),
            ),
          ),
        ),
        _PrincipleTile(
          title: 'Squash & stretch',
          blurb: 'The one playful beat — the paw-reaction pop.',
          // Motion.elasticPop is the scoped squash-&-stretch (reaction burst).
          child: _CurveLoop(
            curve: Motion.elasticPop,
            duration: Motion.slow,
            builder: (context, t) => Center(
              child: Transform.scale(
                scale: 0.4 + t * 0.6,
                child: const Text(
                  '🐾',
                  style: TextStyle(fontSize: Glyphs.burst),
                ),
              ),
            ),
          ),
        ),
        const _PrincipleTile(
          title: 'Staging',
          blurb: 'One focal motion at a time.',
          child: _StagingLoop(),
        ),
      ],
    );
  }
}

/// A labelled principle row: a fixed-width title + blurb on the left, the live
/// animated specimen framed on the right (mirrors the racer leading layout).
class _PrincipleTile extends StatelessWidget {
  const _PrincipleTile({
    required this.title,
    required this.blurb,
    required this.child,
  });

  final String title;
  final String blurb;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: TypeScale.semibold,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(blurb, style: t.caption.copyWith(color: c.textDim)),
              ],
            ),
          ),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.border),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The accent dot shared by the principle slides (matches the racer dot).
class _AccentDot extends StatelessWidget {
  const _AccentDot();

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.accent,
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: Opacities.pressed),
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// Loops a [curve]'s progress 0↔1 forever and hands [builder] the eased value,
/// so a principle's character (wind-up, overshoot, squash) reads at a glance.
/// Honors reduce motion: holds the settled end-state with no loop.
class _CurveLoop extends StatefulWidget {
  const _CurveLoop({
    required this.curve,
    required this.duration,
    required this.builder,
  });

  final Curve curve;
  final Duration duration;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_CurveLoop> createState() => _CurveLoopState();
}

class _CurveLoopState extends State<_CurveLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _controller.value = 1; // settled, no character
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => widget.builder(context, _t.value),
    );
  }
}

/// "Staging" — one focal motion at a time: a highlight travels across three
/// cards, only one raised at any moment. Honors reduce motion (static).
class _StagingLoop extends StatefulWidget {
  const _StagingLoop();

  @override
  State<_StagingLoop> createState() => _StagingLoopState();
}

class _StagingLoopState extends State<_StagingLoop>
    with SingleTickerProviderStateMixin {
  static const int _count = 3;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!context.reduceMotion) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final reduce = context.reduceMotion;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final active = (_controller.value * _count).floor() % _count;
        return Row(
          children: [
            for (var i = 0; i < _count; i++) ...[
              if (i > 0) const SizedBox(width: Spacing.md),
              Expanded(
                child: AnimatedScale(
                  scale: i == active ? 1.0 : 0.92,
                  duration: reduce ? Duration.zero : Motion.fast,
                  curve: Motion.standard,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: i == active
                          ? c.accent.withValues(alpha: Opacities.hover)
                          : c.surface,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: i == active ? c.accent : c.border,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Live demo of the staggered-cascade list reflow (Motion study variant C).
/// Toggling the presentation adds, removes and reorders cards; survivors glide
/// and arrivals ripple in top-to-bottom instead of the list hard-swapping.
/// Drives the *real* [collapseHistory] logic over fixed sample rows.
class MotionReflowSpecimen extends StatefulWidget {
  const MotionReflowSpecimen({super.key});

  @override
  State<MotionReflowSpecimen> createState() => _MotionReflowSpecimenState();
}

class _MotionReflowSpecimenState extends State<MotionReflowSpecimen> {
  HistoryMode _mode = HistoryMode.latestPerRoom;

  // Fixed clock + rows (gallery convention: deterministic, never DateTime.now).
  static final DateTime _now = DateTime(2026, 1, 7, 21, 0);
  static final List<HistoryEntry> _entries = [
    _demo(
      1,
      'The Bear — S03E08',
      'sleepy-otter',
      'lin',
      2850000,
      1122000,
      1503238553,
      2,
    ),
    _demo(
      2,
      'The Bear — S03E07',
      'sleepy-otter',
      'lin',
      2850000,
      2650000,
      1503238553,
      24,
    ),
    _demo(
      3,
      'Dune: Part Two',
      'cosmic-cat',
      'mochi',
      9960000,
      6120000,
      4402341478,
      48,
    ),
    _demo(
      4,
      'Spirited Away',
      'cosmic-cat',
      'mochi',
      7440000,
      1931000,
      2362232012,
      72,
    ),
    _demo(
      5,
      'Frieren — S01E12',
      'ghibli-night',
      'you',
      1440000,
      663000,
      754974720,
      120,
    ),
    _demo(
      6,
      'Frieren — S01E11',
      'ghibli-night',
      'you',
      1440000,
      1420000,
      734003200,
      144,
    ),
  ];

  static HistoryEntry _demo(
    int id,
    String title,
    String room,
    String user,
    int durationMs,
    int positionMs,
    int sizeBytes,
    int hoursAgo,
  ) => HistoryEntry(
    id: id,
    filePath: '/$title',
    fileName: title,
    fileSizeBytes: sizeBytes,
    durationMs: durationMs,
    lastPositionMs: positionMs,
    playedAt: _now.subtract(Duration(hours: hoursAgo)),
    room: room,
    username: user,
  );

  @override
  Widget build(BuildContext context) {
    final visible = collapseHistory(_entries, _mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReflowToggle(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
        const SizedBox(height: Spacing.md),
        StaggeredReflowList(
          children: [
            for (final e in visible)
              ReflowChild(
                id: e.id,
                child: _ReflowDemoCard(entry: e, now: _now),
              ),
          ],
        ),
      ],
    );
  }
}

/// Two-option segmented control with a sliding pill — mirrors the lobby's
/// Latest-per-room ⇄ Every-video switch, animated over the motion tokens.
class _ReflowToggle extends StatelessWidget {
  const _ReflowToggle({required this.mode, required this.onChanged});

  final HistoryMode mode;
  final ValueChanged<HistoryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    final isEvery = mode == HistoryMode.everyVideo;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: Motion.base,
              curve: Motion.standard,
              alignment: isEvery ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  margin: const EdgeInsets.all(Spacing.xxs),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: Opacities.hover),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: c.accent),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _segment(
                  'Latest per room',
                  !isEvery,
                  HistoryMode.latestPerRoom,
                  c,
                  t,
                ),
                _segment('Every video', isEvery, HistoryMode.everyVideo, c, t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    String label,
    bool selected,
    HistoryMode value,
    MeowColors c,
    MeowTextStyles t,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => onChanged(value),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: Motion.base,
            curve: Motion.standard,
            style: t.label.copyWith(
              color: selected ? c.accent : c.textDim,
              fontWeight: selected ? TypeScale.semibold : TypeScale.regular,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// Read-only twin of the lobby's Continue-watching card, for the gallery demo.
class _ReflowDemoCard extends StatelessWidget {
  const _ReflowDemoCard({required this.entry, required this.now});

  final HistoryEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    final frac = progressFraction(entry);
    final roomLine = historyRoomLine(entry);
    return Card(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.play_circle, color: c.accent),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textPrimary),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    historySubtitle(entry, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: c.textDim),
                  ),
                  if (roomLine != null) ...[
                    const SizedBox(height: Spacing.xxs),
                    Row(
                      children: [
                        Icon(Icons.groups, size: 12, color: c.accent),
                        const SizedBox(width: Spacing.xs),
                        Flexible(
                          child: Text(
                            roomLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.body.copyWith(color: c.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (frac != null) ...[
                    const SizedBox(height: Spacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.xs),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 4,
                        backgroundColor: c.border,
                        valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Icon(Icons.close, color: c.textDim, size: IconSizes.md),
          ],
        ),
      ),
    );
  }
}

/// The launch-reveal motion, live: a [RevealIn] demo you can replay and a
/// "Play full launch reveal" button that runs the real [LaunchReveal] over a
/// placeholder lobby. The replay tile lets the splash live in the design system.
class MotionRevealSpecimen extends StatefulWidget {
  const MotionRevealSpecimen({super.key});

  @override
  State<MotionRevealSpecimen> createState() => _MotionRevealSpecimenState();
}

class _MotionRevealSpecimenState extends State<MotionRevealSpecimen> {
  int _replayKey = 0; // bump to remount the RevealIn demo

  void _playFullReveal() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _FullRevealReplay()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // RevealIn demo — remounts on replay so the fade+rise replays.
        Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RevealIn(
                key: ValueKey('reveal-in-$_replayKey'),
                overshoot: true,
                child: Text(
                  'RevealIn',
                  style: t.title.copyWith(color: c.accent),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _replayKey++),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: const Text('Replay'),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        FilledButton.icon(
          onPressed: _playFullReveal,
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.background,
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play full launch reveal'),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Tip shown: “${kLaunchTips.first}”',
          style: t.caption.copyWith(color: c.textDim),
        ),
      ],
    );
  }
}

/// Full-screen replay of the real [LaunchReveal] over a placeholder lobby, so
/// the splash can be reviewed in the gallery exactly as it ships. A back button
/// is always present (the preview is never a dead end) and a Replay button
/// appears once the reveal has settled.
class _FullRevealReplay extends StatefulWidget {
  const _FullRevealReplay();

  @override
  State<_FullRevealReplay> createState() => _FullRevealReplayState();
}

class _FullRevealReplayState extends State<_FullRevealReplay> {
  int _key = 0; // bump to re-run the reveal
  bool _settled = false;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: c.backgroundGradient,
                color: c.backgroundGradient == null ? c.background : null,
              ),
              child: LaunchReveal(
                key: ValueKey('full-reveal-$_key'),
                onComplete: () {
                  if (mounted) setState(() => _settled = true);
                },
                // A faux lobby so the content-rise reads as real content
                // settling in, not a lone line of text slowly fading.
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Welcome back', style: t.heading),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Preview — the real lobby rises in here.',
                          style: t.body.copyWith(color: c.textDim),
                        ),
                        const SizedBox(height: Spacing.lg),
                        for (var i = 0; i < 2; i++) ...[
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(color: c.border),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Always on top of the splash, so the preview is never a dead end.
          Positioned(
            top: Spacing.md,
            left: Spacing.md,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Back',
                icon: Icon(Icons.arrow_back, color: c.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          if (_settled)
            Positioned(
              left: 0,
              right: 0,
              bottom: Spacing.xxl,
              child: Center(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.background,
                  ),
                  onPressed: () => setState(() {
                    _settled = false;
                    _key++;
                  }),
                  icon: const Icon(Icons.replay),
                  label: const Text('Replay'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Live [PressableScale] demo: a button + an icon that squash ~3% on press and
/// lift on hover, driving the real primitive so it degrades to an instant tap
/// target under reduce motion exactly as it does app-wide. Tapping either bumps
/// a counter so the press is unmistakably live.
class MotionPressableSpecimen extends StatefulWidget {
  const MotionPressableSpecimen({super.key});

  @override
  State<MotionPressableSpecimen> createState() =>
      _MotionPressableSpecimenState();
}

class _MotionPressableSpecimenState extends State<MotionPressableSpecimen> {
  int _presses = 0;

  void _bump() => setState(() => _presses++);

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PressableScale(
              onPressed: _bump,
              semanticLabel: 'Pressable button demo',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl,
                  vertical: Spacing.md,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Text(
                  'Press me',
                  style: t.label.copyWith(color: c.background),
                ),
              ),
            ),
            const SizedBox(width: Spacing.xl),
            PressableScale(
              onPressed: _bump,
              semanticLabel: 'Pressable icon demo',
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.border),
                ),
                child: Icon(Icons.pets, color: c.accent, size: IconSizes.lg),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Text(
          _presses == 0
              ? 'Press for the ~3% squash; hover for the lift. '
                    'Instant under reduce motion.'
              : 'Pressed $_presses ${_presses == 1 ? 'time' : 'times'}.',
          style: t.caption.copyWith(color: c.textDim),
        ),
      ],
    );
  }
}

class ShadowSpecimen extends StatelessWidget {
  const ShadowSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Wrap(
      spacing: Spacing.xxxl,
      runSpacing: Spacing.lg,
      children: [
        _Swatch(
          name: 'card',
          tile: Container(
            width: 96,
            height: 56,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              boxShadow: Shadows.card(c.scrim),
            ),
          ),
        ),
        _Swatch(
          name: 'overlay',
          tile: Container(
            width: 96,
            height: 56,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              boxShadow: Shadows.overlay(c.scrim),
            ),
          ),
        ),
      ],
    );
  }
}

/// Live real components so a token edit's effect is visible. Reuses the actual
/// widgets with deterministic sample data (fixed timestamp, never DateTime.now).
class ComponentZoo extends StatelessWidget {
  const ComponentZoo({super.key});

  @override
  Widget build(BuildContext context) {
    final stamp = DateTime(2026, 1, 1, 21, 4);
    const me = 'you';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChatBubble(
                message: ChatMessage(
                  username: 'Mochi',
                  text: 'this part is so good omg',
                  timestamp: stamp,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              ChatBubble(
                message: ChatMessage(
                  username: me,
                  text: 'right?? rewinding 10s',
                  timestamp: stamp,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              const ChatBubble(
                message: ChatMessage(
                  username: '',
                  text: '🐾 Mochi joined the room',
                  system: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        SizedBox(
          height: 320,
          child: EmptyState(
            onBrowse: () {},
            notice: 'lin started playback — load a video to join',
          ),
        ),
      ],
    );
  }
}

/// The brand mark at three sizes, plus the horizontal and stacked lockups, live
/// over the active theme — so a theme switch retints the logo here too.
class BrandSpecimen extends StatelessWidget {
  const BrandSpecimen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;

    Widget label(String s) => Text(
      s.toUpperCase(),
      style: t.caption.copyWith(
        color: c.textPrimary,
        letterSpacing: 1.5,
        fontWeight: TypeScale.semibold,
      ),
    );

    // Each specimen is a labelled tile, centred over its content; the row
    // spreads them across the card's full width — first flush left, last flush
    // right — and centres them vertically against the tallest tile.
    Widget tile(String name, Widget content) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        label(name),
        const SizedBox(height: Spacing.lg),
        content,
      ],
    );

    // double.infinity width forces the Wrap to take the card's full width;
    // without it the Wrap shrinks to its content and spaceBetween has no room
    // to spread the tiles to both edges.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: Spacing.xxl,
        children: [
          tile(
            'Mark',
            const Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MeowLogoMark(size: 32),
                SizedBox(width: Spacing.xl),
                MeowLogoMark(size: 48),
                SizedBox(width: Spacing.xl),
                MeowLogoMark(size: 72),
              ],
            ),
          ),
          tile('Horizontal lockup', const MeowLogo(markSize: 52, fontSize: 28)),
          tile(
            'Stacked',
            const MeowLogo(
              markSize: 56,
              fontSize: 26,
              axis: Axis.vertical,
              gap: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sections in display order. Used by the gallery screen.
List<Widget> gallerySections() => const [
  GallerySection(
    title: 'Brand',
    description:
        'The Neon Nine mark + Sora wordmark, tinted live to the active '
        'theme. Mark is pure vector; "Watch" + glow take the accent.',
    child: BrandSpecimen(),
  ),
  GallerySection(
    title: 'Color',
    description:
        'Ten roles per theme — only colour changes between Cozy, Cinema Noir, and Glass Aurora.',
    child: ColorSpecimen(),
  ),
  GallerySection(
    title: 'Typography',
    description:
        'Six roles. Size + weight are global; colour and font come from the active theme.',
    child: TypeSpecimen(),
  ),
  GallerySection(
    title: 'Radius',
    description: 'Six steps in even 4px increments.',
    child: RadiusSpecimen(),
  ),
  GallerySection(
    title: 'Spacing',
    description: 'Eight steps on a 4px grid for every gap and inset.',
    child: SpacingSpecimen(),
  ),
  GallerySection(
    title: 'Icon / Glyph',
    description:
        'Icon sizes, plus emoji glyph sizes (kept separate from text).',
    child: IconSpecimen(),
  ),
  GallerySection(
    title: 'Opacity',
    description: 'Named alpha levels for dim text, scrims, and states.',
    child: OpacitySpecimen(),
  ),
  GallerySection(
    title: 'Motion',
    description:
        'The shared timing and easing every transition draws from. '
        'Looping live so the difference is legible.',
    child: MotionSpecimen(),
  ),
  GallerySection(
    title: 'Motion · principles',
    description:
        'The Disney principles that map to UI, each a live looping specimen '
        'driving the real character curves. Under reduce motion they hold '
        'still — the character is exactly what reduce motion drops.',
    child: MotionPrinciplesSpecimen(),
  ),
  GallerySection(
    title: 'Motion · list reflow',
    description:
        'Toggling Latest per room ⇄ Every video adds, removes and reorders '
        'cards. The staggered cascade glides survivors and ripples arrivals '
        'in top-to-bottom instead of hard-swapping the list.',
    child: MotionReflowSpecimen(),
  ),
  GallerySection(
    title: 'Motion · reveal',
    description:
        'The cold-start launch reveal + its RevealIn primitive. Replay the '
        'RevealIn demo or play the full splash to review it as it ships.',
    child: MotionRevealSpecimen(),
  ),
  GallerySection(
    title: 'Motion · pressable',
    description:
        'The shared press feel — a few-percent squash on press, a subtle lift '
        'on hover. Press the button or icon to feel it; instant under reduce '
        'motion.',
    child: MotionPressableSpecimen(),
  ),
  GallerySection(
    title: 'Shadow',
    description: 'Two elevation tokens; colour follows each theme’s scrim.',
    child: ShadowSpecimen(),
  ),
  GallerySection(
    title: 'Components',
    description:
        'Real widgets, live — change a token and they all move with it.',
    child: ComponentZoo(),
  ),
];
