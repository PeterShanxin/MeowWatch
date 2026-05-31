import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/theme/meow_context.dart';
import 'update_dialog.dart';

/// A subtle version chip anchored to the bottom-right of a parent [Stack].
///
/// Tapping it opens the [UpdateDialog] to check for and apply updates.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Tooltip(
      message: "Updates & what's new",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const UpdateDialog(),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: m.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: m.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pets, size: 12, color: m.textDim),
                const SizedBox(width: 5),
                Text(
                  'v$appVersion',
                  style: TextStyle(
                    color: m.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
