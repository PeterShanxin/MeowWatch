# AGENTS.md

Codex-specific entrypoint for this repository.

## ⛔ STOP — read the guide before any work

**Open `docs/AGENT_GUIDE.md` and read it fully before you touch anything.** It is mandatory, not a read-when-stuck reference. This repo's sharp edges, toolchain paths, and release rules live there and nowhere else; skipping it has repeatedly caused real breakage (silent broken builds, "fix not showing up", unreleased versions).

If you internalize nothing else, internalize these — each has bitten an agent who skipped the guide (full detail in the linked sections):

- **Flutter is installed via Puro and is NOT on PATH.** Use the absolute binary `C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat`. Run `analyze`/`test` locally with it — never claim "no toolchain" and defer to CI. (Gotchas §)
- **A release is NOT finished at merge.** The full chain is: PR → CI green → merge → **tag `v<version>` on the merge commit and push it** (this is what fires the Windows build + R2 upload) → **verify R2** (`latest.json` version matches, `changelog.json` includes it) → only then clean up. Stopping at "merged" ships nothing. (Release flow §)
- **Every behavior-changing PR bumps the version in lockstep** across `pubspec.yaml`, `lib/core/app_version.dart`, and `CHANGELOG.md`. Out-of-sync = broken updater. (Versioning §)
- **Manual testing uses the Release build**, and you must kill running `meowwatch.exe` before `flutter build windows` (a running instance holds a lock and the build still reports success). (Gotchas §)

## Codex-specific overrides

Keep only Codex-specific overrides in this file. When general repo guidance changes, update `docs/AGENT_GUIDE.md` instead of duplicating content here — the bullets above are deliberate, high-cost exceptions kept loud at the entrypoint, not a license to copy the guide.
