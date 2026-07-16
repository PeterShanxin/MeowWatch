import 'package:flutter/foundation.dart';

import '../video/video_url.dart';

// Builders for the empty-screen "load a video to join" prompt — the persistent
// nudge shown to whoever is still on the no-video screen while a friend is
// already set up.
//
// Three triggers, so neither side is left guessing:
//  - a peer announced a loaded file (they're ready, waiting on us) — #116
//  - a peer started playback before we'd loaded anything — #60
//  - a peer announced a loaded *URL*, which we can one-click load too — #121
//
// Each returns null when the prompt shouldn't apply (we already have our own
// file, or the event is our own echo), so the caller can assign the result and
// only overwrite the current prompt when one is produced. Wording lives here so
// the file-, play-, and URL-triggered prompts stay consistent and don't fight.

/// A peer announced a loaded file while we have nothing loaded (#116). Mirrors
/// the loader's "hasn't loaded a video yet" heads-up from the other direction.
String? peerLoadedJoinPrompt({
  required bool localHasFile,
  required String? localUsername,
  required String peerUsername,
  required String peerFileName,
}) {
  if (localHasFile) return null;
  if (peerUsername == localUsername) return null;
  return '$peerUsername loaded "$peerFileName" — load the same video to join';
}

/// A peer drove playback while we have nothing loaded (#60).
String? peerStartedPlaybackJoinPrompt({
  required bool localHasFile,
  required String? localUsername,
  required String peerUsername,
}) {
  if (localHasFile) return null;
  if (peerUsername == localUsername) return null;
  return '$peerUsername started playback — load a video to join';
}

/// Empty-screen join-prompt state. [message] is always shown; [url] is set
/// only when it carries a one-click action — currently just
/// [peerLoadedUrlJoinPrompt]'s offer. Null for the plain-text prompts above
/// (a peer's local file, or the play-triggered nudge), which have no in-app
/// action to offer.
@immutable
class JoinPrompt {
  const JoinPrompt(this.message, {this.url});

  final String message;
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is JoinPrompt && other.message == message && other.url == url;

  @override
  int get hashCode => Object.hash(message, url);
}

/// A peer announced a loaded **URL** while we have nothing loaded — the
/// one-click cousin of [peerLoadedJoinPrompt] (#121, step 2 of #119's
/// URL-sharing arc; #129 shipped direct-URL playback). Returns null for a
/// local file (that case keeps [peerLoadedJoinPrompt]'s plain text, with no
/// action to offer) or when the same base guards from #116 apply: we already
/// have something loaded (including this very URL), or this is our own
/// echoed announce.
///
/// [peerFileUrl] must be the peer's *raw* announced name (not a
/// display-shortened form) — the returned [JoinPrompt.url] is what the
/// caller loads verbatim (any signed token intact), while [JoinPrompt.message]
/// shows the shortened, redacted form via [mediaDisplayName].
JoinPrompt? peerLoadedUrlJoinPrompt({
  required bool localHasFile,
  required String? localUsername,
  required String peerUsername,
  required String peerFileUrl,
}) {
  if (localHasFile) return null;
  if (peerUsername == localUsername) return null;
  if (!isHttpUrl(peerFileUrl)) return null;
  final url = peerFileUrl.trim();
  return JoinPrompt(
    '$peerUsername is watching ${mediaDisplayName(url)} — load it too',
    url: url,
  );
}
