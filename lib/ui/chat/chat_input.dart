import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sync/syncplay_constants.dart';
import '../../core/theme/meow_context.dart';

/// Message composer: a text field plus a send button. Fires [onSend] with the
/// trimmed text (never blank) and clears itself. While the user is typing it
/// pulses [onTypingChanged] true, then false after a short idle (or on send).
///
/// Plain Enter sends; Shift+Enter inserts a newline (#56). The field is capped
/// at [SyncplayConstants.maxChatMessageLength] with a counter near the limit, so
/// the server's silent truncation can never eat the tail of a long message
/// (#55).
class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    this.onTypingChanged,
    this.focusNode,
    this.controller,
  });

  final void Function(String text) onSend;
  final ValueChanged<bool>? onTypingChanged;

  /// Supplied by the overlay so it can focus the field when the card is opened.
  final FocusNode? focusNode;

  /// Externally-owned draft controller. The overlay lifts ownership up to a
  /// State that outlives the input subtree, so a typed-but-unsent draft survives
  /// focus loss, window minimize/restore, and chat collapse (#59). When null the
  /// input owns a private controller (back-compat for standalone use/tests).
  final TextEditingController? controller;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  /// Only created (and disposed) when the caller didn't hand us one. An external
  /// controller is owned by the parent and must outlive this State.
  TextEditingController? _ownController;
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  Timer? _typingIdle;
  bool _typing = false;
  static const _typingIdleDelay = Duration(milliseconds: 1800);

  @override
  void dispose() {
    _typingIdle?.cancel();
    _ownController?.dispose();
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
    widget.focusNode?.requestFocus();
  }

  /// Plain Enter sends; Shift+Enter falls through so the multiline field inserts
  /// a newline. Consuming the plain-Enter key event suppresses the default
  /// newline insertion on desktop (#56).
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event is! KeyDownEvent || !isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored; // let the field insert a newline
    }
    _submit();
    return KeyEventResult.handled;
  }

  /// Hide the counter until the message is within 30 chars of the cap, so the
  /// composer stays clean for normal-length messages but warns before the
  /// server would truncate.
  Widget? _buildCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) {
    const showFrom = SyncplayConstants.maxChatMessageLength - 30;
    if (maxLength == null || currentLength < showFrom) return null;
    final m = context.meow;
    final atLimit = currentLength >= maxLength;
    return Text(
      '$currentLength/$maxLength',
      style: TextStyle(
        color: atLimit ? Colors.redAccent : m.textPrimary.withValues(alpha: 0.5),
        fontSize: 11,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: _onKeyEvent,
              // Pure key-interceptor: it must never take focus itself, or
              // desktop Tab traversal could land on this invisible wrapper
              // (typed chars go nowhere, yet Enter still submits). It stays in
              // the tree as an ancestor, so _onKeyEvent still fires while the
              // TextField below is focused.
              canRequestFocus: false,
              skipTraversal: true,
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                onChanged: _onChanged,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLength: SyncplayConstants.maxChatMessageLength,
                buildCounter: _buildCounter,
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
