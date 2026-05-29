import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';

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
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              style: TextStyle(color: m.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle:
                    TextStyle(color: m.textPrimary.withValues(alpha: 0.40)),
                isDense: true,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: m.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: m.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: m.accent),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: m.accent),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
