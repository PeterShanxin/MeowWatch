import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/ping_service.dart';

void main() {
  group('PingService', () {
    test('first RTT sample is adopted directly', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.rtt, closeTo(0.10, 1e-9));
    });

    test('subsequent samples are exponentially weighted', () {
      final ping = PingService(weight: 0.85);
      ping.recordRtt(0.10);
      ping.recordRtt(0.20);
      // 0.85*0.10 + 0.15*0.20 = 0.115
      expect(ping.rtt, closeTo(0.115, 1e-9));
    });

    test('forwardDelay is half the RTT', () {
      final ping = PingService();
      ping.recordRtt(0.10);
      expect(ping.forwardDelay, closeTo(0.05, 1e-9));
    });

    test('newTimestamp returns a monotonically sensible epoch seconds', () {
      final ping = PingService();
      final a = ping.newTimestamp();
      expect(a, greaterThan(0));
    });
  });
}
