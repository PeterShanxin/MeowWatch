import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/opacities.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/shadows.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../chat/chat_bubble.dart';
import '../empty_state.dart';

/// A titled block with a small uppercase header.
class GallerySection extends StatelessWidget {
  const GallerySection({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: context.meowText.caption.copyWith(
                color: c.accent,
                letterSpacing: 1.5,
                fontWeight: TypeScale.semibold,
              )),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

class TypeSpecimen extends StatelessWidget {
  const TypeSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final rows = <(String, TextStyle)>[
      ('caption 11', t.caption),
      ('body 13', t.body),
      ('label 15', t.label),
      ('title 18', t.title),
      ('heading 24', t.heading),
      ('display 30', t.display),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, style) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(width: 96, child: Text(name, style: t.caption.copyWith(color: context.meow.textDim))),
                const SizedBox(width: Spacing.md),
                Text('The quick brown fox', style: style),
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
      ('xs', Radii.xs), ('sm', Radii.sm), ('md', Radii.md),
      ('lg', Radii.lg), ('xl', Radii.xl), ('pill', Radii.pill),
    ];
    return Wrap(spacing: Spacing.lg, runSpacing: Spacing.md, children: [
      for (final (name, r) in steps)
        Column(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: c.myBubble,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(r),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text('$name ${r.toInt()}', style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
    ]);
  }
}

class SpacingSpecimen extends StatelessWidget {
  const SpacingSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    const steps = <double>[
      Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
      Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl,
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final s in steps)
        Padding(
          padding: const EdgeInsets.only(right: Spacing.md),
          child: Column(children: [
            Container(width: s, height: 32, color: c.accent),
            const SizedBox(height: Spacing.xs),
            Text(s.toInt().toString(), style: context.meowText.caption.copyWith(color: c.textDim)),
          ]),
        ),
    ]);
  }
}

class IconSpecimen extends StatelessWidget {
  const IconSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('16', IconSizes.sm), ('20', IconSizes.md), ('24', IconSizes.lg), ('32', IconSizes.xl),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final (name, s) in steps)
        Padding(
          padding: const EdgeInsets.only(right: Spacing.lg),
          child: Column(children: [
            Icon(Icons.pets, size: s, color: c.accent),
            Text(name, style: context.meowText.caption.copyWith(color: c.textDim)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(left: Spacing.md),
        child: Column(children: [
          const Text('🐾', style: TextStyle(fontSize: Glyphs.react)),
          Text('react 20', style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
      ),
      Column(children: [
        const Text('🐾', style: TextStyle(fontSize: Glyphs.burst)),
        Text('burst 34', style: context.meowText.caption.copyWith(color: c.textDim)),
      ]),
    ]);
  }
}

class OpacitySpecimen extends StatelessWidget {
  const OpacitySpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final steps = <(String, double)>[
      ('dim', Opacities.dim), ('scrim', Opacities.scrim),
      ('disabled', Opacities.disabled), ('pressed', Opacities.pressed), ('hover', Opacities.hover),
    ];
    return Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: [
      for (final (name, a) in steps)
        Column(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: a),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          ),
          Text(name, style: context.meowText.caption.copyWith(color: c.textDim)),
        ]),
    ]);
  }
}

class MotionAndShadowSpecimen extends StatelessWidget {
  const MotionAndShadowSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    String ms(Duration d) => '${d.inMilliseconds}ms';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('fast ${ms(Motion.fast)} · base ${ms(Motion.base)} · slow ${ms(Motion.slow)}',
          style: context.meowText.body.copyWith(color: c.textDim)),
      const SizedBox(height: Spacing.lg),
      Row(children: [
        Container(width: 80, height: 48,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: Shadows.card(c.scrim))),
        const SizedBox(width: Spacing.xxl),
        Container(width: 80, height: 48,
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: Shadows.overlay(c.scrim))),
      ]),
    ]);
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
        // All three bubble states from one widget.
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChatBubble(
                message: ChatMessage(username: 'Mochi', text: 'this part is so good omg', timestamp: stamp),
                myUsername: me,
              ),
              const SizedBox(height: Spacing.xs),
              ChatBubble(
                message: ChatMessage(username: me, text: 'right?? rewinding 10s', timestamp: stamp),
                myUsername: me,
              ),
              const SizedBox(height: Spacing.xs),
              const ChatBubble(
                message: ChatMessage(username: '', text: '🐾 Mochi joined the room', system: true),
                myUsername: me,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        // EmptyState fills its parent — give it a bounded box in the gallery list.
        SizedBox(
          height: 320,
          child: EmptyState(onBrowse: () {}, notice: 'lin started playback — load a video to join'),
        ),
      ],
    );
  }
}
