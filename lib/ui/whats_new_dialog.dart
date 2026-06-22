import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/tokens/icon_sizes.dart';
import '../core/theme/tokens/radii.dart';
import '../core/theme/tokens/spacing.dart';
import '../core/theme/tokens/type_scale.dart';
import '../core/update/update_service.dart';
import 'changelog_view.dart';

/// One-time, dismissable modal shown on the first launch after an update. It
/// presents the just-installed version's highlights using the same hero card as
/// the updater's "What's new" panel (via [ChangelogView] with a single entry),
/// so there is one consistent presentation and no duplicate layout code.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({super.key, required this.entry});

  /// The just-installed version's changelog entry.
  final ChangelogEntry entry;

  /// Show the modal over [context]. Barrier-dismissable; completes on dismiss.
  static Future<void> show(BuildContext context, ChangelogEntry entry) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WhatsNewDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Dialog(
      backgroundColor: m.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: m.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.celebration, color: m.accent, size: IconSizes.md),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'MeowWatch updated',
                      style: TextStyle(
                        color: m.textPrimary,
                        fontSize: TypeScale.title,
                        fontWeight: TypeScale.semibold,
                        fontFamily: m.titleFontFamily,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: m.textDim, size: IconSizes.md),
                    splashRadius: IconSizes.md,
                    tooltip: 'Dismiss',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              ChangelogView(entries: [entry]),
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Got it',
                    style: TextStyle(
                      color: m.accent,
                      fontSize: TypeScale.body,
                      fontWeight: TypeScale.semibold,
                    ),
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
