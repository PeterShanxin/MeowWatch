# Changelog presentation redesign (A+B+D)

**Date:** 2026-06-21
**Status:** Design — awaiting user approval before implementation plan
**Area:** In-app updater dialog — the "What's new" / changelog panel

## Problem

The changelog panel in [`update_dialog.dart`](../../../lib/ui/update_dialog.dart)
(`_changelogPanel`, ~line 277) renders each version's `notes` as a single
plain `Text` widget inside one scroll box capped at 220px. Three problems:

1. **Raw markdown shows literally.** Notes contain `**bold**`, `### Added`,
   `- bullet`, `` `code` ``, and `(#136)`. None of it is rendered — the user
   sees the asterisks, hashes, and dashes as-is.
2. **Walls of text.** Long entries (e.g. 0.31.2-alpha — three large paragraphs)
   are crammed into the fixed scroll box. No collapse, no "show more", no
   visual hierarchy between versions.
3. **Dev-speak leaks.** Notes sometimes carry internal detail ("media_kit/mpv
   paths", "the seek Future stayed unfinished", "single-flight flag") that means
   nothing to the end user.

## Goals

- Render the markdown that already lives in `notes` (bold, bullets, headings,
  inline code, issue refs).
- Lead with the newest version as a **highlights hero**; fold older versions into
  a **collapsible list** ("show more").
- Tag each version with **category chips** (New / Fixed / Improved).
- Establish a **writing convention** so future notes are user-facing, and codify
  it where all contributors see it.

## Non-goals (YAGNI for this pass)

- No search/filter by tag.
- No mass rewrite of historical CHANGELOG entries' wording (risky, out of scope).
  Going-forward discipline only; the parser degrades gracefully on old entries.
- No CI/pipeline change required for v1 (see "Why no pipeline change").
- No new markdown dependency — a small built-in formatter handles the fixed
  subset we author.

## Decisions (locked with user)

- **Formatting:** small built-in formatter, no external package. Input is our
  own CHANGELOG, so the markdown subset is fixed and testable.
- **Summaries:** hybrid. Auto-derive a one-line summary from `notes` so every
  past version works immediately; optionally hand-write a nicer one per future
  release via a leading blockquote convention.

## The combined layout (A+B+D)

```
┌─ What's new ───────────────────────────────┐
│ WHAT'S NEW · v0.33.0          Jun 21        │  ← Hero (D), newest entry
│  [✨ New] [🐛 Fixed]                         │  ← tags (A), derived from headings
│  • Latest video per room                    │  ← highlights (top bullets, rendered)
│  • Updates footer in the in-room gear       │
│  Full notes ▾                               │  ← expander → full rendered notes
│─────────────────────────────────────────── │
│ EARLIER UPDATES                             │
│ v0.31.2 · Jun 21   Freeze fixed for good  ▾ │  ← collapsed row (B): summary + chevron
│ v0.31.1 · Jun 20   Auto-fix stalled resume▾ │     tap → expand rendered notes + tags
│ v0.31.0 · Jun 20   Better diagnostics     ▾ │
└─────────────────────────────────────────────┘
```

- **Hero** = `entries.first` (newest). The newest entry is the version you'd get
  (update-available phase) or the version you're on (up-to-date phase) — the same
  widget serves both phases the panel already appears in.
- **Earlier updates** = `entries.skip(1)`, each collapsed by default.
- Whole panel stays inside a scrollable, height-capped container (raise cap to
  ~280px to give the hero room).
- **Empty changelog** → existing fallback paths (single `releaseNotes`, or
  nothing) are untouched.

## Architecture

Three new small, focused units. Pure parsing is split from rendering so it can be
unit-tested headless (matches the repo's `sync_follow.dart` pattern), and the
parser is **total — it never throws** (matches the logger-freeze lesson: parsers
feeding the UI must degrade, not crash).

### 1. `lib/core/update/changelog_markup.dart` — pure parser (no Flutter import)

Turns one entry's raw `notes` string into a structured, render-ready model.

```
ParsedNotes parseChangelogNotes(String notes)

ParsedNotes {
  String? summaryOverride;     // from a leading "> ..." blockquote, else null
  List<NoteSection> sections;  // in document order
}

NoteSection {
  ChangelogTag? tag;           // from "### Added/Fixed/Changed/Improved", else null
  List<NoteBlock> blocks;      // paragraphs + bullet lists under this heading
}

NoteBlock = Paragraph(List<NoteSpan>) | BulletList(items: List<List<NoteSpan>>)
NoteSpan (own type, named to avoid Flutter's InlineSpan) =
    PlainText(text) | Bold(text) | Code(text) | IssueRef(number, raw: "#NNN")
```

Helper getters / derivations on the parsed result (all pure):

- `summary` → `summaryOverride` if present, else **derived**: first sentence of
  the first paragraph or first bullet, markdown-stripped, trimmed to a sane
  length (e.g. ~90 chars with ellipsis).
- `tags` → distinct `ChangelogTag`s found across sections (order: New, Fixed,
  Improved). Empty when no `###` headings exist (old flat entries).
- `highlights` → first N (3) bullet items across the notes, as inline spans for
  the hero; if there are no bullets, fall back to a single highlight = `summary`.

Inline grammar (the fixed subset we author):
- `**bold**`
- `` `code` ``
- `#123` and `(#123)` → `IssueRef`
- everything else → `Text`

Heading → tag mapping:
- `### Added` → `ChangelogTag.added` ("New")
- `### Fixed` → `ChangelogTag.fixed` ("Fixed")
- `### Changed` / `### Improved` → `ChangelogTag.improved` ("Improved")
- unknown heading text → ignored for tags (its blocks still render under it)

### 2. `lib/ui/changelog_markdown.dart` — span/block renderer

Takes `List<NoteBlock>` (or `List<NoteSection>`) and renders to Flutter widgets,
themed via `context.meow`:
- Bold → `FontWeight.w600`, `textPrimary`.
- Code → small mono chip on a faint `background` fill.
- IssueRef → soft `accent`-tinted tappable text; opens the GitHub issue URL
  (reuse the app's existing external-link launch path).
- Bullets → indented rows with a leading dot in `accent`.
- Body text → `textDim`, `TypeScale.body`.

### 3. `lib/ui/changelog_view.dart` — the A+B+D panel

Stateful widget owning expand/collapse state (a `Set<int>` of expanded indices;
hero's own "Full notes" toggle is separate). Composes the hero + earlier-updates
list using units 1 and 2. Replaces `_changelogPanel` in `update_dialog.dart`.

Category chip styling (Material icons, matching the dialog's existing icon use):
- New → `Icons.auto_awesome`, `accent`
- Fixed → `Icons.check_circle` / `Icons.bug_report`, `online` (green)
- Improved → `Icons.bolt`, amber tint

### Changes to existing files

- `update_service.dart` — `ChangelogEntry` is unchanged on the wire (still
  `version`/`date`/`notes`); parsing happens lazily in the view via
  `parseChangelogNotes(entry.notes)`. **No model field changes required.**
- `update_dialog.dart` — delete `_changelogPanel`; both the up-to-date and
  update-available phases call `ChangelogView(entries: _service.changelog)`.
  This also trims this 408-line file, which is doing too much.

## Why no pipeline change (v1)

The build.yml Python parser ([build.yml:288-313](../../../.github/workflows/build.yml#L288-L313))
already emits `notes` verbatim. Because all derivation (summary, tags,
highlights) happens **client-side from `notes`**, and the hand-written summary
uses a convention that lives **inside `notes`** (a leading `> ...` line), the
pipeline needs no change. This avoids CI risk and keeps the change to app code +
tests. (A future optimization could pre-compute these fields into changelog.json,
but it is not needed and is explicitly out of scope here.)

## Writing convention (going forward)

Documented in `docs/AGENT_GUIDE.md` (so every contributor follows it — not just
Claude memory) with a one-line pointer at the top of `CHANGELOG.md`.

Per version, under the `## [version] - date` header:

```
## [0.33.0-alpha] - 2026-06-21
> One friendly sentence — the headline (optional; powers the hero/row summary).

### Added
- User-facing description of the new thing. (#136)

### Fixed
- What broke, in plain words, and what's better now.
```

Rules:
- Write for the user. Keep internal mechanism ("Future", "single-flight",
  "robocopy") in the **commit message**, not the note.
- Use `### Added` / `### Fixed` / `### Improved` so chips appear.
- Optional leading `> ...` blockquote = the polished one-liner; omit it and the
  app derives one from the first line.
- Issue refs `(#NNN)` stay — they render as soft tappable links.

## Error handling & edge cases

- `parseChangelogNotes` is total: malformed/empty/odd input yields a best-effort
  model, never an exception. A version with no bullets and no headings still
  renders (paragraph in the expander, derived summary in the row, no chips).
- Empty `changelog` list → unchanged fallback in the dialog.
- Long summaries truncate with ellipsis; long notes scroll within the capped
  panel.
- IssueRef link launch failures are swallowed (best-effort), consistent with
  other external-link uses.

## Testing

- `test/core/update/changelog_markup_test.dart` (new): inline parsing
  (bold/code/issue refs, mixed), explicit `>` summary vs derived summary, tag
  extraction from headings, highlight extraction (with and without bullets),
  and that malformed/empty input never throws.
- `test/ui/changelog_view_test.dart` (new): hero renders the newest entry,
  older entries collapsed by default, tapping a row/chevron expands it, chips
  appear per tag, empty list falls back.
- `test/ui/update_dialog_test.dart` (extend): both phases mount `ChangelogView`;
  existing behavior intact.
- `test/core/update/changelog_test.dart` (unchanged): fetch/model tests still
  pass since the wire shape is unchanged.
- Optional golden for the panel in the cozy theme.

## Versioning

Behavior-changing feature → MINOR bump: `0.32.0-alpha → 0.33.0-alpha`, in lockstep
across `pubspec.yaml`, `lib/core/app_version.dart`, and `CHANGELOG.md`. The new
CHANGELOG entry is itself written in the new convention (dogfood the hero/tags).

## Rollout

Single PR — the three units are cohesive and not large. Suggested build order in
the implementation plan: parser (TDD, pure) → renderer → view → wire into dialog
→ AGENT_GUIDE convention + version bump.
