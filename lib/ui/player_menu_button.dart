import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import 'theme/theme_swatches.dart';

/// Top-left in-player control: a gear button that opens a small anchored
/// popover holding the theme swatches and a "Leave room" action. Replaces the
/// bare Leave button so theme switching is a deliberate pick (not a blind
/// cycle) while watching.
class PlayerMenuButton extends StatelessWidget {
  const PlayerMenuButton({
    required this.currentTheme,
    required this.onThemeChanged,
    required this.onLeave,
    super.key,
  });

  final MeowThemeId currentTheme;
  final ValueChanged<MeowThemeId> onThemeChanged;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(m.surface),
        side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: m.border)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.fromLTRB(14, 12, 14, 8),
        ),
      ),
      builder: (context, controller, _) => Material(
        color: m.background.withValues(alpha: 0.80),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: m.border),
        ),
        child: IconButton(
          key: const Key('player-menu-gear'),
          tooltip: 'Options',
          icon: Icon(Icons.settings, size: 18, color: m.textPrimary),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
      menuChildren: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Theme',
                  style: TextStyle(color: m.textDim, fontSize: 13)),
            ),
            ThemeSwatches(current: currentTheme, onChanged: onThemeChanged),
            const SizedBox(height: 8),
            Divider(color: m.border, height: 16),
            InkWell(
              key: const Key('player-menu-leave'),
              borderRadius: BorderRadius.circular(8),
              onTap: onLeave,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 16, color: m.textPrimary),
                    const SizedBox(width: 8),
                    Text('Leave room',
                        style: TextStyle(color: m.textPrimary, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
