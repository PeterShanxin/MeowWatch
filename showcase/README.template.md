<div align="center">

# {{PRODUCT_NAME}}

**{{TAGLINE}}**

![{{PRODUCT_NAME}}](assets/hero.png)

[![Latest release](https://img.shields.io/github/v/release/PeterShanxin/MeowWatch-releases?label=latest&color=orange)](https://github.com/PeterShanxin/MeowWatch-releases/releases/latest)
![Windows](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)
![Status](https://img.shields.io/badge/status-alpha-orange)

[**Download latest**]({{DOWNLOAD_URL}}) · [**All releases**]({{RELEASES_URL}})

</div>

---

## The problem

Watching something with a friend over a voice call means constantly asking "are you paused?" and counting "3…2…1…" before every seek. MeowWatch removes that friction: **one room code, same playback position, chat right on the video.**

## What it does

1. **Start or join a room** — a code copies to your clipboard.
2. **Drop the same video** on both machines (or paste a URL to resolve).
3. **Stay in sync** — play, pause, and seek propagate through Syncplay.
4. **Talk while you watch** — floating chat, reactions, and typing indicators.

## Features

{{FEATURES_TABLE}}

## UX decisions

{{UX_LIST}}

## How sync works

```text
You press play/pause/seek
    → MeowWatch Syncplay client
    → public Syncplay server
    → friend's MeowWatch
    → libmpv adjusts playback
```

Convergence uses `ignoringOnTheFly` and `setBy` semantics so neither side fights the other during drift correction.

## Architecture

![System overview](assets/architecture.svg)

| Subsystem | Responsibility |
| --- | --- |
| VideoCore | libmpv playback, keyboard shortcuts, drag-and-drop |
| SyncCore | Syncplay TCP + startTLS, heartbeat, roster |
| ChatStore | Messages, reactions, typing — over Syncplay chat + control channel |
| Data layer | Drift/SQLite — profiles, history, settings, themes |
| UpdateService | R2 manifest + Ed25519 signature verification |

Pure logic (`sync_follow`, `chat_overlay_layout`, etc.) is split from widgets for headless unit tests.

## Engineering highlights

{{ENGINEERING_LIST}}

## Quick start

1. Download and extract the latest release zip.
2. Run `meowwatch.exe`.
3. Enter your name → **Start new room** (code copies automatically).
4. Friend pastes the code under **Enter code from friend** → **Join**.
5. Drop the same video file on both windows.

## Compatibility

| Platform | Status |
| --- | --- |
| Windows x64 | Available |
| Windows ARM64 | Coming soon (x64 build runs under emulation today) |

{{REQUIREMENTS_NOTES}}

## Project status

{{STATUS}}. Six foundational product phases are shipped (solo playback → sync → chat → connect flow → themes → polish). Source code is developed privately; this repository is the public download and showcase surface.

Latest release: **{{VERSION}}**.

## About the product engineering

MeowWatch is built as a co-watching product first: lobby friction, presence cues, chat placement, theme personality, and sync reliability were iterated in real use — not specified upfront. The result is a Windows desktop app with a custom network client, signed update infrastructure, and 40+ alpha releases of continuous refinement.

## License

{{LICENSE_SUMMARY}}
