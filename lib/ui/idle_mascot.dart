import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';

/// A hand-painted sitting cat that idles on the empty screen so MeowWatch feels
/// alive while waiting for a video. Theme-aware (drawn in the active accent),
/// and animated: it breathes, its tail wags, an ear twitches, and it blinks.
class IdleMascot extends StatefulWidget {
  const IdleMascot({this.size = 128, super.key});

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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
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
          return CustomPaint(
            painter: _CatPainter(
              color: accent,
              // Breathing: noticeable chest rise/fall.
              breathe: 1 + 0.05 * math.sin(t * 2 * math.pi),
              // Tail wag: a full sweep each loop.
              tailWag: math.sin(t * 2 * math.pi),
              // Ear twitch: a brief flick once per loop.
              earTwitch: (t > 0.55 && t < 0.62) ? 1.0 : 0.0,
              // Blink: eyes shut briefly.
              blinking: t > 0.92 && t < 0.97,
            ),
          );
        },
      ),
    );
  }
}

class _CatPainter extends CustomPainter {
  _CatPainter({
    required this.color,
    required this.breathe,
    required this.tailWag,
    required this.earTwitch,
    required this.blinking,
  });

  final Color color;
  final double breathe;
  final double tailWag;
  final double earTwitch;
  final bool blinking;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final solid = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final innerEar = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final cx = w / 2;

    // --- Tail (drawn first, behind the body) — wags side to side. -----------
    final tailBase = Offset(w * 0.70, h * 0.82);
    final wag = tailWag * w * 0.10;
    final tail = Path()
      ..moveTo(tailBase.dx, tailBase.dy)
      ..cubicTo(
        w * 0.92, h * 0.86,
        w * 0.98 + wag, h * 0.66,
        w * 0.86 + wag, h * 0.52,
      );
    canvas.drawPath(tail, line..strokeWidth = w * 0.05);
    line.strokeWidth = w * 0.02;

    // --- Body: a rounded sitting torso, breathing vertically. ---------------
    final chest = h * (0.50 - (breathe - 1) * 0.4);
    final bodyPath = Path()
      ..moveTo(cx - w * 0.22, h * 0.92)
      ..cubicTo(
          cx - w * 0.30, chest, cx - w * 0.16, h * 0.40, cx, h * 0.40)
      ..cubicTo(
          cx + w * 0.16, h * 0.40, cx + w * 0.30, chest, cx + w * 0.22, h * 0.92)
      ..close();
    canvas
      ..drawPath(bodyPath, body)
      ..drawPath(bodyPath, line);

    // Front paws.
    for (final dir in <double>[-1, 1]) {
      final paw = Rect.fromCenter(
        center: Offset(cx + dir * w * 0.11, h * 0.90),
        width: w * 0.16,
        height: w * 0.11,
      );
      canvas
        ..drawRRect(
            RRect.fromRectAndRadius(paw, Radius.circular(w * 0.05)), body)
        ..drawRRect(
            RRect.fromRectAndRadius(paw, Radius.circular(w * 0.05)), line);
    }

    // --- Head ----------------------------------------------------------------
    final headCy = h * 0.34;
    final headR = w * 0.26;

    // Ears (outer + inner), left twitches.
    for (final dir in <double>[-1, 1]) {
      canvas.save();
      final earBaseX = cx + dir * headR * 0.72;
      if (dir < 0 && earTwitch > 0) {
        canvas
          ..translate(earBaseX, headCy - headR * 0.5)
          ..rotate(-0.18 * earTwitch)
          ..translate(-earBaseX, -(headCy - headR * 0.5));
      }
      final outer = Path()
        ..moveTo(earBaseX - w * 0.085, headCy - headR * 0.45)
        ..lineTo(earBaseX + dir * w * 0.03, headCy - headR * 1.05)
        ..lineTo(earBaseX + w * 0.085, headCy - headR * 0.30)
        ..close();
      final inner = Path()
        ..moveTo(earBaseX - w * 0.045, headCy - headR * 0.52)
        ..lineTo(earBaseX + dir * w * 0.02, headCy - headR * 0.92)
        ..lineTo(earBaseX + w * 0.045, headCy - headR * 0.44)
        ..close();
      canvas
        ..drawPath(outer, body)
        ..drawPath(outer, line)
        ..drawPath(inner, innerEar);
      canvas.restore();
    }

    // Head circle (slightly wider than tall for a cat cheek look).
    final headRect = Rect.fromCenter(
        center: Offset(cx, headCy), width: headR * 2.1, height: headR * 1.9);
    canvas
      ..drawOval(headRect, body)
      ..drawOval(headRect, line);

    // Eyes — almond shaped, with a pupil + highlight; blink = a closed arc.
    final eyeDx = headR * 0.46;
    final eyeY = headCy - headR * 0.04;
    for (final dir in <double>[-1, 1]) {
      final ex = cx + dir * eyeDx;
      if (blinking) {
        final blink = Path()
          ..moveTo(ex - headR * 0.16, eyeY)
          ..quadraticBezierTo(ex, eyeY + headR * 0.12, ex + headR * 0.16, eyeY);
        canvas.drawPath(blink, line);
      } else {
        final eye = Rect.fromCenter(
            center: Offset(ex, eyeY), width: headR * 0.34, height: headR * 0.44);
        canvas
          ..drawOval(eye, solid)
          // catchlight highlight
          ..drawCircle(Offset(ex - headR * 0.06, eyeY - headR * 0.10),
              headR * 0.05, Paint()..color = Colors.white.withValues(alpha: 0.85));
      }
    }

    // Nose.
    final noseY = headCy + headR * 0.22;
    final noseW = headR * 0.12;
    final nose = Path()
      ..moveTo(cx - noseW, noseY)
      ..lineTo(cx + noseW, noseY)
      ..lineTo(cx, noseY + noseW)
      ..close();
    canvas.drawPath(nose, solid);

    // Mouth — soft "w" under the nose.
    for (final dir in <double>[-1, 1]) {
      final rect = Rect.fromCircle(
          center: Offset(cx + dir * headR * 0.13, noseY + noseW * 1.1),
          radius: headR * 0.15);
      canvas.drawArc(rect, math.pi * 0.15, math.pi * 0.7, false, line);
    }

    // Whiskers — three per side, gently fanned.
    final whiskerY = headCy + headR * 0.22;
    for (final dir in <double>[-1, 1]) {
      final startX = cx + dir * headR * 0.34;
      for (final dy in <double>[-headR * 0.14, 0, headR * 0.14]) {
        canvas.drawLine(
          Offset(startX, whiskerY + dy * 0.4),
          Offset(startX + dir * headR * 1.1, whiskerY + dy),
          line,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CatPainter old) =>
      old.breathe != breathe ||
      old.tailWag != tailWag ||
      old.earTwitch != earTwitch ||
      old.blinking != blinking ||
      old.color != color;
}
