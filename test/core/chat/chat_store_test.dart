import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/chat/chat_signals.dart';
import 'package:meowwatch/core/chat/chat_store.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';

class FakeSync extends SyncCore {
  final List<String> sent = <String>[];

  void incoming(ChatMessage m) => emitChat(m);

  void connectedAs(String username) => emitConnectionState(
    SyncConnectionState(
      status: SyncConnectionStatus.connected,
      username: username,
    ),
  );

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) => sent.add(text);

  @override
  Future<void> disposeBackend() async {}
}

void main() {
  test('appends incoming messages in order', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));
    sync.incoming(const ChatMessage(username: 'me', text: 'yo'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.map((m) => m.text), ['hi', 'yo']);
    await store.dispose();
    await sync.dispose();
  });

  test('stamps arrival time using the injected clock', () async {
    final sync = FakeSync();
    final fixed = DateTime(2026, 5, 28, 21, 43);
    final store = ChatStore(sync: sync, now: () => fixed);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.single.timestamp, fixed);
    await store.dispose();
    await sync.dispose();
  });

  test('emits the updated list on its stream', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final future = store.stream.first;

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));

    final list = await future;
    expect(list.single.text, 'hi');
    await store.dispose();
    await sync.dispose();
  });

  test('send delegates to sync.sendChat', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    store.send('hello');

    expect(sync.sent, ['hello']);
    await store.dispose();
    await sync.dispose();
  });

  test('control messages are routed, not shown in history', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final reaction = store.reactions.first;
    final typing = store.typing.first;

    sync.incoming(ChatMessage(username: 'lin', text: encodeReaction('🎉')));
    sync.incoming(ChatMessage(username: 'lin', text: encodeTyping(true)));
    sync.incoming(const ChatMessage(username: 'lin', text: 'real msg'));
    await Future<void>.delayed(Duration.zero);

    expect((await reaction).emoji, '🎉');
    expect((await reaction).username, 'lin');
    expect((await typing).isTyping, isTrue);
    // Only the real message reaches chat history.
    expect(store.messages.map((m) => m.text), ['real msg']);

    await store.dispose();
    await sync.dispose();
  });

  test('sendReaction / sendTyping emit encoded control messages', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    store.sendReaction('👍');
    store.sendTyping(isTyping: true);

    expect(sync.sent, [encodeReaction('👍'), encodeTyping(true)]);
    await store.dispose();
    await sync.dispose();
  });

  test('leaving signal routes to leaving stream, not chat history', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final leavingFuture = store.leaving.first;

    sync.incoming(
      ChatMessage(username: 'lin', text: encodeLeaving()),
    );
    sync.incoming(const ChatMessage(username: 'bob', text: 'real msg'));
    await Future<void>.delayed(Duration.zero);

    expect(await leavingFuture, 'lin');
    // Leaving signal must not appear in history.
    expect(store.messages.map((m) => m.text), ['real msg']);

    await store.dispose();
    await sync.dispose();
  });

  test(
    'addSystem inserts a local system line, not sent over the wire',
    () async {
      final sync = FakeSync();
      final store = ChatStore(sync: sync);

      store.addSystem('lin joined the room');
      await Future<void>.delayed(Duration.zero);

      expect(sync.sent, isEmpty); // never transmitted
      final msg = store.messages.single;
      expect(msg.system, isTrue);
      expect(msg.text, 'lin joined the room');
      expect(msg.timestamp, isNotNull);

      await store.dispose();
      await sync.dispose();
    },
  );

  test('stamps isMine on messages from our assigned username', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.connectedAs('meow');
    sync.incoming(const ChatMessage(username: 'meow', text: 'mine'));
    sync.incoming(const ChatMessage(username: 'lin', text: 'theirs'));
    await Future<void>.delayed(Duration.zero);

    final byText = {for (final m in store.messages) m.text: m.isMine};
    expect(byText['mine'], isTrue);
    expect(byText['theirs'], isFalse);
    await store.dispose();
    await sync.dispose();
  });

  test('a message arriving before any connection state is not mine', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.incoming(const ChatMessage(username: 'meow', text: 'early'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.single.isMine, isFalse);
    await store.dispose();
    await sync.dispose();
  });

  test('tracks ownership across a reconnect rename (collision dedupe)', () async {
    // The server can hand us a different name on reconnect ("meow" -> "meow_").
    // Ownership is stamped at receipt against our *current* name, so a message
    // received while we were "meow" stays ours, and our later echoes arrive
    // under "meow_". This is the #40/#77 flip the fix targets.
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.connectedAs('meow');
    sync.incoming(const ChatMessage(username: 'meow', text: 'before'));
    sync.connectedAs('meow_');
    sync.incoming(const ChatMessage(username: 'meow_', text: 'after'));
    // A peer has since claimed the name the server freed when it renamed us.
    // Their messages under the old name must NOT count as ours.
    sync.incoming(const ChatMessage(username: 'meow', text: 'peer-took-old'));
    sync.incoming(const ChatMessage(username: 'lin', text: 'peer'));
    await Future<void>.delayed(Duration.zero);

    final byText = {for (final m in store.messages) m.text: m.isMine};
    expect(byText['before'], isTrue); // stamped while we were "meow"
    expect(byText['after'], isTrue); // our echo under the new name
    expect(byText['peer-took-old'], isFalse); // freed name, now a peer's
    expect(byText['peer'], isFalse);
    await store.dispose();
    await sync.dispose();
  });
}
