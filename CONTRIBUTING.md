# Contributing to MeowWatch

Thanks for helping out.

**By intentionally submitting a contribution to this project, you agree to the
[Contributor License Agreement](CLA.md) for that contribution.** No per-pull-
request checkbox is required.

For toolchain, release flow, versioning, and gotchas see
[`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md). This file is the contributor-facing
CI and license summary.

## License

Community source is **[AGPL-3.0-only](LICENSE)**. You keep copyright in your
contributions. Under the CLA you also grant the maintainer a copyright and
patent license, including the right to relicense, so commercial licensing can
be offered to organizations that require terms outside AGPL-3.0.

Acceptance is submission-based: the CLA terms in effect when you intentionally
submit material for inclusion govern that contribution. Viewing, starring, or
forking the repository, opening an issue, or joining a discussion does not by
itself accept the CLA.

Using the public project under AGPL-3.0 does **not** require a paid license.
See [TRADEMARKS.md](TRADEMARKS.md) for the name and logo. Report
vulnerabilities via [SECURITY.md](SECURITY.md), not a public issue.

Runtime helpers (yt-dlp Windows exe, Deno) are downloaded by the app and are
**not** AGPL'd — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## How CI works

Every PR must pass one check before it can merge: **`Analyze & Test`**
(`flutter analyze` + `flutter test`). The suite is Windows-only (it asserts on
Windows file paths and uses Windows-rendered golden images), so the check
always runs on a Windows runner.

**Untrusted PRs always run on GitHub-hosted Windows.** That includes forks,
Dependabot, trusted-admin same-repo PRs, and every other login. There is no
self-hosted PR path. The privileged self-hosted PC holds the release-signing
seed; pull-request code must never execute there.

| Who | Runner | When |
| --- | --- | --- |
| **Every pull request** | GitHub-hosted `windows-2022` | Automatic. The `check-hosted` job, then the `gate` referee. Pinned to 2022: hosted 2025 failed the two chat-overlay goldens. |
| **Trusted-admin push / `v*` tag** (`PeterShanxin` or `ianmeowmeow`, not Dependabot) | Self-hosted Windows (`meowwatch-ci`) | Analyze + test on push/tag, and tag-only **Sign release**. Any other login's branch or tag push does **not** run on that host and does **not** sign. |

The merge gate is the `gate` job. Its check-run name is exactly
**`Analyze & Test`** — that is the required check. It passes when the hosted
PR job is green.

Write access is not host trust. GitHub's fork-workflow approval does not
replace the YAML actor allowlist on remaining self-hosted jobs.

Hosted PR jobs use `permissions: contents: read` only. Their checkout
sets `persist-credentials: false`. They must not see
`TAURI_SIGNING_PRIVATE_KEY`, the MeowWatch Ed25519 seed /
`MEOWWATCH_RELEASE_KEY` / `release-key.txt`, `R2_*` secrets, or
other release credentials.

### If your check is stuck "Queued / Expected"

You are waiting on **GitHub-hosted** Windows. A self-hosted job queued on a
PR is a bug — say so on the PR.

## Self-hosted runners

Do **not** attach a self-hosted runner to this canonical repository. The
privileged Windows host is **trusted-admin push/tag sign only**
(`PeterShanxin` and `ianmeowmeow`). Pull requests never schedule jobs there.
Outsiders registering runners here is not supported.

If you maintain your own **fork**, you may register runners on that fork
alone. Never point a runner at this repo.

## Development

Flutter is installed via [Puro](https://puro.dev/) on the `stable` channel.
On the maintainer's Windows machines it lives at
`%USERPROFILE%\.puro\envs\stable\flutter\bin` and is **not** on PATH. Hosted CI
installs Flutter with `subosito/flutter-action`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```
