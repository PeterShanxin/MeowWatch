// lib/ui/changelog_markdown.dart
import 'package:flutter/material.dart';

import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/update/changelog_markup.dart';

typedef IssueTapCallback = void Function(int number);

/// Renders parsed changelog [sections] with theme colors. Bold/code/issue-ref
/// inline runs and bullet lists are painted; `### Added/Fixed/Improved` headings
/// become category chips (toggle with [showTags]).
class ChangelogMarkdown extends StatelessWidget {
  const ChangelogMarkdown({
    super.key,
    required this.sections,
    required this.onIssueTap,
    this.showTags = true,
  });

  final List<NoteSection> sections;
  final IssueTapCallback onIssueTap;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final m = context.meow;
    final children = <Widget>[];
    for (final s in sections) {
      if (s.tag != null) {
        if (showTags) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: ChangelogTagChip(tag: s.tag!, label: s.chipLabel),
          ));
        }
      } else if (s.title != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            s.title!,
            style: TextStyle(
              color: m.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ));
      }
      for (final blk in s.blocks) {
        if (blk is Paragraph) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(_inline(blk.spans, m)),
          ));
        } else if (blk is BulletList) {
          for (final item in blk.items) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: m.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text.rich(_inline(item, m))),
                ],
              ),
            ));
          }
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  TextSpan _inline(List<NoteSpan> spans, MeowColors m) {
    final base = TextStyle(color: m.textDim, fontSize: 12.5, height: 1.5);
    return TextSpan(children: [
      for (final s in spans)
        switch (s) {
          PlainText(:final text) => TextSpan(text: text, style: base),
          BoldText(:final text) => TextSpan(
              text: text,
              style: base.copyWith(
                color: m.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          CodeText(:final text) => TextSpan(
              text: text,
              style: base.copyWith(
                fontFamily: 'monospace',
                color: m.accent,
                backgroundColor: m.background,
              ),
            ),
          IssueRef(:final number) => WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => onIssueTap(number),
                child: Text(
                  '#$number',
                  style: TextStyle(color: m.accent, fontSize: 11.5),
                ),
              ),
            ),
        },
    ]);
  }
}

/// A small pill for a changelog category. Colors are fixed (theme-independent)
/// so the three categories stay distinct on every dark theme.
class ChangelogTagChip extends StatelessWidget {
  const ChangelogTagChip({super.key, required this.tag, this.label});
  final ChangelogTag tag;

  /// Short custom text; when null the chip shows the category word [tag.label].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = _tagStyles[tag]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.fg),
          const SizedBox(width: 4),
          Text(
            label ?? tag.label,
            style: TextStyle(
              color: style.fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagStyle {
  const _TagStyle(this.bg, this.fg, this.icon);
  final Color bg;
  final Color fg;
  final IconData icon;
}

const Map<ChangelogTag, _TagStyle> _tagStyles = {
  ChangelogTag.added:
      _TagStyle(Color(0x33D4A574), Color(0xFFEBCEA8), Icons.auto_awesome),
  ChangelogTag.fixed:
      _TagStyle(Color(0x2A7BC47F), Color(0xFF9BD89E), Icons.check_circle),
  ChangelogTag.improved:
      _TagStyle(Color(0x2AE0B873), Color(0xFFEBCB8E), Icons.bolt),
};
