<div align="center">

# 🐱 MeowWatch

**Watch videos together, in perfect sync.**

A sleek, Windows-first co-watch app built with Flutter. Drop in a local video, connect to a room, and stay perfectly synchronized with your friends — with a floating chat overlay, reaction bursts, and a cozy aesthetic.

![MeowWatch — co-watching in action](docs/assets/hero.png)

[![Build](https://github.com/PeterShanxin/MeowWatch/actions/workflows/build.yml/badge.svg)](https://github.com/PeterShanxin/MeowWatch/actions/workflows/build.yml)
![License](https://img.shields.io/badge/license-proprietary-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange)

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔄 **Precision Sync** | Custom Dart Syncplay client — TCP + startTLS, stateful heartbeat, convergence with `ignoringOnTheFly` / `setBy`. Two friends stay frame-accurate through any public Syncplay server. |
| 💬 **Floating Chat** | Drag-and-snap glass-card overlay — dock to any corner, collapse to a peek tab, Tab‑key toggle. Chat flows over the Syncplay channel (server echo, no optimistic insert). |
| 🎨 **3 Themes** | Cozy (warm dark), Cinema Noir (pure black), Glass Aurora (gradient + blur). Switch live from the lobby or in-player gear menu; choice persists in SQLite. |
| 🎬 **Drag & Drop** | Drop a video file onto the window — plays instantly via `libmpv`. Keyboard shortcuts: space, arrows, volume. |
| 📂 **Continue Watching** | SQLite-backed watch history with resume position, progress bar, room info, and one-click resume. |
| ⏸ **Smart Auto-Pause** | Pauses playback when sync drops or your friend disconnects (2 s debounce to ignore blips). Banner explains why. |
| 😸 **Reactions & Typing** | Floating emoji bursts sent over a sentinel-prefixed control channel. Typing indicators with 5 s watchdog. |
| 🐾 **Idle Mascot** | A hand-painted cat breathes, blinks, and wags its tail while you wait for a friend. |
| 🔄 **Auto-Update** | Checks for new releases, downloads in-app with a progress bar, and restarts seamlessly — no second copy on your PC. |

---

## 📥 Download

Grab the latest release from the **Releases** page:

| Platform | Status |
|---|---|
| Windows x64 (Intel / AMD) | ✅ Available |
| Windows ARM64 | 🔜 Coming soon |

> **Auto-update:** After the first install, MeowWatch updates itself in-place — just click "Install & Restart" when prompted.

---

## 🚀 Quick Start

1. **Download** and extract the zip
2. **Run** `meowwatch.exe`
3. **Enter** your name and click **Start new room** — a room code is copied to your clipboard
4. **Share** the code with your friend — they paste it under *Enter code from friend* and click **Join**
5. **Drop** the same video file onto both windows — you're in sync! 🎬

---

## 🏗 Building from Source

### Prerequisites

- [Flutter](https://flutter.dev/) 3.44+ (stable channel)
- Windows 10/11 with Visual Studio 2022 (Desktop C++ workload)
- Git

### Build

```powershell
# Clone
git clone https://github.com/PeterShanxin/MeowWatch.git
cd MeowWatch

# Resolve dependencies
flutter pub get

# Analyze
flutter analyze

# Run tests
flutter test

# Build release (kill any running instance first)
flutter build windows --release

# Output lives at:
# build/windows/x64/runner/Release/meowwatch.exe
```

---

## 🧩 Architecture

**Commands-in / streams-out.** The two core subsystems expose the same shape: abstract interfaces with imperative methods for input and broadcast `Stream`s for output. UI never reaches into internals.

```
lib/
├── core/
│   ├── video/      # VideoCore → MediaKitVideoCore (libmpv)
│   ├── sync/       # SyncCore → SyncplayClient (TCP + startTLS)
│   ├── chat/       # ChatStore — subscribes to SyncCore.chat
│   ├── update/     # UpdateService — R2-based auto-updater
│   └── data/       # Drift/SQLite stores (profiles, history, settings)
├── ui/
│   ├── connect/    # Lobby — room creation, join, profiles, history
│   ├── chat/       # Floating overlay, bubbles, reactions
│   ├── theme/      # Theme swatches, Cozy / Noir / Aurora
│   └── ...         # Video surface, playback bar, mascot, etc.
└── app.dart        # MaterialApp with theme wiring
```

Pure logic is split from widgets for headless unit testing: `sync_follow.dart`, `chat_corner.dart`, `chat_overlay_layout.dart`.

---

## 📋 Roadmap

All six foundational phases are shipped. See [docs/ROADMAP.md](docs/ROADMAP.md) for the full history and future work.

**Next up:**
- 🖥 Windows ARM64 native builds (CI runner pending)
- 📦 MSIX installer for Microsoft Store distribution
- 🗣 Voice chat overlay
- 🖼 Picture-in-Picture mode

---

## 📜 Credits & Acknowledgments

MeowWatch stands on the shoulders of giants:

- **[Syncplay](https://syncplay.pl/)** — The synchronization protocol and public server infrastructure that makes co-watching possible.
- **[media_kit](https://github.com/media-kit/media-kit)** & **[mpv](https://mpv.io/)** — High-performance video rendering engine (`libmpv`) and Flutter bindings (LGPL).
- **[desktop_drop](https://github.com/leanflutter/desktop_drop)** — Seamless drag-and-drop UX.
- **[Drift](https://drift.simonbinder.eu/)** — Reactive SQLite persistence layer.

---

## 📄 License

Copyright © 2026 MeowWatch. All rights reserved.

The source code and binaries of MeowWatch are **proprietary**. Unauthorized copying, modification, redistribution, or reverse engineering is strictly prohibited. See the [LICENSE](LICENSE) file for details.
