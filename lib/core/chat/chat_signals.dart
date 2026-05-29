/// Lightweight "control messages" piggybacked on the Syncplay chat channel so
/// MeowWatch peers can exchange reactions and typing state without a second
/// protocol. A control message is an ordinary chat message whose text begins
/// with [chatControlSentinel]; the receiver parses and routes it instead of
/// showing it in the chat history.
///
/// Both peers run MeowWatch (the app assumes this), so the sentinel — which
/// starts with a SOH control character (U+0001) that cannot be typed — never
/// collides with real chat. A non-MeowWatch client would just see a short odd
/// line.
library;

/// Prefix marking a chat line as a MeowWatch control message.
const String chatControlSentinel = 'MW:';

/// A decoded control signal.
sealed class ChatSignal {
  const ChatSignal();
}

/// A peer sent a floating reaction (an emoji).
class ReactionSignal extends ChatSignal {
  const ReactionSignal(this.emoji);
  final String emoji;
}

/// A peer's typing state changed.
class TypingSignal extends ChatSignal {
  const TypingSignal(this.isTyping);
  final bool isTyping;
}

/// Parse [text] as a control message, or null if it is ordinary chat.
ChatSignal? parseChatControl(String text) {
  if (!text.startsWith(chatControlSentinel)) return null;
  final body = text.substring(chatControlSentinel.length);
  final sep = body.indexOf(':');
  final type = sep < 0 ? body : body.substring(0, sep);
  final payload = sep < 0 ? '' : body.substring(sep + 1);
  switch (type) {
    case 'react':
      return payload.isEmpty ? null : ReactionSignal(payload);
    case 'typing':
      return TypingSignal(payload == '1');
    default:
      return null;
  }
}

/// Encode a reaction control message for sending over the chat channel.
String encodeReaction(String emoji) => '${chatControlSentinel}react:$emoji';

/// Encode a typing-state control message.
String encodeTyping(bool isTyping) =>
    '${chatControlSentinel}typing:${isTyping ? '1' : '0'}';
