# Public-readiness audit

**Date:** 2026-08-29  
**Repository:** `PeterShanxin/MeowWatch` (still private; this audit does not change visibility)  
**HEAD:** `73a4be18b33358bf4bc5dcdf1c4884ac9bbffe64`  
**Issue:** [#246](https://github.com/PeterShanxin/MeowWatch/issues/246) Checkpoint A input  
**This PR:** report only. No remediations, no history rewrite, no visibility change.

## Verdict

**SAFE TO REMEDIATE**

Full-history secret scanning and targeted review found **no credential values, private keys, signing seeds, or R2/API tokens** in git history or at HEAD. Nothing from this scan needs emergency rotation.

**Do not flip the repository public on this report alone.** Checkpoint A is not a pass until the before-public list below lands — especially GitHub Actions hardening so untrusted pull-request code cannot run on the privileged self-hosted Windows runner (the same host that is documented as holding the release-signing seed).

| Question | Answer |
| --- | --- |
| Secret values in history? | None found |
| History rewrite required? | No (and must not be done) |
| Safe to flip public now? | No |
| Safe to start remediations? | Yes |

## Method

1. **gitleaks 8.30.1** on full git history (`gitleaks git --log-opts=--all`). Default ruleset. No repo `.gitleaks.toml` / `.gitleaksignore`. Result: **0 findings** across **643** commits (~3.69 MB scanned). `git rev-list --all` reports 789 commits (646 non-merge); the small gap is empty / no-diff commits, not unscoped refs.
2. **Targeted pickaxe** (`git log --all -G`) for AWS key IDs, GitHub token prefixes, PEM/private-key banners, Slack tokens, Cloudflare token assignments, literal `R2_*` assignments, connection strings, JWT-like triples, and generic `api_key` / `secret_key` literals. Result: **0 commits**. Working-tree `git grep` for the same families: **0 files**.
3. **Filename survey** of every path ever added: no `.env`, `.pem`, `.key`, `release-key*`, or credential-named files in history.
4. **Workflow read** of `.github/workflows/build.yml`, `package-check.yml`, `publish-showcase.yml`, `ytdlp-pin.yml`. No `pull_request_target`.
5. **Manual review** of license/governance files, updater/signing docs, screenshots/goldens, personal paths, public updater origin, and bundled-runtime notices.
6. **Image metadata:** PNG `tEXt`/`iTXt`/`zTXt` chunks on every HEAD image — none present.

Raw scanner output that can contain secret fields was discarded after extracting rule / path / commit metadata. This file contains **no secret values**.

## Redacted secret-history table

| Rule | File | Commit | Still at HEAD | Recommended action |
| --- | --- | --- | --- | --- |
| *(none)* | — | — | — | No rotation required from this scan |

Informational items below are **not secrets**. They are listed so a later reviewer does not re-discover them and treat them as leaks.

| Kind | File | Commit | Still at HEAD | Notes / action |
| --- | --- | --- | --- | --- |
| Ed25519 **public** key (baked verifier) | `lib/core/update/release_signature.dart` | present at HEAD | yes | Expected. Public half only. Do not treat as a leak. |
| Public updater origin (`r2.dev`) | `lib/core/app_version.dart` | present at HEAD | yes | Client-facing by design. Not an access key. Keep it; optional custom domain later. |
| Signing **path** docs (`%USERPROFILE%\.meowwatch\…`) | `docs/AGENT_GUIDE.md`, `.github/workflows/build.yml` | present at HEAD | yes | Path convention only. Seed file was not in git. Host must not run untrusted PR code (see CI). |
| Personal Windows home path | `docs/AGENT_GUIDE.md`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, many `docs/superpowers/**` plans | present at HEAD | yes | Username-bearing absolute Puro path. Scrub before public. |
| Commit author mailbox domains | git metadata | all history | n/a | Personal/institutional authors will become visible. Do **not** rewrite history. Use noreply going forward. |

## Targeted review

### `.env`, keys, PEM, tokens

- No `.env` / `.pem` / `.key` / `id_rsa*` files at HEAD or in history.
- `.gitignore` ignores logs and build output but **does not** ignore `.env`, `*.pem`, `*.key`, or `release-key.txt`. Defense-in-depth gap, not a current leak.
- Test fixtures use placeholder strings such as `SECRET` / `SECRETTOKEN` in URL-redaction tests (`test/core/sync/sync_messages_test.dart`, `test/core/video/mpv_log_filter_test.dart`). Those are test sentinels, not credentials.

### Cloudflare R2

- Workflow interpolates `secrets.R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`, `R2_BUCKET_NAME`, `R2_PUBLIC_URL` **only** in the `release` job of `build.yml`.
- That job is `runs-on: ubuntu-latest` and is gated `startsWith(github.ref, 'refs/tags/v')` plus a green Windows tag build. It does **not** run on `pull_request`.
- Jobs that *do* run on pull requests (`check-self-hosted`, `check-hosted`, `gate`) do not reference any `secrets.R2_*`. GitHub does not inject unused secrets into those jobs.
- Fork `pull_request` events additionally receive **no** repository secrets (GitHub platform rule).
- Same-repo collaborator PRs *could* see R2 secrets only if a future workflow edit referenced them in a PR job. Least-privilege job permissions reduce that risk (see remediations).
- The public `r2.dev` origin in `lib/core/app_version.dart` is the updater base URL, not an access key.

### Signing seeds

- Docs and the tag-only `Sign release` step say the private seed lives on the release PC at a user-profile path (override `MEOWWATCH_RELEASE_KEY`). **The seed file is not in the repository.**
- `tool/release_signer.dart` generates/signs; it does not embed a seed.
- `releasePublicKeyBase64` is the public verifier. Safe to ship.
- **Residual risk (CI, not git):** the documented seed path is on the same Windows account that runs `check-self-hosted`. A public PR that executes on that runner can read local files. That is the main public-blocking CI finding.

### Screenshots, logs, fixtures

HEAD images (product hero, logo, social preview, widget goldens, app icon) show UI chrome, a generic chat (`You` / `Liam`), or line-art. No readable tokens, paths, or mailbox addresses. No PNG text metadata.

Historical golden-failure PNGs under `test/ui/chat/failures/` exist **in history only** (that directory is gitignored now). Names match Flutter golden diffs, not desktop captures.

No `*.log` committed at HEAD. `*.log` is gitignored.

### Personal paths and private URLs

- Absolute Puro path `C:/Users/<redacted>/.puro/envs/stable/flutter/bin/flutter.bat` is repeated in agent entrypoints, `docs/AGENT_GUIDE.md`, `CONTRIBUTING.md`, and many design plans.
- Workflows and `CONTRIBUTING.md` use `%USERPROFILE%\.puro\...` (better) and document runner name / install directory on the maintainer PC.
- `CONTRIBUTING.md` states self-hosted CI is safe **because the repo is private** and tells fork maintainers how to attach a Windows runner. That assumption dies the moment the repo is public.
- Public Syncplay hostnames in tests/docs (`syncplay.pl`) are the public service, not a private URL.
- No Discord/Slack webhooks, no RFC1918 hosts, no private issue-tracker hosts found.

### Bundled models / runtimes

- No `.exe`, `.dll`, `.onnx`, `.gguf`, or similar binaries at HEAD. No history blob larger than 1 MB.
- `THIRD_PARTY_NOTICES.md`: yt-dlp (Unlicense source / GPLv3+ official Windows exe) and Deno (MIT) are **downloaded at runtime**, hash-pinned, not shipped inside release zips.
- Flutter/`media_kit` native bits are built at compile time, not stored in git.

## GitHub Actions threat model

### `build.yml` (verified)

| Item | Observed at HEAD |
| --- | --- |
| Triggers | `push` (`main`, `v*` tags), `pull_request` to `main` (`opened` / `synchronize` / `reopened` / `labeled`), `paths-ignore: '**.md'` |
| Workflow `permissions` | `contents: write` (comment: needed for creating releases) |
| Default PR job | `check-self-hosted` → `runs-on: [self-hosted, windows, meowwatch-ci]` unless label `ci-hosted` |
| Hosted fallback | `check-hosted` on `windows-2022` only when `ci-hosted` is present |
| Merge referee | `gate` on `ubuntu-latest`, PR-only |
| Windows tag build + sign | `build-windows-x64`, tag-only, self-hosted; reads local signing seed; uses `GITHUB_TOKEN` to publish GitHub Release assets |
| R2 publish | `release` on `ubuntu-latest`, tag-only; **only** job that references `secrets.R2_*` |
| `pull_request_target` | **Absent** |

**R2 secrets vs pull-request jobs:** confirmed **not used** and **not available** to current `pull_request` jobs. They are referenced only in the skipped tag `release` job. Fork PRs also get an empty secret set from GitHub.

**Public-blocking CI finding:** the default PR path executes **the PR's checkout** (untrusted code) on a privileged self-hosted runner. GitHub's own guidance is that self-hosted runners on public repos are unsafe for `pull_request`. Fork secret-withholding does **not** protect the runner disk. After a visibility flip, an outside PR can run `flutter test` as the logged-in user and read the signing seed, Puro toolchain, and other profile files.

`contents: write` at workflow scope is broader than the PR gate needs. Fork PRs get a read-only `GITHUB_TOKEN`; same-repo PRs do not. Tighten to `contents: read` at workflow level and grant write only on tag jobs.

### `package-check.yml`

- `pull_request` on workflow / `pubspec.yaml` paths.
- `permissions: contents: read`.
- `ubuntu-latest`. No secrets. Stand-in zip only.
- **Fine for public** as written.

### `publish-showcase.yml`

- `workflow_dispatch` only (not `pull_request`).
- `permissions: contents: read`.
- Uses `secrets.RELEASE_MIRROR_TOKEN` to push the public showcase/mirror repo.
- **Not a fork-PR execution path.** Retire or lock down when the mirror is archived (post-public work). Token stays a GitHub secret; never commit it.

### `ytdlp-pin.yml`

- `schedule` + `workflow_dispatch`. Guard `github.repository == 'PeterShanxin/MeowWatch'`.
- Hosted `ubuntu-latest`. `permissions: contents: write` + `pull-requests: write` for the pin PR.
- Uses `secrets.GITHUB_TOKEN` only. Downloads upstream `yt-dlp.exe`, hashes it, deletes it; does not commit the binary.
- **Fine for public** with the existing fork guard. Write tokens are appropriate for this job, not for PR CI.

### Dependabot

`.github/dependabot.yml` schedules pub + Actions bumps (`Asia/Shanghai` timezone is a mild location hint). Dependabot PRs must not be routed to the privileged self-hosted runner after the repo is public.

## License and governance

| File | At HEAD |
| --- | --- |
| `LICENSE` | Proprietary all-rights-reserved (added `fbc05fc5caa41b7ac7b86dbe5b94a899c7dad769`, 2026-05-30). **Not** AGPL-3.0-only. No earlier license file. |
| `CONTRIBUTING.md` | Present. Describes private-repo self-hosted CI. No CLA. |
| `SECURITY.md` | **Absent** |
| `TRADEMARKS.md` | **Absent** |
| CLA / `CODE_OF_CONDUCT.md` | **Absent** |
| `THIRD_PARTY_NOTICES.md` | Present. Runtime yt-dlp / Deno credits; points at `pubspec.yaml` for Flutter deps. |
| README license badge | `proprietary` |

**Obvious third-party vs future AGPL** (not a legal memo, not a block on this audit):

- yt-dlp official Windows exe is called out as **GPLv3+**. It is not redistributed in MeowWatch zips (runtime download). GPLv3-family is generally aligned with AGPL-3.0-only; the sharper tension today is **GPLv3+ helper + current proprietary LICENSE** if distribution story ever changes.
- Deno: MIT. Compatible.
- `media_kit` (MIT) + bundled libmpv (typically LGPL-family) + ANGLE (BSD-family): no obvious AGPL blocker if notices stay accurate and native bits remain dynamically linked / replaceable as those licenses require.
- `pubspec.yaml` packages reviewed at a glance (Flutter SDK, drift, http, archive, crypto, ed25519_edwards, window_manager, desktop_drop, path_provider, …) are commonly MIT/BSD. Nothing obviously SSPL-only or proprietary-SDK.

Governance docs (AGPL text, CLA, trademarks, security policy) are **missing** and are Checkpoint A items. They are remediations, not secret findings.

## CI blockers vs post-public work

**CI blockers (must be true before visibility changes)**

1. Untrusted / fork pull requests must **not** automatically run on `[self-hosted, windows, meowwatch-ci]`. Default public PR CI should be GitHub-hosted or require an explicit maintainer gate after review.
2. The host that can read the release-signing seed must not execute untrusted workflows. Split “PR test” from “tag sign/build”, or keep self-hosted offline for PRs.
3. Drop workflow-level `contents: write` on PR-triggered workflows; grant write only to tag/release jobs that create releases.
4. Keep `R2_*` and `RELEASE_MIRROR_TOKEN` off every `pull_request` job (already true; lock it in with job-level `permissions` and job-level secret usage).
5. Rewrite `CONTRIBUTING.md` so it no longer claims self-hosted PR CI is safe on a public repo, and so it does not invite strangers to attach runners to the canonical repo.

**Post-public (explicitly out of scope for a visibility flip)**

- Broader hosted-CI modernization, ARM64, minute-budget tuning.
- Showcase/README polish and moving product story into this repo.
- Making `PeterShanxin/MeowWatch/releases` canonical; deciding how long R2 stays in the updater path.
- Archiving `MeowWatch-releases` (archive, do not delete).
- Dependabot timezone / community templates / topics / social-preview settings.
- Perfect final CI architecture.

## BEFORE-PUBLIC remediations only

Do these in follow-up PRs. Do **not** rewrite git history. Do **not** flip visibility until they are done.

1. **Harden `build.yml` for public forks**
   - Stop using `check-self-hosted` as the default `pull_request` job.
   - Require a maintainer label / approval / `pull_request` from a trusted ref before any job uses `[self-hosted, windows, meowwatch-ci]`.
   - Prefer hosted Windows (or a sandbox you do not mind losing) for first-party and fork PR analyze/test.
   - Keep tag `build-windows-x64` + `Sign release` on a runner that outsiders cannot schedule.
2. **Least-privilege tokens**
   - Workflow default `permissions: contents: read` (and no `pull-requests` write) on `build.yml`.
   - Job-level `contents: write` only on the tag release-creation job.
   - Re-check that no PR job interpolates `secrets.R2_*` or `RELEASE_MIRROR_TOKEN`.
3. **Governance for Checkpoint A**
   - Replace HEAD `LICENSE` with AGPL-3.0-only plus dual-license wording if that is still the product intent.
   - Add `SECURITY.md`, `TRADEMARKS.md`, and a CLA/relicensing path. Keep `CONTRIBUTING.md`; rewrite the private-repo runner section.
4. **Scrub personal machine paths at HEAD**
   - Replace `C:/Users/<name>/...` with `%USERPROFILE%\.puro\...` or “Puro stable Flutter on PATH”.
   - Leave historical commits as-is.
5. **Ignore credential filenames**
   - Add `.env`, `*.pem`, `*.key`, and `release-key.txt` to `.gitignore` so a future copy-paste cannot land in git.
6. **Optional hygiene (still before public if cheap)**
   - Confirm the signing seed on the runner disk is backed up offline and that the runner is stopped when not releasing.
   - Decide whether `docs/superpowers/**` plans stay in the public tree (they repeat the personal path many times) or move later; scrubbing the entrypoints is enough if the plans stay.

## What this audit did not do

- Did not change repository visibility.
- Did not rewrite history.
- Did not rotate credentials (none found in git).
- Did not implement CI, license, or path remediations.
- Did not produce a full license-compatibility memo.
- Did not inspect GitHub org/repo setting UI (Actions fork-approval toggle, environment protection) beyond what is in-tree.

## Sign-off

| Gate | Status |
| --- | --- |
| History secret scan | Pass (0 findings) |
| R2 secrets isolated from PR jobs | Pass (current YAML) |
| Privileged self-hosted vs untrusted PRs | **Fail** (default PR job) |
| LICENSE / SECURITY / TRADEMARKS / CLA | **Fail** (proprietary + missing files) |
| Safe to remediate | **Yes** |
| Safe to flip public | **No** |
