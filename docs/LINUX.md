# Linux desktop (local testing)

Linux is a **compile target for local two-window testing**. It is not a
shipped release. Windows stays the supported product; there is no Linux
installer, R2 asset, or in-app updater.

## Packages

On Debian/Ubuntu:

```bash
sudo apt install clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libmpv-dev mpv
```

`media_kit` uses the system libmpv. GTK 3 is required by the Flutter Linux
runner. clang / cmake / ninja are the usual Flutter desktop toolchain.

Enable the target once per machine:

```bash
flutter config --enable-linux-desktop
```

## Run two instances

The GTK application id is `com.shanxin.meowwatch` with
`G_APPLICATION_NON_UNIQUE`, so a second process opens a second window.

Give each process its own data dir, and force software decode so the two
players do not fight over one hardware decoder:

```bash
export MEOWWATCH_FORCE_SW_DECODE=1

MEOWWATCH_DATA_DIR=/tmp/meow-a flutter run -d linux
MEOWWATCH_DATA_DIR=/tmp/meow-b flutter run -d linux
```

Core loop that should work: window, Start / Join room, load a local video
(or a direct `http(s)` stream). Syncplay is `dart:io` TCP + STARTTLS and
is unchanged.

## What stays Windows-only

- **In-app updates.** `UpdateService` does not check R2 or apply a zip on
  Linux. Do not change the Windows updater or R2 publish path for this.
- **Pasted YouTube / Bilibili page URLs.** The resolver pins `yt-dlp.exe`.
  Load a local file or a direct stream URL instead.
- **The test suite.** Windows-path basename asserts and chat-overlay
  goldens skip on Linux. PR CI stays on hosted Windows. Do not move the
  gate to Linux.

`desktop_drop` and `file_selector` both have Linux implementations; drag
and drop should work on a real desktop session. Headless / no-display
environments can still `flutter build linux`. Opening windows needs a
display or Xvfb. Missing PipeWire or DRI3 prints a warning and does not
block boot.
