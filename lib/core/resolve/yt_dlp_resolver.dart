import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meowwatch/core/resolve/resolve_error.dart';
import 'package:meowwatch/core/resolve/resolved_media.dart';

/// Runs yt-dlp against a page URL and parses its `-J` JSON into a
/// [ResolvedMedia]. The process spawn is an injectable seam ([ProcessRunner])
/// so tests never touch a real binary.

/// Test seam for running yt-dlp: given the exe + args, yield its
/// [ProcessResult]. Only injected by tests — the production path uses
/// [Process.start] directly so a hung process can be killed (see
/// [_runWithTimeout]).
typedef ProcessRunner = Future<ProcessResult> Function(
    String exe, List<String> args);

/// Resolves a page URL (YouTube, Bilibili, …) into playable stream URLs by
/// invoking yt-dlp with a fixed, research-vetted argument list.
class YtDlpResolver {
  YtDlpResolver({
    required this.exePath,
    ProcessRunner? runner,
    this.timeout = const Duration(seconds: 60),
    // Public param stays `runner`; the field is private, so an initializing
    // formal can't be used here.
    // ignore: prefer_initializing_formals
  }) : _runner = runner;

  final String exePath;
  final Duration timeout;

  /// When set (tests), used instead of spawning a real process. Null in
  /// production, where [_runWithTimeout] owns a killable [Process].
  final ProcessRunner? _runner;

  /// Resolve [pageUrl]; throws [ResolveException] on any failure.
  Future<ResolvedMedia> resolve(String pageUrl) async {
    final args = <String>[
      '-J',
      '--no-playlist',
      '-I',
      '1',
      '-f',
      'bv*+ba/b',
      '--ignore-config',
      '--no-warnings',
      '--socket-timeout',
      '10',
      '--retries',
      '2',
      '--',
      pageUrl,
    ];

    final result = await _runWithTimeout(args);
    final stderr = result.stderr.toString();
    if (result.exitCode != 0) {
      throw ResolveException(mapYtDlpStderr(stderr), stderr.trim());
    }
    return _parse(pageUrl, result.stdout.toString());
  }

  Future<ProcessResult> _runWithTimeout(List<String> args) async {
    // Test path: no real OS process, so the timeout is a plain race with
    // nothing to kill.
    final runner = _runner;
    if (runner != null) {
      final result = await Future.any<ProcessResult?>([
        runner(exePath, args),
        Future<ProcessResult?>.delayed(timeout, () => null),
      ]);
      if (result == null) throw _timeoutException();
      return result;
    }

    // Production path: own the process so a hung yt-dlp is terminated on
    // timeout, not left running in the background (Codex P2). Process.run gives
    // back only a ProcessResult after completion, so it can't be killed.
    final process = await Process.start(exePath, args);
    // Drain both pipes eagerly; an unread stdout/stderr buffer can itself wedge
    // the child once it fills.
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exit = await Future.any<int?>([
      process.exitCode,
      Future<int?>.delayed(timeout, () => null),
    ]);
    if (exit == null) {
      process.kill(ProcessSignal.sigkill);
      // Reap the exit + drain so no pipe/process handle is leaked.
      unawaited(process.exitCode);
      unawaited(stdoutFuture);
      unawaited(stderrFuture);
      throw _timeoutException();
    }
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return ProcessResult(process.pid, exit, stdout, stderr);
  }

  ResolveException _timeoutException() => ResolveException(
        ResolveErrorKind.timeout,
        'yt-dlp did not finish within ${timeout.inSeconds}s',
      );

  ResolvedMedia _parse(String pageUrl, String stdout) {
    final Object? decoded;
    try {
      decoded = jsonDecode(stdout);
    } on FormatException catch (e) {
      throw ResolveException(
          ResolveErrorKind.unknown, 'malformed yt-dlp JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ResolveException(
          ResolveErrorKind.unknown, 'unexpected yt-dlp JSON shape');
    }
    // Series/episode pages (e.g. bilibili.tv `/play/<id>`) come back wrapped in
    // a one-entry playlist even under `--no-playlist`/`-I 1`. The entry itself
    // holds the same video object shape as a bare single video, so resolve it
    // rather than rejecting — that's what unlocks those URLs. A genuinely empty
    // playlist has nothing to play.
    if (decoded['_type'] == 'playlist') {
      final entries = decoded['entries'];
      if (entries is List && entries.isNotEmpty) {
        final first = entries.first;
        if (first is Map<String, dynamic>) {
          return _fromVideoObject(pageUrl, first);
        }
      }
      throw const ResolveException(ResolveErrorKind.unknown, 'empty playlist');
    }
    return _fromVideoObject(pageUrl, decoded);
  }

  /// Parse a yt-dlp single-video object (top-level, or one playlist entry) into
  /// a [ResolvedMedia]. Prefers split `requested_formats`; falls back to a
  /// muxed top-level `url`.
  ResolvedMedia _fromVideoObject(String pageUrl, Map<String, dynamic> video) {
    final title = video['title'] as String?;
    final formats = video['requested_formats'];
    if (formats is List && formats.isNotEmpty) {
      return _fromSplitFormats(pageUrl, title, formats);
    }
    final url = video['url'];
    if (url is String && url.isNotEmpty) {
      return ResolvedMedia(
        pageUrl: pageUrl,
        videoUrl: url,
        httpHeaders: _headers(video['http_headers']),
        title: title,
      );
    }
    throw const ResolveException(
        ResolveErrorKind.unknown, 'no stream URL in yt-dlp JSON');
  }

  ResolvedMedia _fromSplitFormats(
      String pageUrl, String? title, List<dynamic> formats) {
    final maps = formats.whereType<Map<String, dynamic>>().toList();
    // The entry with a real vcodec is the video; fall back to list order.
    Map<String, dynamic>? video;
    for (final f in maps) {
      final vcodec = f['vcodec'];
      if (vcodec is String && vcodec != 'none') {
        video = f;
        break;
      }
    }
    video ??= maps.isNotEmpty ? maps.first : null;
    final videoUrl = video?['url'];
    if (video == null || videoUrl is! String || videoUrl.isEmpty) {
      throw const ResolveException(
          ResolveErrorKind.unknown, 'no video URL in requested_formats');
    }
    Map<String, dynamic>? audio;
    for (final f in maps) {
      if (!identical(f, video) && f['url'] is String) {
        audio = f;
        break;
      }
    }
    final videoHeaders = _headers(video['http_headers']);
    // The audio stream is a separate CDN request and needs its own headers
    // (Bilibili gates it on the same Referer); fall back to the video's when
    // the audio format didn't carry them (they share an origin).
    final audioHeaders =
        audio == null ? const <String, String>{} : _headers(audio['http_headers']);
    return ResolvedMedia(
      pageUrl: pageUrl,
      videoUrl: videoUrl,
      audioUrl: audio?['url'] as String?,
      httpHeaders: videoHeaders,
      audioHeaders: audioHeaders.isEmpty ? videoHeaders : audioHeaders,
      title: title,
    );
  }

  static Map<String, String> _headers(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }
}
