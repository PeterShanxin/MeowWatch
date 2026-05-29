import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';

/// A cute, hand-painted cat face that gently "breathes" and blinks. Shown on
/// the idle/empty screen so MeowWatch feels alive while waiting for a video.
/// Theme-aware: drawn in the active palette's accent colour.
class IdleMascot extends StatefulWidget {
  const IdleMascot({this.size = 96, super.key});

  final double size;

  @override
  State<IdleMascot> createState() => _IdleMascotState();
}

class _IdleMascotState extends State<IdleMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // One slow loop drives both the breath (sine) and a brief blink near the
    // end of each cycle.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.meow.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final breathe = 1 + 0.03 * math.sin(t * 2 * math.pi);
          // Eyes shut briefly once per loop.
          final blinking = t > 0.90 && t < 0.96;
          return Transform.scale(
            scale: breathe,
            child: CustomPaint(
              painter: _CatPainter(color: accent, blinking: blinking),
            ),
          );
        },
      ),
    );
  }
}

class _CatPainter extends CustomPainter {
  _CatPainter({required this.color, required this.blinking});

  final Color color;
  final bool blinking;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final solid = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = w / 2;
    final cy = h * 0.56;
    final headR = w * 0.34;

    // Ears (filled triangles) above the head.
    final earH = h * 0.26;
    final earSpread = headR * 0.78;
    for (final dir in <double>[-1, 1]) {
      final baseX = cx + dir * earSpread;
      final path = Path()
        ..moveTo(baseX - w * 0.10, cy - headR * 0.55)
        ..lineTo(baseX + dir * w * 0.02, cy - headR * 0.55 - earH)
        ..lineTo(baseX + w * 0.10, cy - headR * 0.30)
        ..close();
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, stroke);
    }

    // Head.
    canvas
      ..drawCircle(Offset(cx, cy), headR, fill)
      ..drawCircle(Offset(cx, cy), headR, stroke);

    // Eyes.
    final eyeDx = headR * 0.42;
    final eyeY = cy - headR * 0.08;
    final eyeR = headR * 0.12;
    for (final dir in <double>[-1, 1]) {
      final ex = cx + dir * eyeDx;
      if (blinking) {
        canvas.drawLine(
          Offset(ex - eyeR, eyeY),
          Offset(ex + eyeR, eyeY),
          stroke,
        );
      } else {
        canvas.drawCircle(Offset(ex, eyeY), eyeR, solid);
      }
    }

    // Nose (small downward triangle).
    final noseY = cy + headR * 0.14;
    final noseW = headR * 0.12;
    final nose = Path()
      ..moveTo(cx - noseW, noseY)
      ..lineTo(cx + noseW, noseY)
      ..lineTo(cx, noseY + noseW)
      ..close();
    canvas.drawPath(nose, solid);

    // Mouth (two little arcs forming a soft "w").
    final mouthY = noseY + noseW;
    for (final dir in <double>[-1, 1]) {
      final rect = Rect.fromCircle(
        center: Offset(cx + dir * headR * 0.14, mouthY),
        radius: headR * 0.16,
      );
      canvas.drawArc(rect, math.pi * 0.15, math.pi * 0.7, false, stroke);
    }

    // Whiskers.
    final whiskerY = cy + headR * 0.16;
    for (final dir in <double>[-1, 1]) {
      final startX = cx + dir * headR * 0.30;
      for (final dy in <double>[-headR * 0.16, 0, headR * 0.16]) {
        canvas.drawLine(
          Offset(startX, whiskerY + dy * 0.4),
          Offset(startX + dir * headR * 0.95, whiskerY + dy),
          stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CatPainter old) =>
      old.blinking != blinking || old.color != color;
}
