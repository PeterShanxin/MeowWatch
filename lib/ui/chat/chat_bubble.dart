import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';

/// One chat message. Own messages sit right (amber); the friend's sit left
/// (dark). A dim HH:MM time shows under the text.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.myUsername,
  });

  final ChatMessage message;
  final String myUsername;

  bool get _mine => message.username == myUsername;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final ts = message.timestamp;

    // System/event lines (joins, leaves) render centered and dim — not bubbles.
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: m.textDim,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: _mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _mine ? m.myBubble : m.peerBubble,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: m.accent.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment:
              _mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.username,
                  style: TextStyle(
                    color: m.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: m.titleFontFamily,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(color: m.textPrimary, fontSize: 14),
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _hhmm(ts),
                  style: TextStyle(color: m.textDim, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
