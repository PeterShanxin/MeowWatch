# Third-party notices

MeowWatch downloads the following external tools at runtime (on first use of
the paste-a-page-link feature) from their official release channels. They are
separate programs invoked as subprocesses; they are not linked into MeowWatch
and are not redistributed inside MeowWatch's release archives.

## yt-dlp

- Source: <https://github.com/yt-dlp/yt-dlp> (downloaded from its official
  GitHub releases, verified against the release's published SHA-256 checksums)
- License: the yt-dlp source is released into the public domain (Unlicense);
  the official Windows executable is a PyInstaller-bundled work that includes
  GPLv3+-licensed components and is therefore licensed under GPLv3+. See the
  yt-dlp repository for the full license texts.
- Used to resolve a pasted page URL (YouTube, Bilibili, …) into a playable
  stream URL. Nothing is downloaded or re-hosted by MeowWatch itself.

## Deno

- Source: <https://github.com/denoland/deno> (downloaded from its official
  GitHub releases)
- License: MIT
- Used by yt-dlp as its JavaScript runtime for full YouTube support.

## Bundled Flutter/Dart dependencies

MeowWatch itself is built with Flutter and the pub.dev packages listed in
`pubspec.yaml`, including media_kit (MIT) with its bundled libmpv build. See
each package's listing on pub.dev for its license.
