import 'package:flutter/material.dart';

/// The collapsed chat: a 14px tab hugging the right edge. Tap to expand.
/// [pulsing] brightens it to hint at a freshly arrived message.
class PeekTab extends StatelessWidget {
  const PeekTab({super.key, required this.pulsing, required this.onTap});

  final bool pulsing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 14,
        height: 64,
        decoration: BoxDecoration(
          color: pulsing ? const Color(0xFFD4A574) : const Color(0xCC1A1410),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          border: Border.all(color: const Color(0x55D4A574)),
        ),
        child: const Center(
          child: Icon(Icons.chat_bubble_outline,
              size: 10, color: Color(0xFFF5E6D3)),
        ),
      ),
    );
  }
}
