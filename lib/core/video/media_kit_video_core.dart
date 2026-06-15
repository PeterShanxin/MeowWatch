import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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

  /// In-flight [reset] (leave-room teardown) on this reused engine, or null when
  /// idle. [load] awaits it before touching the shared player so a fast re-join
  /// can't open a new source only for the previous room's trailing `stop()` to
  /// unload it (#143 review).
  Future<void>? _pendingReset;

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
        emit(state.copyWith(
          status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        ));
      }),
      _player.stream.position.listen((pos) {
        // Reject a stale end-of-file position from the previous file that
        // libmpv can deliver mid-load — otherwise a freshly loaded episode
        // shows the old one's end instead of 0:00, and a room would broadcast
        // the wrong position (#132). See [acceptPlayerPosition].
        if (!acceptPlayerPosition(
          incoming: pos,
          duration: state.duration,
          started: _playbackStarted,
        )) {
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
      _player.stream.error.listen((err) {
        // Same boundary guard as duration: with the engine reused across rooms
        // (#137), a late error from the source we left must not error out the
        // next room. A real error for this source arrives after its START_FILE
        // reset; a hung/failed load is still caught by the load() open-timeout.
        if (!_paramsResetSeen) return;
        emit(state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: err.toString(),
        ));
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
    // Let any in-flight leave-room [reset] finish first: the engine is shared
    // across rooms, so a fast re-join must not open a new source only for the
    // previous room's trailing stop() to unload it mid-load (#143 review).
    final pendingReset = _pendingReset;
    if (pendingReset != null) await pendingReset;
    // Arm the stale-position guard: until the user plays or seeks, the new file
    // legitimately sits at 0:00 and any non-zero tick is the previous file's
    // lingering end position (#132).
    _playbackStarted = false;
    // Arm the params-open guard: a real params event seen before this load's
    // START_FILE reset is the previous source's, and must not latch `opened`.
    _paramsResetSeen = false;
    emit(state.copyWith(
      status: PlaybackStatus.loading,
      fileName: mediaSourceName(source),
      filePath: source,
      position: Duration.zero,
      duration: Duration.zero,
      errorMessage: null,
      // Clear the confirmed-open latch: this new source must re-prove it opens.
      opened: false,
    ));
    await _player.open(Media(source), play: false);
  }

  @override
  Future<void> play() {
    _playbackStarted = true;
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) {
    _playbackStarted = true;
    return _player.seek(position);
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
    try {
      await _player.stop();
      await _player.setVolume(100.0);
    } catch (_) {}
  }

  @override
  Future<void> disposeBackend() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }
}
