import 'dart:ui' show Offset;

/// Estimates where the pointer will be a few frames from now, so the dragged
/// chat card can be *rendered* slightly ahead of its true position.
///
/// Why: Flutter on Windows presents input roughly two to three frames after
/// the mouse moved (event batching to vsync + swapchain + DWM composition),
/// so a dragged widget visibly trails a fast-moving cursor — the gap grows
/// with speed. Rendering ahead by `velocity × latency` cancels most of that
/// gap while moving, and decays to nothing at rest so the grab point stays
/// exact when it matters (hover, drop).
///
/// Velocity comes from the drag deltas and their *source timestamps* (the
/// OS-stamped event times), smoothed with an exponential moving average so a
/// single noisy event can't kick the card around. Samples without usable
/// timestamps (null, non-advancing — e.g. synthetic test events) leave the
/// velocity untouched, so prediction gracefully degrades to "off".
class DragPredictor {
  /// How far ahead to render, in milliseconds. Matches the typical two-to-three
  /// frame input-to-photon latency of the Windows embedder at 60 Hz.
  static const double kHorizonMs = 40;

  /// Ceiling on the prediction distance so an extreme flick can never place
  /// the card absurdly far from the true drag position.
  static const double kMaxPredictionPx = 56;

  /// EMA weight of the newest velocity sample (higher = more responsive,
  /// lower = smoother).
  static const double kSmoothing = 0.35;

  /// A gap between samples longer than this means the pointer stalled — the
  /// old velocity is stale and must not predict the next move.
  static const Duration kStallGap = Duration(milliseconds: 100);

  Offset _velocityPxPerMs = Offset.zero;
  Duration? _lastTimestamp;

  /// Feed one drag update: [delta] px moved, stamped [sourceTimeStamp] (the
  /// pointer event's own clock; null when the platform didn't provide one).
  void addSample(Offset delta, Duration? sourceTimeStamp) {
    if (sourceTimeStamp == null) return;
    final last = _lastTimestamp;
    _lastTimestamp = sourceTimeStamp;
    if (last == null) return; // First sample only establishes the baseline.
    final dt = sourceTimeStamp - last;
    if (dt <= Duration.zero) return; // Synthetic/non-advancing clock: ignore.
    if (dt > kStallGap) {
      _velocityPxPerMs = Offset.zero;
      return;
    }
    final ms = dt.inMicroseconds / 1000.0;
    final instantaneous = delta / ms;
    _velocityPxPerMs =
        Offset.lerp(_velocityPxPerMs, instantaneous, kSmoothing)!;
  }

  /// Offset to add to the true drag position when rendering: `velocity ×
  /// horizon`, capped at [kMaxPredictionPx]. Zero at rest.
  Offset get prediction {
    final raw = _velocityPxPerMs * kHorizonMs;
    final distance = raw.distance;
    if (distance <= kMaxPredictionPx) return raw;
    return raw / distance * kMaxPredictionPx;
  }

  /// Forget everything (drag start/end): velocity and timestamp baseline.
  void reset() {
    _velocityPxPerMs = Offset.zero;
    _lastTimestamp = null;
  }
}
