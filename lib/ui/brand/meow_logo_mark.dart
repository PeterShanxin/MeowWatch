import 'package:flutter/widgets.dart';

import '../../core/theme/meow_context.dart';

/// The MeowWatch "Neon Nine" mark: a rounded-square cat face with cat-eye slits
/// and a nose dot. Drawn in a 64×64 space and tinted to one [color] (defaults to
/// the theme accent). Pure vector — no asset, crisp at any size. Geometry is
/// verbatim from the Neon Nine design handoff.
class MeowLogoMark extends StatelessWidget {
  const MeowLogoMark({super.key, this.size = 40, this.color});

  final double size;

  /// Tint for the whole mark; falls back to the live theme accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.meow.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MeowLogoMarkPainter(tint)),
    );
  }
}

class _MeowLogoMarkPainter extends CustomPainter {
  _MeowLogoMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in the design's native 64×64 space, then scale to the widget size so
    // every coordinate and stroke width below is verbatim from the handoff.
    canvas.save();
    canvas.scale(size.width / 64.0, size.height / 64.0);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    // Ears (stroke 2.6, no fill).
    line.strokeWidth = 2.6;
    canvas.drawPath(
      _triangle(const Offset(19, 17), const Offset(22, 6), const Offset(32, 15)),
      line,
    );
    canvas.drawPath(
      _triangle(const Offset(45, 17), const Offset(42, 6), const Offset(32, 15)),
      line,
    );

    // Head: rounded square (13,15) 38×38, corner radius 14.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 15, 38, 38),
        const Radius.circular(14),
      ),
      line,
    );

    // Cat-eye slits (stroke 3.2).
    line.strokeWidth = 3.2;
    canvas.drawLine(const Offset(25, 30), const Offset(25, 38), line);
    canvas.drawLine(const Offset(39, 30), const Offset(39, 38), line);

    // Nose dot.
    canvas.drawCircle(const Offset(32, 42), 1.7, fill);

    canvas.restore();
  }

  Path _triangle(Offset a, Offset b, Offset c) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..close();

  @override
  bool shouldRepaint(_MeowLogoMarkPainter old) => old.color != color;
}
