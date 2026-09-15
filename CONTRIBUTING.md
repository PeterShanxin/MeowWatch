# Contributing to MeowWatch

Thanks for helping out.

**By intentionally submitting a contribution to this project, you agree to the
[Contributor License Agreement](CLA.md) for that contribution.**

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

Every PR must pass **`Analyze & Test`** (`flutter analyze` + `flutter test`).
The suite is Windows-only, so pull-request verification runs on GitHub-hosted
`windows-2022`; the small `gate` referee on hosted Linux preserves the required
check name. The canonical repository has no self-hosted CI path.

Trusted-admin `v*` tags also use GitHub-hosted `windows-2022` for the Windows
x64 build/sign/release path, followed by hosted Ubuntu for R2 metadata. Hosted
PR jobs have read-only contents permission, disable persisted checkout
credentials, and must never receive signing or R2 secrets.

### If your check is stuck "Queued / Expected"

You are waiting on GitHub-hosted Actions. Check GitHub Actions service status or
re-run the hosted workflow when appropriate; there is no maintainer PC runner
to start.

If you maintain your own **fork**, you may register runners on that fork alone.
Never point a runner at this canonical repo.

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

Linux is a local compile target for two-window testing, not a release.
See [`docs/LINUX.md`](docs/LINUX.md) for apt packages and
`flutter run -d linux`.
