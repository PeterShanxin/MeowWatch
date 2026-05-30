# 🐱 MeowWatch

> A sleek, premium Windows-first co-watch application built with Flutter. Load a local video, connect to a Syncplay room, stay in perfect sync with your friends, and chat over a gorgeous floating overlay.

---

## ✨ Features

*   **Precision Synchronization**: Powered by a custom line-framed Dart implementation of the **Syncplay** protocol.
*   **Floating Cozy Chat**: Sleek, interactive transparent chat overlay built with a custom warm dark aesthetic.
*   **Windows-First Performance**: Native media playback powered by `libmpv` under the hood.
*   **Intuitive Drag & Drop**: Instantly load local video files by dragging them directly onto the player interface.

---

## 🛠️ Build & Development

This project utilizes the **Puro** Flutter environment manager. Always run commands using the Puro environment path to avoid compiler/SDK mismatch.

```powershell
# Define Flutter environment path
$FLUTTER = "C:/Users/shanx/.puro/envs/stable/flutter/bin/flutter.bat"

# Run project analysis
& $FLUTTER analyze

# Run test suite
& $FLUTTER test

# Compile release build (ensure running instances are closed)
& $FLUTTER build windows
```

---

## 📜 Credits & Acknowledgments

MeowWatch stands on the shoulders of giants. We express our deepest gratitude to the following open-source projects:

*   **[Syncplay](https://syncplay.pl/)**: For the standard-setting synchronization protocol, server architecture, and public rooms that make co-watching possible.
*   **[media_kit](https://github.com/media-kit/media-kit)** & **[mpv](https://mpv.io/)**: For providing the superb, high-performance video rendering engine (`libmpv`) and Flutter bindings.
*   **[desktop_drop](https://github.com/leanflutter/desktop_drop)**: For enabling seamless drag-and-drop UX.

---

## 📄 License

Copyright © 2026 MeowWatch. All rights reserved. 

The source code and binaries of MeowWatch are **Proprietary**. Unauthorized copying, modification, redistribution, or reverse engineering of this software is strictly prohibited under the terms of the proprietary license. See the [LICENSE](LICENSE) file for details.
