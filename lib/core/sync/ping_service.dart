/// Tracks RTT as an exponential moving average and derives the one-way forward
/// delay used to latency-compensate a peer's reported position. Mirrors
/// upstream's PingService (PING_MOVING_AVERAGE_WEIGHT = 0.85).
class PingService {
  PingService({this.weight = 0.85});

  final double weight;
  double _rtt = 0.0;
  bool _hasSample = false;

  double get rtt => _rtt;

  /// One-way delay estimate (half the round trip).
  double get forwardDelay => _rtt / 2.0;

  void recordRtt(double sample) {
    if (!_hasSample) {
      _rtt = sample;
      _hasSample = true;
    } else {
      _rtt = weight * _rtt + (1 - weight) * sample;
    }
  }

  /// Epoch seconds as a double, sent as clientLatencyCalculation so the peer's
  /// echo lets us measure RTT on the next State.
  double newTimestamp() => DateTime.now().millisecondsSinceEpoch / 1000.0;
}

/// Round-trip time sample (seconds) derived from the server echoing back the
/// clientLatencyCalculation timestamp we previously sent: the round trip is
/// simply `now - echoed`. Returns null when there is no echo, or when the
/// result is negative (clock skew or a stale echo), mirroring upstream
/// Syncplay's guard so a bad sample never pollutes the moving average.
double? rttSampleFromEcho({
  required double? echoedTimestamp,
  required double nowEpochSeconds,
}) {
  if (echoedTimestamp == null) return null;
  final rtt = nowEpochSeconds - echoedTimestamp;
  if (rtt < 0) return null;
  return rtt;
}
