import 'package:flutter/material.dart';

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

  static const _cream = Color(0xFFF5E6D3);
  static const _amber = Color(0xFFD4A574);

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
    final icon =
        widget.forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    final label = '${widget.forward ? '+' : '-'}${widget.seconds}s';
    final chevrons = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger each chevron's brightness so they appear to march.
            final phase = (_controller.value * 3 - i) % 3;
            final lit = phase >= 0 && phase < 1;
            return Icon(
              icon,
              size: 30,
              color: lit ? _amber : _cream.withValues(alpha: 0.35),
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
            color: const Color(0x99000000),
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
                style: const TextStyle(
                  color: _cream,
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
