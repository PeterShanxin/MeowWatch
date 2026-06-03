import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';
import '../../core/theme/tokens/motion.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';

/// The collapsed chat: a 14px tab hugging the right edge. Tap to expand.
/// [pulsing] brightens it to hint at a freshly arrived message; [typing]
/// brightens it and shows an animated three-dot indicator so you can tell a
/// peer is typing without expanding the card (#53). An unread count badge wins
/// over the typing dots when both apply.
class PeekTab extends StatelessWidget {
  const PeekTab({
    super.key,
    required this.pulsing,
    required this.unreadCount,
    required this.onTap,
    this.typing = false,
  });

  final bool pulsing;
  final bool typing;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    // Brighten the tab when a message just arrived (pulsing) or a peer is
    // typing — both are "something's happening in chat" cues.
    final bright = pulsing || typing;
    // Widen a touch when it carries content (unread badge or typing dots) so it
    // doesn't feel cramped.
    final hasContent = unreadCount > 0 || typing;
    // The visible tab is a slim 14px, but a 14px-wide hit target is very easy
    // to miss (it read as "I have to tap twice"). Pad the gesture area out to a
    // comfortable ~40px and make it opaque so a near-miss still opens the chat.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: Spacing.lg, horizontal: Spacing.md),
        child: AnimatedContainer(
          duration: Motion.slow,
          width: hasContent ? 22 : 14,
          height: 64,
          decoration: BoxDecoration(
            color: bright ? m.accent : m.background.withValues(alpha: 0.80),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(Radii.sm),
            ),
            border: Border.all(color: m.border),
          ),
          child: Center(child: _content(m)),
        ),
      ),
    );
  }

  Widget _content(dynamic m) {
    // Priority: an unread count badge, then the typing dots, then the idle icon.
    if (unreadCount > 0) {
      return Container(
        padding: const EdgeInsets.all(Spacing.xxs),
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          unreadCount > 99 ? '99+' : unreadCount.toString(),
          style: const TextStyle(
            color: Colors.white,
            // 9px badge text is sized to the slim 22px tab — below the
            // TypeScale.caption (11) floor on purpose; '99+' bold at 11px
            // crowds/overflows the circle. Kept off-scale like the 10px glyph.
            fontSize: 9,
            fontWeight: TypeScale.bold,
            height: 1,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (typing) {
      // Dots are dark on the brightened (accent) tab so they read clearly.
      return _PeekTypingDots(color: m.background as Color);
    }
    // 10px glyph is sized to the slim 14px tab — below the IconSizes scale (16+)
    // on purpose; snapping it up would overflow the tab.
    return Icon(
      Icons.chat_bubble_outline,
      size: 10,
      color: m.textPrimary as Color,
    );
  }
}

/// Three small dots stacked vertically (the tab is narrow and tall), each
/// fading in and out in turn — a compact "…is typing" animation for the
/// collapsed peek tab.
class _PeekTypingDots extends StatefulWidget {
  const _PeekTypingDots({required this.color});

  final Color color;

  @override
  State<_PeekTypingDots> createState() => _PeekTypingDotsState();
}

class _PeekTypingDotsState extends State<_PeekTypingDots>
    with SingleTickerProviderStateMixin {
  // 1100ms is the bespoke typing-cycle period, not a UI transition — kept off
  // the Motion scale.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (i) {
            // Stagger each dot a third of a cycle apart, then ease its opacity
            // up and back down with a triangle wave.
            final phase = (_ctrl.value - i / 3) % 1.0;
            final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final opacity = 0.3 + 0.7 * wave;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
