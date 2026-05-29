import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';

/// Persistent indicator shown while the user holds the seek keys. Three
/// chevrons march in the seek direction and the accumulated jump is shown.
class SeekIndicator extends StatefulWidget {
  const SeekIndicator({
    required this.forward,
    required this.seconds,
    super.key,
  });

  final bool forward;
  final int seconds;

  @override
  State<SeekIndicator> createState() => _SeekIndicatorState();
}

class _SeekIndicatorState extends State<SeekIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final icon =
        widget.forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    final label = '${widget.forward ? '+' : '-'}${widget.seconds}s';
    final chevrons = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each chevron's brightness so they appear to march in the
            // seek direction: left-to-right for forward, right-to-left for back.
            final idx = widget.forward ? i : (2 - i);
            final phase = (_controller.value * 3 - idx) % 3;
            final lit = phase >= 0 && phase < 1;
            return Icon(
              icon,
              size: 30,
              color: lit ? m.accent : m.textPrimary.withValues(alpha: 0.35),
            );
          }),
        );
      },
    );

    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: m.scrim.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection:
                widget.forward ? TextDirection.ltr : TextDirection.rtl,
            children: [
              chevrons,
              const SizedBox(width: 10),
              Text(
                label,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: m.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
