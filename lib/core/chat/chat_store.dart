import 'dart:async';

import '../sync/peer_state.dart';
import '../sync/sync_core.dart';
import 'chat_signals.dart';

/// A reaction (floating emoji) received from a room member.
class ReactionEvent {
  const ReactionEvent({required this.username, required this.emoji});
  final String username;
  final String emoji;
}

/// A room member's typing state changed.
class TypingEvent {
  const TypingEvent({required this.username, required this.isTyping});
  final String username;
  final bool isTyping;
}

/// Holds the room's chat history and feeds it to the UI. Subscribes to
/// [SyncCore.chat], stamps each message's local arrival time, and republishes
/// the whole (immutable) list. Sending delegates to the sync core; the server
/// echoes our own message back on the same channel, so it lands in the list
/// through the normal receive path — no optimistic local insert.
///
/// Control messages (reactions, typing) ride the same chat channel with a
/// sentinel prefix; they are filtered out of the visible history and routed to
/// [reactions] / [typing] instead.
class ChatStore {
  // Fields are private; named params cannot start with an underscore, so
  // initializing formals don't apply here.
  // ignore_for_file: prefer_initializing_formals
  ChatStore({required SyncCore sync, DateTime Function() now = DateTime.now})
    : _sync = sync,
      _now = now {
    _connSub = _sync.connectionState.listen((state) {
      if (state.username != null && state.username!.isNotEmpty) {
        _myUsername = state.username;
      }
    });
    _sub = _sync.chat.listen(_onChat);
  }

  final SyncCore _sync;
  final DateTime Function() _now;
  late final StreamSubscription<ChatMessage> _sub;
  late final StreamSubscription<SyncConnectionState> _connSub;
  // The name the server currently has us under. The server may rename us on
  // (re)connect to dedupe a collision ("meow" -> "meow_"); we always track the
  // latest assignment. Ownership is stamped at receipt against this current
  // name only — we deliberately do NOT remember past names, because once the
  // server frees an old name a peer can claim it, and their messages must not
  // count as ours.
  String? _myUsername;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final StreamController<List<ChatMessage>> _controller =
      StreamController<List<ChatMessage>>.broadcast();
  final StreamController<ReactionEvent> _reactions =
      StreamController<ReactionEvent>.broadcast();
  final StreamController<TypingEvent> _typing =
      StreamController<TypingEvent>.broadcast();

  /// Fires the username of a peer who sent a [LeavingSignal] — meaning they are
  /// departing deliberately (clean leave). Peers that vanish without this signal
  /// are treated as connection drops.
  final StreamController<String> _leaving =
      StreamController<String>.broadcast();

  /// Current history, oldest first. Unmodifiable snapshot.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Fires the full list every time a message arrives.
  Stream<List<ChatMessage>> get stream => _controller.stream;

  /// Fires when a room member sends a reaction.
  Stream<ReactionEvent> get reactions => _reactions.stream;

  /// Fires when a room member's typing state changes.
  Stream<TypingEvent> get typing => _typing.stream;

  /// Fires the username of a peer who announced a deliberate leave. Consumed by
  /// the UI to distinguish "left the room" from "lost connection" when the
  /// server-side [PresenceKind.left] event arrives.
  Stream<String> get leaving => _leaving.stream;

  void _onChat(ChatMessage m) {
    final signal = parseChatControl(m.text);
    if (signal != null) {
      switch (signal) {
        case ReactionSignal(:final emoji):
          _reactions.add(ReactionEvent(username: m.username, emoji: emoji));
        case TypingSignal(:final isTyping):
          _typing.add(TypingEvent(username: m.username, isTyping: isTyping));
        case LeavingSignal():
          _leaving.add(m.username);
      }
      return; // Control messages never appear in chat history.
    }
    _messages.add(
      m.timestamp == null
          ? m.copyWith(timestamp: _now(), isMine: m.username == _myUsername)
          : m,
    );
    _controller.add(messages);
  }

  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _sync.sendChat(trimmed);
  }

  /// Append a local-only event line (e.g. "lin joined the room"). Not sent over
  /// the wire — each client annotates its own history.
  void addSystem(String text) {
    _messages.add(
      ChatMessage(username: '', text: text, timestamp: _now(), system: true),
    );
    _controller.add(messages);
  }

  /// Broadcast a floating reaction to the room.
  void sendReaction(String emoji) => _sync.sendChat(encodeReaction(emoji));

  /// Broadcast our typing state to the room.
  void sendTyping({required bool isTyping}) =>
      _sync.sendChat(encodeTyping(isTyping));

  Future<void> dispose() async {
    await _connSub.cancel();
    await _sub.cancel();
    await _controller.close();
    await _reactions.close();
    await _typing.close();
    await _leaving.close();
  }
}
