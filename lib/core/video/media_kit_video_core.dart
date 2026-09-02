import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../debug/app_log.dart';
import '../debug/log_redact.dart';
import '../resolve/resolved_media.dart';
import 'await_open_result.dart';
import 'mpv_log_filter.dart';
import 'playback_state.dart';
import 'position_guard.dart';
import 'video_core.dart';
import 'video_decode_config.dart';
import 'video_url.dart';

class MediaKitVideoCore extends VideoCore {
  MediaKitVideoCore() : _player = Player() {
    // Create the render controller up front, BEFORE any media is opened. If it
    // is attached lazily (only once a VideoSurface mounts, i.e. after the first
    // open()), libmpv has no video output wired for that first file and it never
    // starts — which looked like "the first video won't play, but reloading a
    // new one works". Eager creation is also media_kit's documented pattern.
    videoController = VideoController(_player);
    _wireListeners();
    _configureDecoding();
  }

  final Player _player;
  late final VideoController videoController;
  late final List<StreamSubscription<Object?>> _subs;

  /// `false` from a [load] until playback is actually started or deliberately
  /// positioned ([play]/[seek]). While `false`, a freshly loaded file sits at
  /// 0:00 (we open with `play: false`), so non-zero positions in this window
  /// are stale ticks from the previous file and must be dropped (#132).
  bool _playbackStarted = false;

  /// `false` from a [load] until *this* load's `START_FILE` reset crosses the
  /// params stream. `_player.open` emits an empty `VideoParams()` synchronously
  /// inside its internal `stop(open: true)` — always, before the demuxer reads
  /// the new file — so that empty payload is the per-load boundary marker. Any
  /// non-empty params seen *before* it belongs to the previous (now superseded)
  /// file: libmpv events crossing a load boundary, exactly like the stale
  /// position ticks the position listener guards. Until we see the reset we must
  /// not let a stale params event latch [PlaybackState.opened] onto the new
  /// source (which a hung/bad new source would then ride into a false open).
  bool _paramsResetSeen = false;

  /// Token of the load probe's private seek back to 0:00 until its position
  /// event is observed. libmpv can deliver that event after the public resume
  /// seek has already landed; the position listener drops that one stale zero
  /// instead of flashing Continue Watching back to the beginning.
  int? _pendingProbeZeroToken;

  /// Re-seek of libmpv's physical cursor after a delayed probe-zero event. The
  /// retained [PlaybackState] alone is not enough: without this correction the
  /// UI still shows the resume point, but the next play starts from 0:00.
  Future<void>? _pendingProbeRecovery;

  /// In-flight [reset] (leave-room teardown) on this reused engine, or null when
  /// idle. [load] awaits it before touching the shared player so a fast re-join
  /// can't open a new source only for the previous room's trailing `stop()` to
  /// unload it (#143 review).
  Future<void>? _pendingReset;

  /// Monotonic per-attempt id, bumped in [_beginLoad]. The #228 re-resolve retry
  /// reopens the *same* page URL, so `state.filePath` can no longer tell an
  /// abandoned attempt from its successor — both carry the identical URL. Each
  /// load captures its token and every ownership check ([_forceDecodeToConfirmOpen],
  /// the split-audio step) gates on it, so a stalled attempt's late cleanup
  /// (pause/seek/unmute/failLoad) can never clobber the attempt that superseded
  /// it. A newer load always wins because it bumps this first.
  int _loadToken = 0;

  Player get player => _player;

