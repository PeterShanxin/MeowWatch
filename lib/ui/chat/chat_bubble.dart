import 'package:flutter/material.dart';

import '../../core/sync/peer_state.dart';
import '../../core/theme/meow_context.dart';
import '../../core/theme/meow_text.dart';
import '../../core/theme/tokens/radii.dart';
import '../../core/theme/tokens/spacing.dart';
import '../../core/theme/tokens/type_scale.dart';

/// One chat message. Own messages sit right (amber); the friend's sit left
/// (dark). A dim HH:MM time shows under the text.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  bool get _mine => message.isMine;

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final t = context.meowText;
    final ts = message.timestamp;

    // System/event lines (joins, leaves) render centered and dim — not bubbles.
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: Spacing.xs, horizontal: Spacing.md),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: t.caption.copyWith(
              color: m.textDim,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: _mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
            vertical: Spacing.xs, horizontal: Spacing.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          color: _mine ? m.myBubble : m.peerBubble,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: m.accent.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment:
              _mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_mine)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xxs),
                child: Text(
                  message.username,
                  style: t.caption.copyWith(
                    color: m.accent,
                    fontWeight: TypeScale.semibold,
                    fontFamily: m.titleFontFamily,
                  ),
                ),
              ),
            Text(
              message.text,
              style: t.body,
            ),
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xxs),
                child: Text(
                  _hhmm(ts),
                  style: t.caption.copyWith(color: m.textDim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
