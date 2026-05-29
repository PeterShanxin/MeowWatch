import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';

/// Message composer: a text field plus a send button. Fires [onSend] with the
/// trimmed text (never blank) and clears itself. While the user is typing it
/// pulses [onTypingChanged] true, then false after a short idle (or on send).
class ChatInput extends StatefulWidget {
  const ChatInput({super.key, required this.onSend, this.onTypingChanged});

  final void Function(String text) onSend;
  final ValueChanged<bool>? onTypingChanged;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  Timer? _typingIdle;
  bool _typing = false;
  static const _typingIdleDelay = Duration(milliseconds: 1800);

  @override
  void dispose() {
    _typingIdle?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _setTyping(bool value) {
    if (_typing == value) return;
    _typing = value;
    widget.onTypingChanged?.call(value);
  }

  void _onChanged(String text) {
    if (text.trim().isEmpty) {
      _typingIdle?.cancel();
      _setTyping(false);
      return;
    }
    _setTyping(true);
    _typingIdle?.cancel();
    _typingIdle = Timer(_typingIdleDelay, () => _setTyping(false));
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _typingIdle?.cancel();
    _setTyping(false);
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
              onChanged: _onChanged,
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
