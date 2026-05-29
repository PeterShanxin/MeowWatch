import 'package:flutter/material.dart';

import '../../core/theme/meow_context.dart';

/// The emoji palette offered by the reaction button.
const List<String> kReactionEmojis = <String>['❤️', '😂', '👍', '😮', '🎉', '🔥'];

/// A small bottom-right control: a smiley button that expands a row of emoji.
/// Tapping an emoji fires [onReact] (which broadcasts it to the room) and
/// collapses the row.
class ReactionBar extends StatefulWidget {
  const ReactionBar({required this.onReact, super.key});

  final ValueChanged<String> onReact;

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  bool _open = false;

  void _pick(String emoji) {
    widget.onReact(emoji);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: _open
              ? Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: m.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: m.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in kReactionEmojis)
                        IconButton(
                          key: Key('reaction-$e'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pick(e),
                          icon: Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Material(
          color: m.background.withValues(alpha: 0.80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: m.border),
          ),
          child: IconButton(
            key: const Key('reaction-toggle'),
            tooltip: 'React',
            icon: Icon(
              _open ? Icons.close : Icons.add_reaction_outlined,
              color: m.textPrimary,
              size: 20,
            ),
            onPressed: () => setState(() => _open = !_open),
          ),
        ),
      ],
    );
  }
}
