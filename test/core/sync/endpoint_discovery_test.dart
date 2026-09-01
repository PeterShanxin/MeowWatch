import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/data/settings_store.dart';
import 'package:meowwatch/core/sync/endpoint_discovery.dart';
import 'package:meowwatch/core/sync/syncplay_endpoints.dart';

import '../../support/fakes.dart';

const _a = SyncplayEndpoint(host: 'syncplay.pl', port: 8995);
const _b = SyncplayEndpoint(host: 'syncplay.pl', port: 8996);
const _c = SyncplayEndpoint(host: 'syncplay.pl', port: 8997);
const _candidates = <SyncplayEndpoint>[_a, _b, _c];

/// Records every endpoint the discovery actually dialled, in order, and answers
/// from a fixed set of working endpoints.
class _RecordingProbe {
  _RecordingProbe(this.working);

  final Set<SyncplayEndpoint> working;
  final List<SyncplayEndpoint> tried = <SyncplayEndpoint>[];

  Future<bool> call(
    SyncplayEndpoint endpoint, {
    required Duration timeout,
  }) async {
    tried.add(endpoint);
    return working.contains(endpoint);
  }
}

SyncplayEndpointDiscovery _discovery(
  _RecordingProbe probe,
  FakeSettingsStore settings, {
  List<SyncplayEndpoint> candidates = _candidates,
}) {
  return SyncplayEndpointDiscovery(
    settings: settings,
    probe: probe.call,
    candidates: candidates,
  );
}

void main() {
  group('remembered endpoint', () {
    test('is tried first and short-circuits the scan', () async {
      final settings = FakeSettingsStore();
      await settings.set(kSyncplayEndpointSettingKey, _c.toString());
      final probe = _RecordingProbe({_a, _c});

      final resolved = await _discovery(probe, settings).resolve();

      expect(resolved, _c);
      expect(probe.tried, [
        _c,
      ], reason: 'a working remembered endpoint must not cost a scan');
    });

    test('is replaced when it no longer answers', () async {
      final settings = FakeSettingsStore();
      await settings.set(kSyncplayEndpointSettingKey, _c.toString());
      final probe = _RecordingProbe({_b});

      final resolved = await _discovery(probe, settings).resolve();

      expect(resolved, _b);
      expect(probe.tried, [_c, _a, _b]);
      expect(await settings.get(kSyncplayEndpointSettingKey), _b.toString());
    });

    test('is ignored when it is no longer a curated candidate', () async {
      final settings = FakeSettingsStore();
      await settings.set(kSyncplayEndpointSettingKey, 'retired.example:8995');
      final probe = _RecordingProbe({_a});

      final resolved = await _discovery(probe, settings).resolve();

      expect(resolved, _a);
      expect(
        probe.tried,
        [_a],
        reason: 'the curated list is the authority on what may be dialled',
      );
    });

    test('is ignored when the stored value is malformed', () async {
      final settings = FakeSettingsStore();
      await settings.set(kSyncplayEndpointSettingKey, 'not-an-endpoint');
      final probe = _RecordingProbe({_a});

      expect(await _discovery(probe, settings).resolve(), _a);
      expect(probe.tried, [_a]);
    });
  });

  group('scanning', () {
    test('falls through to the first candidate that answers', () async {
      final settings = FakeSettingsStore();
      final probe = _RecordingProbe({_c});

      final resolved = await _discovery(probe, settings).resolve();

      expect(resolved, _c);
      expect(probe.tried, [_a, _b, _c]);
    });

    test('stops probing once a winner is found', () async {
      final settings = FakeSettingsStore();
      final probe = _RecordingProbe({_b, _c});

      expect(await _discovery(probe, settings).resolve(), _b);
      expect(probe.tried, [_a, _b]);
    });

    test('persists the winner', () async {
      final settings = FakeSettingsStore();
      final probe = _RecordingProbe({_b});

      await _discovery(probe, settings).resolve();

      expect(await settings.get(kSyncplayEndpointSettingKey), _b.toString());
    });

    test(
      'returns null and remembers nothing when every candidate fails',
      () async {
        final settings = FakeSettingsStore();
        final probe = _RecordingProbe(const {});

        expect(await _discovery(probe, settings).resolve(), isNull);
        expect(probe.tried, [_a, _b, _c]);
        expect(await settings.get(kSyncplayEndpointSettingKey), isNull);
      },
    );

    test(
      'leaves a previously remembered endpoint alone when nothing answers',
      () async {
        final settings = FakeSettingsStore();
        await settings.set(kSyncplayEndpointSettingKey, _c.toString());
        final probe = _RecordingProbe(const {});

        expect(await _discovery(probe, settings).resolve(), isNull);
        expect(await settings.get(kSyncplayEndpointSettingKey), _c.toString());
      },
    );
  });

  group('preferred endpoint (a room that already lives somewhere)', () {
    test('is tried before anything else', () async {
      final settings = FakeSettingsStore();
      await settings.set(kSyncplayEndpointSettingKey, _a.toString());
      final probe = _RecordingProbe({_a, _c});

      final resolved = await _discovery(probe, settings).resolve(preferred: _c);

      expect(resolved, _c);
      expect(probe.tried, [_c]);
    });

    test(
      'falls back down the shared list, skipping the remembered winner',
      () async {
        // Two peers on the same dead room must not diverge just because their
        // remembered winners differ, so the remembered endpoint is not consulted
        // when a room already has an address.
        final settings = FakeSettingsStore();
        await settings.set(kSyncplayEndpointSettingKey, _c.toString());
        final probe = _RecordingProbe({_a, _c});

        final resolved = await _discovery(
          probe,
          settings,
        ).resolve(preferred: _b);

        expect(resolved, _a);
        expect(probe.tried, [_b, _a]);
      },
    );

    test('is never dialled when it is not a curated candidate', () async {
      // A self-hosted server must never be reached through discovery; the
      // caller pins those instead of asking for a scan.
      final settings = FakeSettingsStore();
      final probe = _RecordingProbe({_a});
      const selfHosted = SyncplayEndpoint(host: 'cozy.example.net', port: 8999);

      await _discovery(probe, settings).resolve(preferred: selfHosted);

      expect(probe.tried, isNot(contains(selfHosted)));
    });
  });

  test('a settings write failure does not fail the connect', () async {
    final probe = _RecordingProbe({_a});
    final discovery = SyncplayEndpointDiscovery(
      settings: _ThrowingSettingsStore(),
      probe: probe.call,
      candidates: _candidates,
    );

    expect(await discovery.resolve(), _a);
  });
}

class _ThrowingSettingsStore implements SettingsStore {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async =>
      throw StateError('disk full');

  @override
  Future<bool> hasAnySettings() async => false;
}
