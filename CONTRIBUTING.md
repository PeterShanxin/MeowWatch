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
| **Every pull request** (including `PeterShanxin`, `ianmeowmeow`, forks, Dependabot) | GitHub-hosted `windows-2025` | Automatic. PRs **never** schedule on the privileged self-hosted PC (`meowwatch-ci`). That machine holds the release-signing seed. |
| **Trusted-admin push / tag analyze** | Self-hosted Windows (`meowwatch-ci`) | Push to `main` and `v*` tags when `github.actor` is `PeterShanxin` or `ianmeowmeow`. |
| **Tag sign (`Windows x64`)** | Self-hosted Windows (`meowwatch-ci`) | Same two actors only. Reads the Ed25519 seed on that PC. |

The merge gate is the `gate` job. Its check-run name is exactly
**`Analyze & Test`** — that is the required check. It passes if the hosted
Windows job went green.

Tag-only `Windows x64` build and **Sign release** stay on self-hosted, and
only when **`github.actor` is `PeterShanxin` or `ianmeowmeow`**. Any other
login's `git push` of a branch or a `v*` tag does **not** run on that host
and does **not** sign a release. Pull requests cannot schedule those jobs.
Write access alone is not host trust. The **Publish Showcase** workflow
(`workflow_dispatch`) holds `RELEASE_MIRROR_TOKEN` and is likewise limited
to those two actors — any other login's click must not run it.

### If your check is stuck "Queued / Expected"

- **Pull request:** you should already be on hosted Windows. A queued
  `meowwatch-ci` job on a PR is a bug — say so on the PR.
- **Push / tag analyze or `Windows x64`:** no self-hosted runner is
  online. Start it. Tag signing has no hosted fallback.

## Self-hosted runners

Do **not** attach a self-hosted runner to this canonical repository. The
privileged Windows host is for trusted co-admins only (`PeterShanxin` and
`ianmeowmeow`: push/tag analyze and tag signing). Pull requests never
schedule there. Outsiders registering runners here is not supported.

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
