# Phase 6 — Manual Test Checklist

Built overnight 2026-05-30. All automated tests pass (173) and the Release build
is ready. Below is what to verify by hand before tagging `phase-6-complete`.

**Launch:** `build\windows\x64\runner\Release\meowwatch.exe` (open two copies for
two-instance tests; use two different usernames so each is its own peer).

> Note: two instances on one PC now both play (software decode fix). For the
> sync-dependent features, two separate machines is still the most realistic
> test, but one PC works for a sanity check.

## 1. File-mismatch warning
- [ ] Both join the same room. Load **different** files on each.
- [ ] Expect a banner over the video: **"⚠ Different file — <name> has …"**.
- [ ] Load the **same** file on both → warning disappears.
- [ ] Edge: load a file on one side before the other joins; the late joiner
      should still see the mismatch (peer file now surfaced on join).

## 2. Idle cat mascot
- [ ] On the empty screen (no video loaded), a cat face shows, gently
      breathing, and blinks every few seconds.
- [ ] Switch themes (gear → swatches): the cat re-tints to the new accent.

## 3. Floating reactions
- [ ] While watching, tap the **react button** (bottom-right, smiley) → emoji
      palette opens.
- [ ] Tap an emoji → it floats up over the video and fades, on **both**
      instances.
- [ ] The palette closes after picking.

## 4. Typing indicator
- [ ] Start typing in the chat box on instance A.
- [ ] Instance B shows **"<A> is typing…"** just above its chat input.
- [ ] Stop typing (or send) → the indicator clears within ~2s.
- [ ] Your own typing does NOT show on your own screen.

## 5. Regression sanity (already verified earlier, re-check quickly)
- [ ] Auto-pause: friend leaves / connection drops > 2s → video pauses with
      "⏸ Paused — lost sync"; stays paused on rejoin.
- [ ] Friend-joined banner "🐾 <name> joined" on enter/rejoin.
- [ ] Gear → room code copies (green "Copied!" + snackbar); Start-new-room on
      the connect screen pops the "copied" snackbar.
- [ ] Play stays smooth (no yank-back) with both instances running.

## After it passes
Tell Claude → it will `git tag phase-6-complete`, flip the ROADMAP Phase 6 row
to ✅, and update project memory.

## Deferred (not in this build — see ROADMAP backlog)
- Picture-in-Picture (needs a native always-on-top window — own mini-project).
- Per-message reactions (Syncplay chat has no stable message id).
