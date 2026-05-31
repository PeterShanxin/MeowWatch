import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';

/// The local user's own play/pause/seek must surface as a [SyncActivity] on the
/// `activity` stream (issue #27). The Syncplay client classifies the change in
/// `notifyLocalChange`, comparing the new local state against the prior one it
/// has been fed via `updateLocalState`.
void main() {
  late SyncplayClient client;
  late List<SyncActivity> events;

  setUp(() {
    client = SyncplayClient();
    events = <SyncActivity>[];
    client.activity.listen(events.add);
  });

  tearDown(() => client.dispose());

  test('local pause is announced with our username and position', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(position: const Duration(seconds: 30), paused: false);
    client.updateLocalState(position: const Duration(seconds: 30), paused: true);
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single.kind, SyncActivityKind.paused);
    expect(events.single.username, 'me');
    expect(events.single.position, const Duration(seconds: 30));
  });

  test('local forward seek is announced at the landing position', () async {
    client.debugMarkLoggedIn('me');
    client.updateLocalState(position: const Duration(seconds: 10), paused: false);
    client.updateLocalState(position: const Duration(seconds: 90), paused: false);
    client.notifyLocalChange(doSeek: true);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.kind, SyncActivityKind.seekedForward);
    expect(events.single.position, const Duration(seconds: 90));
  });

  test('nothing announced before login (no username to attribute)', () async {
    client.updateLocalState(position: const Duration(seconds: 30), paused: false);
    client.updateLocalState(position: const Duration(seconds: 30), paused: true);
    client.notifyLocalChange(doSeek: false);
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
  });
}
