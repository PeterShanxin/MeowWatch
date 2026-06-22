# Post-update "What's new" modal

**Date:** 2026-06-21
**Status:** Design + implementation (same PR as the changelog presentation redesign)
**Area:** App startup — a one-time, dismissable highlights modal after an update

## Problem

When MeowWatch auto-updates, the user is dropped back into the app with no signal
of what changed. The updater dialog exists, but it is opt-in (you must open it).
Nothing proactively shows "here's what's new in the version you just got".

## Goal

On the first launch **after updating from an older version**, pop a dismissable
modal showing the just-installed version's highlights (the same hero card the
updater's "What's new" panel uses). Show it **at most once per version**. Never
show it on a fresh install or on an unchanged relaunch.

## Decisions

- **Trigger:** persist a `last_seen_version` setting. On launch, show the modal
  iff a previous version was recorded (`last_seen_version` non-null/non-empty)
  **and** it differs from the current `appVersion`. A fresh install has no
  record → no modal. The current version is recorded on every launch so the
  modal fires at most once per bump.
- **Content source is LOCAL, not R2.** The modal describes the version you are
  *already running*, which we ship in `CHANGELOG.md`. Bundling `CHANGELOG.md` as
  an asset and reading the current version's entry makes the modal instant and
  offline, and avoids any dependence on R2 having published the entry yet. (The
  updater dialog keeps using R2 — that's about what's *available remotely*; this
  modal is about what you *just installed*.)
- **Reuse the hero.** The modal body is `ChangelogView(entries: [currentEntry])`,
  so a single entry renders just the approved hero (tags + up-to-3 highlights +
  "Full notes"). No new presentation code.
- **Dev/test backdoor:** mirror the existing `MEOWWATCH_GALLERY=1` env door with
  `MEOWWATCH_WHATS_NEW=1` to force the modal regardless of `last_seen_version`,
  so it can be exercised on a real install.

## Architecture (small, focused units)

1. `lib/core/update/whats_new_gate.dart` — pure
   `bool shouldShowWhatsNew({String? lastSeen, required String current})`.
2. `lib/core/update/changelog_file.dart` — pure
   `List<ChangelogEntry> parseChangelogFile(String markdown)` (split on
   `## [version] - date` headers; total, never throws) +
   `ChangelogEntry? entryForVersion(entries, version)`.
3. `lib/ui/whats_new_dialog.dart` — `WhatsNewDialog` (themed `Dialog`, header +
   `ChangelogView` + "Got it"); `static Future<void> show(context, entry)`.
4. `lib/core/data/settings_store.dart` — add `kLastSeenVersionKey`.
5. `lib/app.dart` — optional `showWhatsNew` / `whatsNewEntry`; show after first
   frame via an internal navigator key.
6. `lib/main.dart` — read `last_seen_version`, compute the gate (+ env door),
   record the current version, and (when showing) load+parse the bundled
   `CHANGELOG.md` for the current entry; pass both into `MeowWatchApp`.
7. `pubspec.yaml` — bundle `CHANGELOG.md` as an asset.

## Edge cases / totality

- Parser is total: malformed/empty markdown → best-effort list, never throws.
- Asset load / parse failure → `whatsNewEntry` null → no modal (silently).
- Gate is null-safe and trims; empty `last_seen_version` is treated as no record.
- Modal is barrier-dismissable and has an explicit "Got it" + close button.

## Testing

- `test/core/update/whats_new_gate_test.dart` — null / empty / same / different.
- `test/core/update/changelog_file_test.dart` — multi-entry split, intro
  ignored, `entryForVersion` hit/miss, empty input.
- `test/ui/whats_new_dialog_test.dart` — renders the entry's highlight + a chip +
  "Got it".
- `test/app_whats_new_test.dart` — `MeowWatchApp(showWhatsNew: true, …)` shows
  the modal after first frame; `showWhatsNew: false` does not.

## Versioning

Ships in the same `0.33.0-alpha` PR as the changelog presentation redesign — the
CHANGELOG entry gains a line for the post-update modal.
