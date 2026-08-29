# Contributing to MeowWatch

Thanks for helping out.

**A pull request cannot merge until you agree to the
[Contributor License Agreement](CLA.md).** Tick the CLA checkbox on the pull
request template.

For toolchain, release flow, versioning, and gotchas see
[`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md). This file is the contributor-facing
CI and license summary.

## License

Community source is **[AGPL-3.0-only](LICENSE)**. You keep copyright in your
contributions. Under the CLA you also grant the maintainer a copyright and
patent license, including the right to relicense, so commercial licensing can
be offered to organizations that require terms outside AGPL-3.0.

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

| Who | Runner | When |
| --- | --- | --- |
| **Fork PRs, Dependabot PRs, and collaborator PRs** | GitHub-hosted `windows-2022` | Automatic. They **never** run on the owner's self-hosted PC (that machine holds the release-signing seed). Write access on the repo is not host trust. |
| **Pushes by a write collaborator onto an already-open owner PR** | GitHub-hosted `windows-2022` | Automatic. The PR author (`user.login`) stays the owner; `github.actor` is the pusher, so this still does **not** get self-hosted. |
| **Same-repo PRs from the owner (`PeterShanxin`) only, triggered by the owner** | Self-hosted Windows (`meowwatch-ci`) | Default, so the owner's own feedback pushes stay off the hosted-minutes meter. |
| **Owner fallback** | GitHub-hosted `windows-2022` | Add the **`ci-hosted`** label (self-hosted runner offline, or you would rather not wait). |

The merge gate is the `gate` job. Its check-run name is exactly
**`Analyze & Test`** — that is the required check. It passes if either path
went green.

Tag-only `Windows x64` build and **Sign release** stay on self-hosted, and
only when **`github.actor` is `PeterShanxin`**. A write collaborator's `git
push` of a branch or a `v*` tag does **not** run on that host and does **not**
sign a release. Pull requests cannot schedule those jobs. Write access is not
host trust. The **Publish Showcase** workflow (`workflow_dispatch`) holds
`RELEASE_MIRROR_TOKEN` and is likewise owner-actor-only — write does not let
you click it live.

### If your check is stuck "Queued / Expected"

- **Fork, Dependabot, collaborator PR, or collaborator push onto an owner PR:** you should already be on hosted
  Windows. A queued self-hosted job is a bug — say so on the PR.
- **Owner (`PeterShanxin`) same-repo PR triggered by the owner:** no self-hosted runner is online.
  Start it, or add the **`ci-hosted`** label.

## Self-hosted runners

Do **not** attach a self-hosted runner to this canonical repository. The
privileged Windows host is owner-triggered only (the owner's PRs, pushes, and
tags). Write collaborators cannot schedule jobs there. Outsiders registering
runners here is not supported.

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
