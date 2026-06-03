import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';
import '../../core/theme/tokens/spacing.dart';
import 'gallery_sections.dart';

/// Hidden design-system gallery: every token scale + the live component zoo,
/// switchable across all three themes. Reachable only via the version-badge
/// long-press or MEOWWATCH_GALLERY=1 (see version_badge.dart / main.dart).
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});
  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  MeowThemeId _id = MeowThemeId.cozy;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: themeDataFor(_id),
      child: Builder(builder: (context) {
        final c = context.meow;
        return Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.surface,
            foregroundColor: c.textPrimary,
            title: const Text('Design Gallery'),
            actions: [
              for (final id in MeowThemeId.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: Spacing.sm),
                  child: ChoiceChip(
                    label: Text(id.label),
                    selected: _id == id,
                    onSelected: (_) => setState(() => _id = id),
                  ),
                ),
              const SizedBox(width: Spacing.md),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Spacing.xl),
            children: const [
              GallerySection(title: 'Typography', child: TypeSpecimen()),
              GallerySection(title: 'Radius', child: RadiusSpecimen()),
              GallerySection(title: 'Spacing', child: SpacingSpecimen()),
              GallerySection(title: 'Icon / Glyph', child: IconSpecimen()),
              GallerySection(title: 'Opacity', child: OpacitySpecimen()),
              GallerySection(title: 'Motion + Shadow', child: MotionAndShadowSpecimen()),
              GallerySection(title: 'Components', child: ComponentZoo()),
            ],
          ),
        );
      }),
    );
  }
}
