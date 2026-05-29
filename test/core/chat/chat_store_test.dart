import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/chat/chat_signals.dart';
import 'package:meowwatch/core/chat/chat_store.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/sync_core.dart';

class FakeSync extends SyncCore {
  final List<String> sent = <String>[];

  void incoming(ChatMessage m) => emitChat(m);

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
}
