# Phase 6 — Manual Test Checklist

Updated 2026-05-30 after the polish round (presence, gear roster, load-video,
mascot, bridge seek guard). All automated tests pass and the Release build is
ready. Verify by hand before tagging `phase-6-complete`.

## Polish round 2 (newest — verify these)
- [ ] **Notices on the load-video screen**: before any video is loaded, the
      "Waiting for a friend…" hint and "🐾 X joined" / "👋 X left" banners now
      show (previously only appeared once a video was playing).
- [ ] **Chat visible without a video**: the chat card shows on the empty screen
      too, so you can type/read while picking a file.
- [ ] **Load video then play**: gear → "Load video…" → pick a file → the menu
      closes; you can immediately press play (space or the bar button) and your
      friend follows. (Before: the open menu trapped focus and play did nothing.)
- [ ] **Reload mid-session**: while watching, gear → "Load video…" a different
      file on A → both can play it together.
- [ ] **Menu dismisses on action**: tapping "Load video…" or "Leave room" closes
      the gear popover.

### About chat history (point #4)
A friend who joins *after* messages were sent will NOT see the earlier ones —
the Syncplay server does not replay past chat to late joiners. Messages from the
moment they join onward appear normally. (Persisting/replaying our own history is
a possible future feature — tell me if you want it.)

### If "B doesn't follow play" happens again
There's now an automatic log at:
`%TEMP%\meowwatch_sync.log`
Reproduce the issue once, then send me that file (or just tell me) — it records
the exact follow decisions so I can pin the root cause.

## Polish round (verify these)
- [ ] **Leave message**: friend leaves → banner "👋 X left" (no longer jumps to
      "waiting for a friend" first), and a centered "X left the room" line in the
      chat card.
- [ ] **Rejoin**: when you (B) re-enter a room where A is already present, you do
      NOT see a spurious "A joined" — A is just listed as present. A sees
      "🐾 B joined".
- [ ] **Chat event lines**: real joins/leaves show as dim centered lines in the
      chat card (not bubbles).
- [ ] **Gear → In the room**: lists everyone with a green dot; you show "(you)".
- [ ] **Gear → Load video…**: opens the file picker; pick a new file → it loads
      without leaving the room.
- [ ] **Room code copy**: tapping the code only flips the icon to a check +
      SnackBar; the gear card no longer stretches sideways.
- [ ] **Mascot**: fuller sitting cat — breathes, tail wags, ear twitches, blinks.
- [ ] **Play smoothness**: a pause/resume no longer causes a tiny backward jump
      (bridge skips micro-seeks).

## Known intermittent (point #1) — watch for it
- After a **long idle** then first play, the follower sometimes doesn't sync until
  you leave + rejoin. Couldn't reproduce reliably; the bridge change may help. If
  it recurs, note the exact timing — it likely needs a fresh diagnostic log run.

---

Below is the original feature checklist.

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
