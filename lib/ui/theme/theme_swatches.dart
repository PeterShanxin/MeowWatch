import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_theme.dart';

/// A row of tappable color chips, one per theme preset. The active one shows a
/// ring. Tapping fires [onChanged].
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({
    required this.current,
    required this.onChanged,
    super.key,
  });

  final MeowThemeId current;
  final ValueChanged<MeowThemeId> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final id in MeowThemeId.values)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              key: Key('theme-swatch-${id.name}'),
              onTap: () => onChanged(id),
              child: Tooltip(
                message: id.label,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: id.colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: id == current ? m.textPrimary : m.border,
                      width: id == current ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
