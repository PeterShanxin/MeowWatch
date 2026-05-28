import 'package:flutter/material.dart';

/// Message composer: a text field plus a send button. Fires [onSend] with the
/// trimmed text (never blank) and clears itself.
class ChatInput extends StatefulWidget {
  const ChatInput({super.key, required this.onSend});

  final void Function(String text) onSend;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(color: Color(0xFFF5E6D3), fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Message…',
                hintStyle: TextStyle(color: Color(0x66F5E6D3)),
                isDense: true,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0x55D4A574)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0x55D4A574)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD4A574)),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFFD4A574)),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
