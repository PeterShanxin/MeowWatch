import 'package:flutter/material.dart';

import '../../core/data/history_collapse.dart';
import '../../core/data/history_entry.dart';
import '../../core/data/history_mode.dart';
import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/icon_sizes.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/opacities.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/shadows.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';
import '../chat/chat_bubble.dart';
import '../connect/history_format.dart';
import '../empty_state.dart';
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
                  child: Text('${rows[i].$1} ${rows[i].$2}',
                      style: t.caption.copyWith(color: c.textDim)),
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Text('The quick brown fox',
                      style: rows[i].$3, overflow: TextOverflow.ellipsis),
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
      ('xs', Radii.xs), ('sm', Radii.sm), ('md', Radii.md),
      ('lg', Radii.lg), ('xl', Radii.xl), ('pill', Radii.pill),
    ];
    return Wrap(spacing: Spacing.lg, runSpacing: Spacing.lg, children: [
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
      ('16', IconSizes.sm), ('20', IconSizes.md), ('24', IconSizes.lg), ('32', IconSizes.xl),
    ];
    return Wrap(spacing: Spacing.xl, runSpacing: Spacing.md, crossAxisAlignment: WrapCrossAlignment.end, children: [
      for (final (name, s) in steps)
        _Swatch(name: name, tile: Icon(Icons.pets, size: s, color: c.accent)),
      const _Swatch(
        name: 'react · 20',
        tile: Text('🐾', style: TextStyle(fontSize: Glyphs.react)),
      ),
      const _Swatch(
        name: 'burst · 34',
        tile: Text('🐾', style: TextStyle(fontSize: Glyphs.burst)),
      ),
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
    return Wrap(spacing: Spacing.lg, runSpacing: Spacing.lg, children: [
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
    ]);
  }
}

class MotionSpecimen extends StatelessWidget {
  const MotionSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.meowText;
    final c = context.meow;
    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.sm),
          decoration: BoxDecoration(
            color: c.myBubble,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: c.border),
          ),
          child: Text(text, style: t.caption.copyWith(color: c.textPrimary)),
        );
    return Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: [
      chip('fast · ${Motion.fast.inMilliseconds}ms'),
      chip('base · ${Motion.base.inMilliseconds}ms'),
      chip('slow · ${Motion.slow.inMilliseconds}ms'),
      chip('stagger · ${Motion.stagger.inMilliseconds}ms'),
      chip('standard · easeOutCubic'),
      chip('symmetric · easeInOut'),
    ]);
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
    _demo(1, 'The Bear — S03E08', 'sleepy-otter', 'lin', 2850000, 1122000,
        1503238553, 2),
    _demo(2, 'The Bear — S03E07', 'sleepy-otter', 'lin', 2850000, 2650000,
        1503238553, 24),
    _demo(3, 'Dune: Part Two', 'cosmic-cat', 'mochi', 9960000, 6120000,
        4402341478, 48),
    _demo(4, 'Spirited Away', 'cosmic-cat', 'mochi', 7440000, 1931000,
        2362232012, 72),
    _demo(5, 'Frieren — S01E12', 'ghibli-night', 'you', 1440000, 663000,
        754974720, 120),
    _demo(6, 'Frieren — S01E11', 'ghibli-night', 'you', 1440000, 1420000,
        734003200, 144),
  ];

  static HistoryEntry _demo(int id, String title, String room, String user,
          int durationMs, int positionMs, int sizeBytes, int hoursAgo) =>
      HistoryEntry(
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
        _ReflowToggle(
          mode: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: Spacing.md),
        StaggeredReflowList(
          children: [
            for (final e in visible)
              ReflowChild(id: e.id, child: _ReflowDemoCard(entry: e, now: _now)),
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
                _segment('Latest per room', !isEvery, HistoryMode.latestPerRoom,
                    c, t),
                _segment('Every video', isEvery, HistoryMode.everyVideo, c, t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool selected, HistoryMode value, MeowColors c,
      MeowTextStyles t) {
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

class ShadowSpecimen extends StatelessWidget {
  const ShadowSpecimen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    return Wrap(spacing: Spacing.xxxl, runSpacing: Spacing.lg, children: [
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
        SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChatBubble(
                message: ChatMessage(username: 'Mochi', text: 'this part is so good omg', timestamp: stamp),
              ),
              const SizedBox(height: Spacing.xs),
              ChatBubble(
                message: ChatMessage(username: me, text: 'right?? rewinding 10s', timestamp: stamp),
              ),
              const SizedBox(height: Spacing.xs),
              const ChatBubble(
                message: ChatMessage(username: '', text: '🐾 Mochi joined the room', system: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),
        SizedBox(
          height: 320,
          child: EmptyState(onBrowse: () {}, notice: 'lin started playback — load a video to join'),
        ),
      ],
    );
  }
}

/// The sections in display order. Used by the gallery screen.
List<Widget> gallerySections() => const [
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
        description: 'Icon sizes, plus emoji glyph sizes (kept separate from text).',
        child: IconSpecimen(),
      ),
      GallerySection(
        title: 'Opacity',
        description: 'Named alpha levels for dim text, scrims, and states.',
        child: OpacitySpecimen(),
      ),
      GallerySection(
        title: 'Motion',
        description: 'Durations + easings shared by every transition.',
        child: MotionSpecimen(),
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
        title: 'Shadow',
        description: 'Two elevation tokens; colour follows each theme’s scrim.',
        child: ShadowSpecimen(),
      ),
      GallerySection(
        title: 'Components',
        description: 'Real widgets, live — change a token and they all move with it.',
        child: ComponentZoo(),
      ),
    ];
