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
    // The visible tab is a slim 14px, but a 14px-wide hit target is very easy
    // to miss (it read as "I have to tap twice"). Pad the gesture area out to a
    // comfortable ~40px and make it opaque so a near-miss still opens the chat.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 14,
          height: 64,
          decoration: BoxDecoration(
            color: pulsing ? m.accent : m.background.withValues(alpha: 0.80),
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(8)),
            border: Border.all(color: m.border),
          ),
          child: Center(
            child: Icon(Icons.chat_bubble_outline,
                size: 10, color: m.textPrimary),
          ),
        ),
      ),
    );
  }
}
