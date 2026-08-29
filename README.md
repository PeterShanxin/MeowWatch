<div align="center">

# MeowWatch

**Watch videos together, in perfect sync.**

Private development repository. Public downloads and the product showcase live at
**[PeterShanxin/MeowWatch-releases](https://github.com/PeterShanxin/MeowWatch-releases)**.

![MeowWatch — co-watching in action](docs/assets/hero.png)

[![Build](https://github.com/PeterShanxin/MeowWatch/actions/workflows/build.yml/badge.svg)](https://github.com/PeterShanxin/MeowWatch/actions/workflows/build.yml)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0--only-blue)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)
![Version](https://img.shields.io/badge/version-0.47.0--alpha-orange)

</div>

---

## Download (public)

**[MeowWatch-releases](https://github.com/PeterShanxin/MeowWatch-releases/releases/latest)** — installers and showcase README for users and portfolio visitors.

| Platform | Status |
| --- | --- |
| Windows x64 | Available |
| Windows ARM64 | Coming soon |

After the first install, MeowWatch updates itself in-place via a signed R2 manifest.

---

## Features

| Feature | Description |
| --- | --- |
| **Precision sync** | Custom Dart Syncplay client — TCP + startTLS, stateful heartbeat, convergence with `ignoringOnTheFly` / `setBy`. |
| **Floating chat** | Drag-and-snap glass-card overlay — dock to any corner, collapse to a peek tab, Tab-key toggle. |
| **3 themes** | Cozy, Cinema Noir, Glass Aurora — persisted in SQLite. |
| **Drag & drop** | Drop a video file — plays via `libmpv`. |
| **Continue watching** | SQLite history with resume position and one-click resume. |
| **Smart auto-pause** | Pauses when sync drops or a friend disconnects (2 s debounce). |
| **Reactions & typing** | Emoji bursts and typing indicators over a control channel. |
| **Idle mascot** | Hand-painted cat while you wait for a friend. |
| **Signed auto-update** | Ed25519-verified updates from Cloudflare R2. |

---

## Development

Contributor setup, CI, and release signing are documented in [docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md). Contributions need a signed-off [CLA](CLA.md) — see [CONTRIBUTING.md](CONTRIBUTING.md).

Public showcase metadata is exported from `showcase/` via **Publish Showcase** when a tagged release is mirrored to `MeowWatch-releases`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

---

## Architecture

Commands-in / streams-out across video, sync, chat, and update subsystems. See [docs/ROADMAP.md](docs/ROADMAP.md) for shipped phases.

---

## License

MeowWatch community source is licensed under the
**[GNU Affero General Public License v3.0 only](LICENSE)** (AGPL-3.0-only).

Commercial licensing is available for organizations that require terms outside
AGPL-3.0. Using the public project under AGPL-3.0 does not require a paid
license.

The MeowWatch name and logo are covered by [TRADEMARKS.md](TRADEMARKS.md), not
by the software license. Runtime helpers (yt-dlp Windows exe, Deno) are
downloaded by the app and are **not** AGPL'd — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
