// lib/ui/changelog_view.dart
import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/platform/open_external.dart';
import '../core/theme/meow_context.dart';
import '../core/theme/meow_theme.dart';
import '../core/update/changelog_markup.dart';
import '../core/update/update_service.dart';
import 'changelog_markdown.dart';

/// Marks the multi-version catch-up hero container in the widget tree, so
/// widget tests can scope assertions to just the aggregate summary (as
/// opposed to the per-version rows below, which repeat some of the same chip
/// labels by design).
const changelogCatchUpHeroKey = Key('changelogCatchUpHero');

/// The redesigned "What's new" panel: a highlights hero (A+D) plus a
/// collapsible "earlier updates" list (B), all rendered markdown with category
/// chips (A). Replaces the old raw-text `_changelogPanel`.
///
/// In [catchUp] mode — the post-update "what's new" modal, where [entries]
/// are versions the user *just installed* — several entries get an aggregate
/// hero summarizing everything across the whole span (a combined chip wrap
/// and a handful of combined highlights), with every version's own details
/// still available below (issue #190: the old design silently made only the
/// newest version the hero and buried the rest). A single entry keeps the
/// original per-version hero even in catch-up mode.
///
/// Without [catchUp] (the default — UpdateDialog's up-to-date and
/// update-available phases, where multiple entries just mean "here's the
/// changelog", not "you just installed all of these"), the original layout
/// renders: newest-version hero plus a collapsed EARLIER UPDATES list.
/// "N updates installed" copy would be a lie there, so it's opt-in, never
/// inferred from entry count (#209 review).
class ChangelogView extends StatefulWidget {
  const ChangelogView({
    super.key,
    required this.entries,
    this.catchUp = false,
  });

  final List<ChangelogEntry> entries;

  /// True only when [entries] are versions the user just installed at once.
  final bool catchUp;

  @override
  State<ChangelogView> createState() => _ChangelogViewState();
}

class _ChangelogViewState extends State<ChangelogView> {
  final Set<int> _expanded = <int>{};
  bool _heroExpanded = false;

  void _onIssueTap(int n) => openExternalUrl('$issueBaseUrl/$n');

  /// Category chips to show: the entry's authored chips, or — when it has none
  /// (a free-form entry with no `### Added/Fixed/Improved` sections) — one
  /// inferred from its version (patch → Fixed, minor/major → New).
  List<ChangelogChip> _chipsFor(ChangelogEntry e, ParsedNotes p) =>
      chipsForVersion(e.version, p);

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final m = context.meow;
    final parsed = widget.entries.map((e) => parseChangelogNotes(e.notes)).toList();
    // A single installed version keeps the exact original hero. Several at
    // once (a catch-up jump) get the aggregate hero instead, with EVERY
    // version -- including the newest -- then listed below, since there is no
    // longer a single "the hero version" to exclude from that list. Gated on
    // widget.catchUp, never inferred from entry count alone (#209 review).
    final isCatchUp = widget.catchUp && widget.entries.length > 1;

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
            if (isCatchUp)
              _catchUpHero(m, widget.entries, parsed)
            else
              _hero(m, widget.entries.first, parsed.first),
            if (isCatchUp) ...[
              const SizedBox(height: 12),
              Text(
                'ALL UPDATES',
                style: TextStyle(
                  color: m.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              for (var i = 0; i < widget.entries.length; i++)
                _earlierRow(m, i, widget.entries[i], parsed[i]),
            ] else if (widget.entries.length > 1) ...[
              // Non-catch-up (UpdateDialog): the original layout — the newest
              // version is the hero above, so it stays out of this list.
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

  /// The multi-version catch-up hero: a "here's everything you just got"
  /// summary shown instead of the single-version hero when [entries] holds
  /// more than one version. Combines category chips and a handful of
  /// highlights across every included version (via
  /// [combineChips]/[combinedHighlights]) -- the full per-version breakdown
  /// still lives in the rows below, so this only needs to summarize, not
  /// repeat the whole changelog.
  Widget _catchUpHero(
    MeowColors m,
    List<ChangelogEntry> entries,
    List<ParsedNotes> parsed,
  ) {
    final chips = combineChips(
      entries.map((e) => e.version).toList(),
      parsed,
    );
    final highlights = combinedHighlights(parsed);
    return Container(
      key: changelogCatchUpHeroKey,
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
                  "WHAT'S NEW · ${entries.length} UPDATES",
                  style: TextStyle(
                    color: m.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                _formatDate(entries.first.date),
                style: TextStyle(color: m.textDim, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${entries.length} updates installed',
            style: TextStyle(
              color: m.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  ChangelogTagChip(tag: c.tag, label: c.label),
              ],
            ),
          ],
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final h in highlights) _bullet(m, h),
          ],
        ],
      ),
    );
  }

  Widget _hero(MeowColors m, ChangelogEntry e, ParsedNotes p) {
    final chips = _chipsFor(e, p);
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
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in chips)
                  ChangelogTagChip(tag: c.tag, label: c.label),
              ],
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
    final chips = _chipsFor(e, p);
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
                      // Same category chips as the hero, so the collapsed list
                      // is scannable without opening each row. Only versions
                      // with `### Added/Fixed/Improved` sections have tags;
                      // older free-form entries simply show none.
                      if (chips.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final c in chips)
                                ChangelogTagChip(tag: c.tag, label: c.label),
                            ],
                          ),
                        ),
                      if (p.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
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
            // Suppress the section tag headings here: the row's chip already
            // sits in the collapsed header above, so re-printing it in the
            // expanded body just duplicates it (matches the hero, which also
            // passes showTags: false).
            child: ChangelogMarkdown(
              sections: p.sections,
              onIssueTap: _onIssueTap,
              showTags: false,
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
