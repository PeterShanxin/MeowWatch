/// Throttles how often a high-frequency interaction event re-arms the UI idle
/// timer.
///
/// Pointer hover/move can fire hundreds of times a second. Re-arming the idle
/// countdown means cancelling and allocating a `Timer` — cheap once, but wasteful
/// churn when it happens on every raw pointer event and the idle delay is
/// measured in seconds. [shouldRearm] returns true at most once per
/// [minInterval]; the caller re-arms the timer only then. The idle countdown may
/// therefore fire up to [minInterval] earlier than the exact last event, which is
/// imperceptible against a multi-second delay.
///
/// Waking *from* idle is handled separately by the caller and stays immediate —
/// call [reset] on wake so the next event re-arms without waiting out the window.
///
/// Pure and clock-injected (the caller passes a monotonic elapsed [Duration],
/// e.g. from a `Stopwatch`), so it is unit-tested without any timers or pumping.
class IdleRearmThrottle {
  IdleRearmThrottle({this.minInterval = const Duration(milliseconds: 200)});

  final Duration minInterval;
  Duration? _lastRearm;

  /// Whether the interaction at [now] should re-arm the idle timer. Returns true
  /// on the first call and whenever at least [minInterval] has elapsed since the
  /// last re-arm, advancing the baseline to [now] when it does.
  bool shouldRearm(Duration now) {
    final last = _lastRearm;
    if (last == null || now - last >= minInterval) {
      _lastRearm = now;
      return true;
    }
    return false;
  }

  /// Forget the last re-arm so the next [shouldRearm] returns true immediately —
  /// used when waking from idle, where the timer must re-arm without delay.
  void reset() => _lastRearm = null;
}
