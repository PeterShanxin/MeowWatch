import 'dart:async';

import '../sync/peer_state.dart';
import '../sync/sync_core.dart';

/// Holds the room's chat history and feeds it to the UI. Subscribes to
/// [SyncCore.chat], stamps each message's local arrival time, and republishes
/// the whole (immutable) list. Sending delegates to the sync core; the server
/// echoes our own message back on the same channel, so it lands in the list
/// through the normal receive path — no optimistic local insert.
class ChatStore {
  // Fields are private; named params cannot start with an underscore, so
  // initializing formals don't apply here.
  // ignore_for_file: prefer_initializing_formals
  ChatStore({required SyncCore sync, DateTime Function() now = DateTime.now})
      : _sync = sync,
        _now = now {
    _sub = _sync.chat.listen(_onChat);
  }

  final SyncCore _sync;
  final DateTime Function() _now;
  late final StreamSubscription<ChatMessage> _sub;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final StreamController<List<ChatMessage>> _controller =
      StreamController<List<ChatMessage>>.broadcast();

  /// Current history, oldest first. Unmodifiable snapshot.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Fires the full list every time a message arrives.
  Stream<List<ChatMessage>> get stream => _controller.stream;

  void _onChat(ChatMessage m) {
    _messages.add(m.timestamp == null ? m.copyWith(timestamp: _now()) : m);
    _controller.add(messages);
  }

  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _sync.sendChat(trimmed);
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _controller.close();
  }
}
