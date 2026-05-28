import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';

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
    final ts = message.timestamp;
    return Align(
      alignment: _mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _mine ? const Color(0x33D4A574) : const Color(0x55241B14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x33D4A574)),
        ),
        child: Column(
          crossAxisAlignment:
              _mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: const TextStyle(color: Color(0xFFF5E6D3), fontSize: 14),
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _hhmm(ts),
                  style:
                      const TextStyle(color: Color(0x99F5E6D3), fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