  /// Configure libmpv decode and sync properties. Reads [Platform.environment]
  /// once so both env lookups share the same snapshot.
  ///
  /// **hwdec:** defaults to hardware decoding — zero-copy `d3d11va` on Windows,
  /// `auto-safe` elsewhere. Set [forceSoftwareDecodeEnvVar] for
  /// two-instance-on-one-PC local testing. See [video_decode_config.dart].
  ///
  /// **video-sync:** defaults to `display-resample` — locks frame presentation
  /// to the monitor refresh rate, resampling audio slightly to maintain A/V
  /// lock. Reduces judder and dropped frames. Set [forceAudioSyncEnvVar] to
  /// revert to mpv's `audio` (audio-clock master) mode, e.g. for VRR monitors
  /// or sync debugging.
  void _configureDecoding() {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      final env = Platform.environment;
      unawaited(
        platform.setProperty(
          'hwdec',
          resolveHwdec(
            forceSoftware: forceSoftwareDecodeFromEnv(env),
            isWindows: Platform.isWindows,
          ),
        ),
      );
      unawaited(
        platform.setProperty(
          'video-sync',
          resolveVideoSync(forceAudioSync: forceAudioSyncFromEnv(env)),
        ),
      );
    }
  }

  void _wireListeners() {
    _subs = [
      _player.stream.playing.listen((playing) {
        // mpv keeps emitting playing/position churn around a failed open; never
        // let those downgrade a sticky error back to paused/playing and unmask
        // the error screen. Only load() clears the error (it resets the state).
        if (state.status == PlaybackStatus.error) return;
        emit(
          state.copyWith(
            status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          ),
        );
      }),
      _player.stream.position.listen((pos) {
        // Reject a stale end-of-file position from the previous file that
        // libmpv can deliver mid-load — otherwise a freshly loaded episode
        // shows the old one's end instead of 0:00, and a room would broadcast
        // the wrong position (#132). See [acceptPlayerPosition].
        final probeZeroPending = _pendingProbeZeroToken == _loadToken;
        final recoveryTarget = lateProbeZeroRecoveryTarget(
          incoming: pos,
          current: state.position,
          started: _playbackStarted,
          probeZeroPending: probeZeroPending,
        );
        final accepted = acceptPlayerPosition(
          incoming: pos,
          current: state.position,
          duration: state.duration,
          started: _playbackStarted,
          probeZeroPending: probeZeroPending,
        );
        // Consume the probe marker on its first zero event whether accepted
        // (normal paused load) or rejected (late after a resume seek).
        if (probeZeroPending && pos <= Duration.zero) {
          _pendingProbeZeroToken = null;
        }
        if (!accepted) {
          if (recoveryTarget != null) {
            appLog('trace: correcting late paused-load probe zero');
            late final Future<void> recovery;
            recovery = _restoreAfterLateProbeZero(recoveryTarget, _loadToken);
            _pendingProbeRecovery = recovery;
            unawaited(
              recovery.whenComplete(() {
                if (identical(_pendingProbeRecovery, recovery)) {
                  _pendingProbeRecovery = null;
                }
              }),
            );
          }
          return;
        }
        emit(state.copyWith(position: pos));
      }),
      _player.stream.duration.listen((dur) {
        // Boundary guard (mirrors the params/_markOpened guard): until this
        // load's START_FILE reset is seen, a non-zero duration belongs to the
        // source we just left. This matters because the engine is now reused
        // across rooms (#137) — a late duration from the previous room would
        // otherwise mark the new source "open" (isPlaybackOpen treats
        // duration>0 as opened) before it has really opened.
        if (!_paramsResetSeen) return;
        emit(state.copyWith(duration: dur));
      }),
      _player.stream.volume.listen((vol) {
        emit(state.copyWith(volume: vol / 100.0));
      }),
      _player.stream.completed.listen((done) {
        // Same boundary guard as duration/error: with the engine reused across
        // rooms (#137), a stale `completed` from the source we left (e.g. left at
        // EOF) must not mark the next source `ended` before its START_FILE reset
        // — awaitOpenResult treats `ended` as opened, so a slow/bad next source
        // would be falsely recorded/announced as loaded.
        if (!_paramsResetSeen) return;
        if (done && state.status != PlaybackStatus.error) {
          emit(state.copyWith(status: PlaybackStatus.ended));
        }
      }),
      // The demuxer reporting real audio/video params is the authoritative "this
      // source genuinely opened" signal — it fires only once data is actually
      // read, so (unlike a forced play/pause tick) a hung URL never produces it,
      // and (unlike a duration) a durationless live stream still does. mpv resets
      // videoParams to empty on each START_FILE (inside `open`), so an empty
      // payload is the reset, not an open: ignore it as evidence, but use it to
      // arm [_paramsResetSeen] — it marks the boundary after which params belong
      // to *this* load. Never let a late open unmask a sticky error (mirrors the
      // `playing`/`completed` guards above).
      _player.stream.videoParams.listen((p) {
        if (p.w == null || p.h == null) {
          // The empty START_FILE reset for the current load: params from here on
          // belong to this source.
          _paramsResetSeen = true;
          return;
        }
        _markOpened();
      }),
      _player.stream.audioParams.listen((p) {
        if (p.sampleRate != null) _markOpened();
      }),
      // Every libmpv failure line during the OPEN window, not just the few
      // media_kit promotes to its error stream — that subset drops the `ffmpeg`
      // line naming *why* an open failed and leaves only mpv's generic summary
      // (#228). Gated on `!state.opened`: once a source is confirmed open,
      // error-level chatter is benign playback noise — a YouTube DASH stream
      // hops CDN hosts mid-play and mpv logs "Cannot reuse HTTP connection…" at
      // error level dozens of times per minute while playing perfectly. That is
      // not a failure and must not flood the log. Log-only: the error stream
      // below still owns the state transition, so an unguarded line here can't
      // error out a source it doesn't belong to.
      _player.stream.log.listen((entry) {
        if (state.opened) return;
        final line = formatMpvLogLine(
          prefix: entry.prefix,
          level: entry.level,
          text: entry.text,
        );
        if (line != null) appLog(line);
      }),
      _player.stream.error.listen((err) {
        // Same boundary guard as duration: with the engine reused across rooms
        // (#137), a late error from the source we left must not error out the
        // next room. A real error for this source arrives after its START_FILE
        // reset; a hung/failed load is still caught by the load() open-timeout.
        if (!_paramsResetSeen) return;
        // The text itself is already on disk via the log listener above (with
        // its mpv prefix, and redacted) — this line records that we *acted* on
        // it, which the raw mpv line can't say.
        appLog('video: mpv error: source failed');
        emit(
          state.copyWith(
            status: PlaybackStatus.error,
            errorMessage: err.toString(),
          ),
        );
      }),
    ];
  }

  /// Latch the current source as genuinely open (see the params listeners). No-op
  /// if this load hasn't crossed its `START_FILE` reset yet (the params event is
  /// stale, from a superseded source — see [_paramsResetSeen]), if already
  /// marked, or if the load already failed — a late params event must not revive
  /// a sticky error screen.
  void _markOpened() {
    if (!_paramsResetSeen) return;
    if (state.opened || state.status == PlaybackStatus.error) return;
    emit(state.copyWith(opened: true));
  }

  /// Load a local file path *or* a direct `http(s)` stream URL — mpv accepts
  /// both in the same `Media(...)` slot, so a URL needs no special engine path.
  /// [mediaSourceName] keeps the display/announce name a base filename for a
  /// file and the full link for a URL (the Syncplay convention).
  @override
  Future<void> load(String source) async {
    final token = await _beginLoad(source);
    await _player.open(Media(source), play: false);
    await _forceDecodeToConfirmOpen(source, token);
  }

  /// Open a yt-dlp-resolved page: play [ResolvedMedia.videoUrl] (with the
  /// CDN's required headers — Bilibili 403s without Referer) while the state
  /// carries the *page* URL, so the room announces a link every peer can
  /// resolve on their side and the short-lived stream URL never leaves this
  /// machine. When yt-dlp returned split formats, the audio stream is attached
  /// as an external audio track once the video confirmed open.
  @override
  Future<void> loadResolved(ResolvedMedia media) async {
    final pageUrl = media.pageUrl;
    final token = await _beginLoad(pageUrl);
    await _player.open(
      Media(
        media.videoUrl,
        httpHeaders: media.httpHeaders.isEmpty ? null : media.httpHeaders,
      ),
      play: false,
    );
    await _forceDecodeToConfirmOpen(pageUrl, token);
    final audioUrl = media.audioUrl;
    if (audioUrl != null &&
        _loadToken == token &&
        state.status != PlaybackStatus.error) {
      // Split-format audio needs the same CDN headers as the video (Bilibili
      // gates it on the video's Referer). AudioTrack.uri has no header
      // parameter, but it doesn't need one: media_kit sets mpv's *global*
      // `http-header-fields` from the video Media during its `on_load` hook,
      // and `audio-add` does NOT re-fire `on_load`, so that global value
      // persists and the external-audio request inherits the video's headers.
      // (media_kit has no per-track header API; audio requiring headers that
      // differ from the video's is an unsupported edge — not our case, where
      // the two streams share an origin.)
      await _player.setAudioTrack(AudioTrack.uri(audioUrl));
    }
  }

  /// Shared pre-open sequence for [load]/[loadResolved]: wait out an in-flight
  /// leave-room [reset], re-arm the per-load guards, and emit the `loading`
  /// state keyed on [source] (the load's identity — the page URL for a
  /// resolved load).
  Future<int> _beginLoad(String source) async {
    // Claim this attempt's token BEFORE any await, so a load that starts while
    // an earlier one is still suspended immediately owns the engine and the
    // earlier attempt's token is already stale by the time it resumes.
    final token = ++_loadToken;
    // Let any in-flight leave-room [reset] finish first: the engine is shared
    // across rooms, so a fast re-join must not open a new source only for the
    // previous room's trailing stop() to unload it mid-load (#143 review).
    final pendingReset = _pendingReset;
    if (pendingReset != null) await pendingReset;
    // Arm the stale-position guard: until the user plays or seeks, the new file
    // legitimately sits at 0:00 and any non-zero tick is the previous file's
    // lingering end position (#132).
    _playbackStarted = false;
    _pendingProbeZeroToken = null;
    _pendingProbeRecovery = null;
    // Arm the params-open guard: a real params event seen before this load's
    // START_FILE reset is the previous source's, and must not latch `opened`.
    _paramsResetSeen = false;
    emit(
      state.copyWith(
        status: PlaybackStatus.loading,
        fileName: mediaSourceName(source),
        filePath: source,
        position: Duration.zero,
        duration: Duration.zero,
        errorMessage: null,
        // Clear the confirmed-open latch: this new source must re-prove it opens.
        opened: false,
      ),
    );
    return token;
  }

  /// Force the just-opened [source] to decode so it can confirm it opened.
  ///
  /// **The reused-engine paused-load trap.** We open every source paused
  /// (`play: false`) so two clients don't both jolt to 0:00. On a *fresh* engine
  /// that is fine — wiring the video output decodes the first frame, which emits
  /// the real audio/video params that latch [PlaybackState.opened]. But on the
  /// **reused** engine ([VideoEnginePool], #137) a second paused `open` decodes
  /// nothing: libmpv emits no params and no duration until playback actually
  /// starts, so [isPlaybackOpen] can never confirm the source and the load times
  /// out on a perfectly good file — the "Couldn't play that video / Timed out"
  /// screen users hit when switching episodes. (A `seek` does **not** wake the
  /// decoder; only starting playback does — confirmed from session logs.)
  ///
  /// So we briefly start playback to force exactly that decode, muted and at the
  /// start, then settle straight back to paused. This stays invisible to the
  /// room: the sync bridge only broadcasts a source after the load coordinator
  /// calls `markSourceOpen` — which happens *after* this returns — so the
  /// transient play is never published, and using the private [_player] (not the
  /// public [play]/[seek]) keeps `_playbackStarted` false so the file still
  /// legitimately sits at 0:00 for the user. A fresh-engine load that already
  /// proved open is skipped. The wait shares the coordinator's [openConfirmTimeout]
  /// (not a second stacked one); if the source never confirms within it we
  /// [failLoad] here so the coordinator's [awaitOpenResult] short-circuits rather
  /// than waiting the full budget again.
  Future<void> _forceDecodeToConfirmOpen(String source, int token) async {
    if (_loadToken != token) return; // superseded by a newer load
    if (isPlaybackOpen(state) || state.status == PlaybackStatus.error) return;

    final platform = _player.platform;
    final native = platform is NativePlayer ? platform : null;

    // Subscribe BEFORE playing so a near-instant open event can't slip past
    // between play() and the listen. Resolves true on confirmed open, false on an
    // error or a newer load superseding this attempt (token bumped — the retry
    // reuses the same URL, so filePath can't be the discriminator).
    final proven = Completer<bool>();
    void settle(bool opened) {
      if (!proven.isCompleted) proven.complete(opened);
    }

    final sub = stateStream.listen((s) {
      if (_loadToken != token || s.status == PlaybackStatus.error) {
        settle(false);
      } else if (isPlaybackOpen(s)) {
        settle(true);
      }
    });
    var opened = false;
    try {
      await native?.setProperty('mute', 'yes');
      await _player.play();
      // A valid file decodes its first frame within milliseconds. Share the
      // coordinator's [openConfirmTimeout] budget — NOT a second one stacked on
      // top — so a genuinely stuck source (e.g. an unresponsive URL) still fails
      // at ~12s, not ~22s.
      opened = await proven.future.timeout(openConfirmTimeout);
    } catch (_) {
      opened = false; // timed out or the stream closed
    } finally {
      await sub.cancel();
      // Own the engine only while this exact attempt is still current. A stalled
      // attempt whose token was bumped by a newer load must not pause, seek,
      // failLoad, or unmute the source that superseded it (same URL, #228).
      bool ownsSource() =>
          _loadToken == token && state.status != PlaybackStatus.error;
      if (ownsSource()) {
        // Stop the probe's playback in BOTH outcomes — including the timeout —
        // BEFORE surfacing anything. Otherwise a source that only recovers
        // *after* the budget keeps the probe's play() running and starts playing
        // audibly behind the (sticky) error screen, since post-error playing
        // ticks are ignored but the audio still comes out.
        await _player.pause();
        if (ownsSource() && opened) {
          // Settle back to a paused start.
          _pendingProbeZeroToken = token;
          await _player.seek(Duration.zero);
        } else if (ownsSource()) {
          // Never confirmed within the budget — surface the failure now so the
          // coordinator's own [awaitOpenResult] short-circuits on the error
          // instead of adding a second full timeout. [failLoad] no-ops if the
          // source genuinely opened.
          failLoad('Timed out waiting for the video to open.');
        }
      }
      if (_loadToken == token) {
        await native?.setProperty('mute', 'no');
      }
    }
  }

  Future<void> _restoreAfterLateProbeZero(Duration target, int token) async {
    if (_loadToken != token || target <= Duration.zero) return;
    try {
      await _player.seek(target);
      if (_loadToken == token) {
        appLog(
          'trace: restored paused-load probe position '
          '${target.inMilliseconds}ms',
        );
      }
    } catch (_) {
      if (_loadToken == token) {
        appLog('video: failed to restore paused-load probe position');
      }
    }
  }

  @override
  Future<void> play() async {
    _playbackStarted = true;
    appLog('trace: play');
    final recovery = _pendingProbeRecovery;
    if (recovery != null) await recovery;
    await _player.play();
  }

  @override
  Future<void> pause() {
    appLog('trace: pause');
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    _playbackStarted = true;
    // An explicit seek to the beginning owns that zero; do not mistake it for
    // the load probe's delayed event.
    if (position <= Duration.zero) _pendingProbeZeroToken = null;
    appLog('trace: seek ${position.inMilliseconds}ms');
    final recovery = _pendingProbeRecovery;
    if (recovery != null) await recovery;
    await _player.seek(position);
  }

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0.0, 1.0)) * 100.0);

  /// Empty the engine between rooms **without** tearing it down, so the same
  /// long-lived engine can be reused for the next room.
  ///
  /// This is the leave-room path instead of [dispose]: media_kit's
  /// [Player.dispose] runs libmpv's teardown on the UI isolate and, when players
  /// are created/destroyed repeatedly on Windows, `mpv_terminate_destroy` can
  /// deadlock there and permanently freeze the next screen (issue #137). We only
  /// ever [Player.stop] here — it unloads the current media but leaves the Player
  /// (and its [videoController] + listeners) usable. See [VideoEnginePool].
  ///
  /// Re-arms the same guards [load] sets so the reused engine starts the next
  /// room as cleanly as a fresh one, and emits a blank [PlaybackState] so the
  /// next screen opens on the load view with no stale file/position.
  Future<void> reset() async {
    _playbackStarted = false;
    _paramsResetSeen = false;
    _pendingProbeZeroToken = null;
    _pendingProbeRecovery = null;
    // Clear stored state synchronously, before any await, so the next room reads
    // a blank slate even if it mounts immediately. stop()'s trailing events
    // (playing:false, position/duration 0) are harmless on the load screen.
    emit(const PlaybackState());
    // Publish the teardown future synchronously (before yielding) so a fast
    // re-join's [load] can await it before reusing the shared player (#143).
    final done = _doReset();
    _pendingReset = done;
    await done;
    if (identical(_pendingReset, done)) _pendingReset = null;
  }

  /// The actual leave-room teardown. Stop playback **first** — that unloads the
  /// media so nothing bleeds into the lobby — *then* restore the pooled player's
  /// volume to what a freshly-created Player would have (100%). The engine is
  /// reused, so native properties persist across rooms; without this the next
  /// room's slider would read 100% while audio stayed silent. Order matters:
  /// raising volume before stop() could briefly play the previous room's audio
  /// at full volume (#143 review).
  ///
  /// Best-effort: a failed stop/volume call must not crash the (fire-and-forget)
  /// leave path nor reject [_pendingReset], which [load] awaits.
  Future<void> _doReset() async {
    // Teardown checkpoints for the intermittent leave-room freeze (#176): this
    // path can hard-deadlock with no thrown exception, so the checkpoints on disk
    // localize the blocking call. Written with appLogSync (not appLog): appLog
    // only queues an *async* flush a wedged isolate would never run, so the
    // marker could be lost exactly when it matters. appLogSync appends
    // synchronously to the crash-markers sidecar and returns only once the bytes
    // are on disk. Crash-proof by contract; never throws back into this teardown.
    //
    // Interpretation: stop() is async and reset() is started unawaited from
    // HomeScreen.dispose(), so `dispose home done` lands between `reset stop
    // begin` and `reset stop done`. It is `reset stop done` — NOT `dispose home
    // done` — that proves the engine actually stopped; `reset stop begin` with no
    // `reset stop done` means the freeze is in libmpv `stop()`.
    appLogSync('life: reset stop begin');
    try {
      await _player.stop();
      appLogSync('life: reset stop done');
      await _player.setVolume(100.0);
      appLogSync('life: reset volume done');
    } catch (e, st) {
      // Log the stack too (still diagnostics-only) so a captured session says
      // what failed, not just the message.
      appLogSync('life: reset error ${redactUrls('$e')}');
      appLogSync('life: reset stack ${redactUrls('$st')}');
    }
  }

  @override
  Future<void> disposeBackend() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
