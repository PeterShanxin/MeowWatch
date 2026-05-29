import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';

/// The collapsed chat: a 14px tab hugging the right edge. Tap to expand.
/// [pulsing] brightens it to hint at a freshly arrived message.
class PeekTab extends StatelessWidget {
  const PeekTab({super.key, required this.pulsing, required this.onTap});

  final bool pulsing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 14,
        height: 64,
        decoration: BoxDecoration(
          color: pulsing ? m.accent : m.background.withValues(alpha: 0.80),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          border: Border.all(color: m.border),
        ),
        child: Center(
          child: Icon(Icons.chat_bubble_outline,
              size: 10, color: m.textPrimary),
        ),
      ),
    );
  }
}
