import '../debug/log_redact.dart';

/// Failure levels libmpv reports. We subscribe at `error`, so anything below
/// these is noise that should never reach the log.
const _failureLevels = {'error', 'fatal'};

/// Format one libmpv log entry for the app log, or null to drop it.
///
/// media_kit surfaces two different things: `Player.stream.error`, which it
/// feeds from a *hand-picked* subset of log lines, and `Player.stream.log`,
/// which carries every line at the requested level. The subset is the problem
/// (#228): an `ffmpeg`-prefixed error is only forwarded when its text starts
/// with `tcp:`, so a rejected HTTP request reaches us as mpv's generic
/// `Failed to open <url>` summary and the line that actually names the cause
/// — `http: HTTP error 403 Forbidden`, a TLS failure, a DNS failure — is
/// dropped. Listening to the log stream instead keeps the reason.
///
/// [prefix] is mpv's subsystem tag (`ffmpeg`, `stream`, `cplayer`, `vd`, …);
/// it stays in the line because it's what tells a network failure apart from a
/// decoder one.
String? formatMpvLogLine({
  required String prefix,
  required String level,
  required String text,
}) {
  if (!_failureLevels.contains(level)) return null;
  final message = text.trim();
  if (message.isEmpty) return null;
  // Stream URLs carry signed, short-lived tokens; mpv embeds the whole URL in
  // its messages, and these lines go to a log file on disk.
  return 'video: mpv[$prefix] ${redactUrls(message)}';
}
