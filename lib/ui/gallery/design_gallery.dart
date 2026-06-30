import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/reduce_motion.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import 'gallery_sections.dart';

/// Hidden design-system gallery: every token scale + the live component zoo,
/// switchable across all three themes. Reachable only via the version-badge
/// long-press or MEOWWATCH_GALLERY=1 (see version_badge.dart / main.dart).
///
/// Laid out as a centered, fixed-width "page" of framed panels so it reads like
/// a polished spec sheet rather than a window-wide list.
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});
  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  MeowThemeId _id = MeowThemeId.cozy;

  // Gallery-only preview: forces the degraded form across every specimen so the
  // reduced state can be reviewed without touching the OS setting. There is no
  // in-app global toggle — in normal use reduce motion comes from the OS.
  bool _reduceMotion = false;

  @override
  Widget build(BuildContext context) {
    // Force-on the reduce-motion scope when previewing, so the theme melt and
    // every section below read it via context.reduceMotion.
    return ReduceMotionScope(
      reduceMotion: _reduceMotion,
      child: Builder(
        builder: (context) {
          // Cross-fade the whole gallery between themes (MeowColors.lerp),
          // matching the app's theme melt; instant under reduce motion.
          return AnimatedTheme(
            data: themeDataFor(_id),
            duration: context.reduceMotion ? Duration.zero : Motion.slow,
            curve: Motion.emphasized,
            child: Builder(
              builder: (context) {
                final c = context.meow;
                final t = context.meowText;
                return Scaffold(
                  backgroundColor: c.background,
                  body: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: c.backgroundGradient,
                      color: c.backgroundGradient == null ? c.background : null,
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          _TopBar(
                            selected: _id,
                            onSelect: (id) => setState(() => _id = id),
                            reduceMotion: _reduceMotion,
                            onToggleReduceMotion: () =>
                                setState(() => _reduceMotion = !_reduceMotion),
                          ),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 900,
                                ),
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    Spacing.xl,
                                    Spacing.lg,
                                    Spacing.xl,
                                    Spacing.xxxl,
                                  ),
                                  children: [
                                    // Hero
                                    Text('Design System', style: t.display),
                                    const SizedBox(height: Spacing.xs),
                                    Text(
                                      'MeowWatch’s visual language — one source of truth for '
                                      'colour, type, space, shape, and motion.',
                                      style: t.body.copyWith(color: c.textDim),
                                    ),
                                    const SizedBox(height: Spacing.xs),
                                    Text(
                                      'v$appVersion · ${_id.label}',
                                      style: t.caption.copyWith(
                                        color: c.textDim,
                                      ),
                                    ),
                                    const SizedBox(height: Spacing.xl),
                                    ...gallerySections(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Back button on the left, the reduce-motion toggle + the three theme pills on
/// the right.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selected,
    required this.onSelect,
    required this.reduceMotion,
    required this.onToggleReduceMotion,
  });

  final MeowThemeId selected;
  final ValueChanged<MeowThemeId> onSelect;
  final bool reduceMotion;
  final VoidCallback onToggleReduceMotion;

  @override
  Widget build(BuildContext context) {
    final c = context.meow;
    final t = context.meowText;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: c.textPrimary),
          ),
          const SizedBox(width: Spacing.sm),
          // The reduce-motion toggle + theme pills sit in a right-anchored
          // horizontal scroll so they never overflow in a narrow window.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  // Preview the degraded form across every specimen.
                  _ThemePill(
                    label: 'Reduce motion',
                    selected: reduceMotion,
                    onTap: onToggleReduceMotion,
                    styles: t,
                    colors: c,
                  ),
                  const SizedBox(width: Spacing.lg),
                  for (final id in MeowThemeId.values)
                    Padding(
                      padding: const EdgeInsets.only(left: Spacing.sm),
                      child: _ThemePill(
                        label: id.label,
                        selected: id == selected,
                        onTap: () => onSelect(id),
                        styles: t,
                        colors: c,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePill extends StatelessWidget {
  const _ThemePill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.styles,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final MeowTextStyles styles;
  final MeowColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Material(
      color: selected ? c.accent : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.pill),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Text(
            label,
            style: styles.label.copyWith(
              color: selected ? c.background : c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
