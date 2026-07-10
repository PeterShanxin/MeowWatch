import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/chat/drag_predictor.dart';

void main() {
  test('no samples means no prediction', () {
    final p = DragPredictor();
    expect(p.prediction, Offset.zero);
  });

  test('a single sample cannot establish velocity (no dt yet)', () {
    final p = DragPredictor();
    p.addSample(const Offset(10, 0), const Duration(milliseconds: 8));
    expect(p.prediction, Offset.zero);
  });

  test('steady rightward motion predicts ahead along +x', () {
    final p = DragPredictor();
    // 10 px every 8 ms = 1.25 px/ms rightward.
    for (var i = 0; i < 20; i++) {
      p.addSample(const Offset(10, 0), Duration(milliseconds: 8 * i));
    }
    expect(p.prediction.dx, greaterThan(0));
    expect(p.prediction.dy, 0);
    // Prediction is velocity * horizon: 1.25 px/ms * horizon, unless capped.
    final expected = 1.25 * DragPredictor.kHorizonMs;
    expect(
      p.prediction.dx,
      closeTo(
        expected > DragPredictor.kMaxPredictionPx
            ? DragPredictor.kMaxPredictionPx
            : expected,
        1.0,
      ),
    );
  });

  test('prediction distance is capped for very fast motion', () {
    final p = DragPredictor();
    for (var i = 0; i < 20; i++) {
      // 200 px every 8 ms — absurdly fast.
      p.addSample(const Offset(200, 0), Duration(milliseconds: 8 * i));
    }
    expect(
      p.prediction.distance,
      lessThanOrEqualTo(DragPredictor.kMaxPredictionPx + 0.001),
    );
  });

  test('non-advancing timestamps are ignored (synthetic events)', () {
    final p = DragPredictor();
    p.addSample(const Offset(40, 0), Duration.zero);
    p.addSample(const Offset(40, 0), Duration.zero);
    p.addSample(const Offset(40, 0), Duration.zero);
    expect(p.prediction, Offset.zero);
  });

  test('missing timestamps are ignored', () {
    final p = DragPredictor();
    p.addSample(const Offset(40, 0), null);
    p.addSample(const Offset(40, 0), null);
    expect(p.prediction, Offset.zero);
  });

  test('a long stall between samples resets the velocity', () {
    final p = DragPredictor();
    for (var i = 0; i < 10; i++) {
      p.addSample(const Offset(10, 0), Duration(milliseconds: 8 * i));
    }
    expect(p.prediction.dx, greaterThan(0));
    // The pointer held still well past the stall window, then moved once:
    // the old velocity must not survive the gap.
    p.addSample(const Offset(1, 0), const Duration(milliseconds: 5000));
    expect(p.prediction, Offset.zero);
  });

  test('reset clears velocity and sample history', () {
    final p = DragPredictor();
    for (var i = 0; i < 10; i++) {
      p.addSample(const Offset(10, 0), Duration(milliseconds: 8 * i));
    }
    p.reset();
    expect(p.prediction, Offset.zero);
    // The first sample after a reset re-establishes the baseline, not a dt.
    p.addSample(const Offset(10, 0), const Duration(milliseconds: 100));
    expect(p.prediction, Offset.zero);
  });

  test('slowing down shrinks the prediction', () {
    final p = DragPredictor();
    var t = 0;
    for (var i = 0; i < 10; i++) {
      p.addSample(const Offset(20, 0), Duration(milliseconds: t += 8));
    }
    final fast = p.prediction.dx;
    for (var i = 0; i < 10; i++) {
      p.addSample(const Offset(1, 0), Duration(milliseconds: t += 8));
    }
    final slow = p.prediction.dx;
    expect(slow, lessThan(fast));
  });
}
