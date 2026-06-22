// lib/ui/changelog_view.dart
import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/platform/open_external.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/update/changelog_markup.dart';
import '../core/update/update_service.dart';
import 'changelog_markdown.dart';

/// The redesigned "What's new" panel: a highlights hero for the newest version
/// (A+D) plus a collapsible "earlier updates" list (B), all rendered markdown
/// with category chips (A). Replaces the old raw-text `_changelogPanel`.
class ChangelogView extends StatefulWidget {
  const ChangelogView({super.key, required this.entries});

  final List<ChangelogEntry> entries;

  @override
  State<ChangelogView> createState() => _ChangelogViewState();
}

class _ChangelogViewState extends State<ChangelogView> {
  final Set<int> _expanded = <int>{};
  bool _heroExpanded = false;

  void _onIssueTap(int n) => openExternalUrl('$issueBaseUrl/$n');

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final m = context.meow;
    final parsed = widget.entries.map((e) => parseChangelogNotes(e.notes)).toList();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.border.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _hero(m, widget.entries.first, parsed.first),
            if (widget.entries.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                'EARLIER UPDATES',
                style: TextStyle(
                  color: m.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              for (var i = 1; i < widget.entries.length; i++)
                _earlierRow(m, i, widget.entries[i], parsed[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(MeowColors m, ChangelogEntry e, ParsedNotes p) {
    final highlights = p.highlights.take(3).toList();
    // "Full notes" only earns its place when it reveals something the hero
    // highlights don't already show — extra bullets beyond the shown few, or
    // paragraph text (headings are rendered as the tag chips above). Without
    // this, a short version (≤3 bullets, no prose) made the expander repeat the
    // exact same bullets.
    final hasMore = p.highlights.length > highlights.length ||
        p.sections.any((s) => s.blocks.any((b) => b is Paragraph));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: m.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: m.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "WHAT'S NEW · v${e.version}",
                  style: TextStyle(
                    color: m.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                _formatDate(e.date),
                style: TextStyle(color: m.textDim, fontSize: 11),
              ),
            ],
          ),
          // The authored `> summary` is the hero headline (writing convention).
          // Only an explicit headline is shown here; a derived summary would
          // just repeat the first bullet below.
          if (p.hasHeadline && p.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              p.summary,
              style: TextStyle(
                color: m.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
          if (p.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in p.tags) ChangelogTagChip(tag: t)],
            ),
          ],
          const SizedBox(height: 4),
          if (highlights.isEmpty) ...[
            if (!p.hasHeadline && p.summary.isNotEmpty)
              _bullet(m, [PlainText(p.summary)]),
          ] else
            for (final h in highlights) _bullet(m, h),
          if (hasMore) ...[
            GestureDetector(
              onTap: () => setState(() => _heroExpanded = !_heroExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Full notes',
                      style: TextStyle(color: m.accent, fontSize: 12.5),
                    ),
                    Icon(
                      _heroExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: m.accent,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (_heroExpanded)
              ChangelogMarkdown(
                sections: p.sections,
                onIssueTap: _onIssueTap,
                showTags: false,
              ),
          ],
        ],
      ),
    );
  }

  Widget _bullet(MeowColors m, List<NoteSpan> spans) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: m.accent, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final s in spans)
                    switch (s) {
                      PlainText(:final text) => TextSpan(text: text),
                      BoldText(:final text) => TextSpan(
                          text: text,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      CodeText(:final text) => TextSpan(text: text),
                      IssueRef(:final number) => WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => _onIssueTap(number),
                            child: Text(
                              '#$number',
                              style: TextStyle(color: m.accent, fontSize: 12.5),
                            ),
                          ),
                        ),
                    },
                ],
                style: TextStyle(color: m.textPrimary, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _earlierRow(MeowColors m, int i, ChangelogEntry e, ParsedNotes p) {
    final open = _expanded.contains(i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _expanded.remove(i);
            } else {
              _expanded.add(i);
            }
          }),
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: m.border)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'v${e.version} · ${_formatDate(e.date)}',
                        style: TextStyle(
                          color: m.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (p.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            p.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: m.textDim, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: m.textDim,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChangelogMarkdown(
              sections: p.sections,
              onIssueTap: _onIssueTap,
            ),
          ),
      ],
    );
  }

  /// "2026-06-21" → "Jun 21, 2026"; falls back to the raw string on any parse
  /// failure (defensive — a malformed date must never break the view).
  String _formatDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final y = int.tryParse(parts[0]);
    final mo = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || mo == null || d == null || mo < 1 || mo > 12) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[mo - 1]} $d, $y';
  }
}
