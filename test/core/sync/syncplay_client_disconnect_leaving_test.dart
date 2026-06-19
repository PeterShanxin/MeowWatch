import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/chat/chat_signals.dart';
import 'package:meowwatch/core/sync/syncplay_client.dart';

/// disconnect() must broadcast a leaving signal before tearing down when
/// the client is logged in, so peers can distinguish a clean leave from a
/// connection drop (issue #92).
void main() {
  late SyncplayClient client;

  setUp(() {
    client = SyncplayClient();
  });

  tearDown(() => client.dispose());

  test('disconnect sends leaving signal when logged in', () async {
    client.debugMarkLoggedIn('me');

    await client.disconnect();

    // The leaving control message should appear in captured outbound sends.
    expect(
      client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
      isTrue,
      reason: 'disconnect() must send a leaving signal before closing',
    );
  });

  test('disconnect sends nothing when not logged in', () async {
    // Deliberately not calling debugMarkLoggedIn — client is not logged in.
    await client.disconnect();

    expect(client.debugSentMessages, isEmpty);
  });

  test('app-close disconnect sends leaving signal synchronously', () {
    client.debugMarkLoggedIn('me');

    client.disconnectForAppClose();

    expect(
      client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
      isTrue,
      reason: 'window close must announce leaving without awaiting a socket',
    );
  });

  test(
    'app close (dispose) also sends a leaving signal when logged in',
    () async {
      client.debugMarkLoggedIn('me');

      await client.dispose();

      expect(
        client.debugSentMessages.any((m) => m['Chat'] == encodeLeaving()),
        isTrue,
        reason: 'closing the app should announce a deliberate departure',
      );
    },
  );

  test('leave then dispose does not double-send the leaving signal', () async {
    client.debugMarkLoggedIn('me');

    await client.disconnect();
    await client.dispose();

    final leavingCount = client.debugSentMessages
        .where((m) => m['Chat'] == encodeLeaving())
        .length;
    expect(leavingCount, 1);
  });
}
