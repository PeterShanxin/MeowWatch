import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:meowwatch/core/connect/room_config.dart';
import 'package:meowwatch/core/nearby/desktop_companion_session.dart';
import 'package:meowwatch/core/session/session_mode.dart';
import 'package:meowwatch/core/video/media_kit_video_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:path/path.dart' as path;

const _outputDirectoryVariable = 'MEOWWATCH_NEARBY_PLAYER_SMOKE_DIR';
const _mediaVariable = 'MEOWWATCH_NEARBY_PLAYER_SMOKE_MEDIA';
const _probeTimeout = Duration(seconds: 50);
const _stateTimeout = Duration(seconds: 8);

/// Release-only Windows probe for the real media_kit backend and the checked
/// command path used by a paired Nearby phone. It does not open a Nearby
/// listener, use protected credentials, or read the normal application profile.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final outputRoot = Platform.environment[_outputDirectoryVariable];
  if (outputRoot == null || outputRoot.trim().isEmpty) exit(64);
  final outputDirectory = Directory(outputRoot).absolute;
  final safeOutput = path
      .split(outputDirectory.path)
      .any((segment) => segment.toLowerCase() == 'nearby-player-smoke');
  if (!safeOutput) exit(64);
  await outputDirectory.create(recursive: true);

  final result = <String, Object?>{
    'probe': 'nearby_player_native_dispatch',
    'platform': Platform.operatingSystem,
    'releaseMode': kReleaseMode,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'checks': <String>[],
    'observations': <String, Object?>{},
    'passed': false,
  };
  final checks = result['checks']! as List<String>;
  final observations = result['observations']! as Map<String, Object?>;
  MediaKitVideoCore? core;
  DesktopCompanionSession? session;

  try {
    if (!Platform.isWindows) throw const _SmokeFailure('windows_required');
    if (!kReleaseMode) throw const _SmokeFailure('release_required');
    final mediaValue = Platform.environment[_mediaVariable];
    if (mediaValue == null || mediaValue.trim().isEmpty) {
      throw const _SmokeFailure('media_required');
    }
    final mediaFile = File(mediaValue).absolute;
    if (!await mediaFile.exists()) {
      throw const _SmokeFailure('media_missing');
    }

    MediaKit.ensureInitialized();
    core = MediaKitVideoCore();
    runApp(_PlayerProbeApp(core: core));
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw const _SmokeFailure('surface_mount_timeout'),
    );

    final source = mediaFile.path;
    session = _createSession(core, source);
    await _runProbe(core, session, source, checks, observations).timeout(
      _probeTimeout,
      onTimeout: () => throw const _SmokeFailure('probe_timeout'),
    );
    result['passed'] = true;
  } on _SmokeFailure catch (error) {
    result['errorCode'] = error.code;
  } catch (error) {
    result['errorType'] = error.runtimeType.toString();
    result['errorCode'] = switch (error) {
      NearbyException(:final code) => code,
      _ => 'native_probe_failed',
    };
  } finally {
    if (core != null) {
      observations['finalState'] = _stateObservation(core);
    }
    try {
      await session?.dispose().timeout(const Duration(seconds: 3));
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(seconds: 3),
      );
      await core?.dispose().timeout(const Duration(seconds: 8));
    } catch (_) {
      result['passed'] = false;
      result['errorCode'] = 'cleanup_failed';
    }
  }

  result['completedAtUtc'] = DateTime.now().toUtc().toIso8601String();
  await File(
    path.join(outputDirectory.path, 'result.json'),
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  exit(result['passed'] == true ? 0 : 1);
}

DesktopCompanionSession _createSession(MediaKitVideoCore core, String source) {
  const generation = 1;
  final room = RoomConfig.local(
    username: 'Native playback probe',
    server: '127.0.0.1',
    port: 8999,
    room: 'nearby-player-smoke',
  );
  return DesktopCompanionSession(
    video: core,
    desktopId: encodeBytes(List<int>.filled(16, 1)),
    desktopName: 'MeowWatch native playback probe',
    sessionEpoch: encodeBytes(List<int>.filled(16, 2)),
    registeredGeneration: generation,
    currentMode: () => SessionMode.local,
    currentRoom: () => room,
    currentUsername: () => room.username,
    acceptedSource: () => source,
    participants: () => const <String>[],
    currentGeneration: () => generation,
    currentMediaGeneration: () => generation,
    currentChat: () => null,
    currentSync: () => null,
  );
}

Future<void> _runProbe(
  MediaKitVideoCore core,
  DesktopCompanionSession session,
  String source,
  List<String> checks,
  Map<String, Object?> observations,
) async {
  var commandNumber = 10;
  final sessionEpoch = session.sessionEpoch;

  Future<void> dispatch(String method, [Map<String, Object?> args = const {}]) {
    final command = NearbyCommand.forTesting(
      id: encodeBytes(List<int>.filled(16, commandNumber++)),
      sessionEpoch: sessionEpoch,
      method: method,
      args: args,
      checkActive: () {},
    );
    return session.handle(command).then((_) {});
  }

  await core
      .load(source)
      .timeout(
        const Duration(seconds: 18),
        onTimeout: () => throw const _SmokeFailure('load_timeout'),
      );
  final ready = await _waitForState(
    core,
    (state) => isPlaybackOpen(state) && state.duration > Duration.zero,
    'ready_timeout',
  );
  if (ready.duration < const Duration(seconds: 3)) {
    throw const _SmokeFailure('fixture_too_short');
  }
  checks.add('native_media_open');
  observations['durationMs'] = ready.duration.inMilliseconds;

  final playStart = ready.position;
  await dispatch('playback.play');
  checks.add('desktop_session_play_dispatch');
  final advanced = await _waitForState(
    core,
    (state) =>
        state.status == PlaybackStatus.playing &&
        state.position >= playStart + const Duration(milliseconds: 500),
    'play_advancement_timeout',
  );
  checks.add('playing_clock_advanced');
  observations['initialAdvanceMs'] =
      advanced.position.inMilliseconds - playStart.inMilliseconds;

  await dispatch('playback.pause');
  checks.add('desktop_session_pause_dispatch');
  final paused = await _waitForState(
    core,
    (state) => state.status == PlaybackStatus.paused,
    'pause_timeout',
  );
  await Future<void>.delayed(const Duration(milliseconds: 700));
  final pauseDrift = (core.state.position - paused.position).inMilliseconds
      .abs();
  if (core.state.status != PlaybackStatus.paused || pauseDrift > 350) {
    throw const _SmokeFailure('pause_not_stable');
  }
  checks.add('paused_clock_stable');
  observations['pauseDriftMs'] = pauseDrift;

  final duration = ready.duration;
  final seekTarget = Duration(milliseconds: duration.inMilliseconds * 2 ~/ 5);
  await dispatch('playback.seek', {'positionMs': seekTarget.inMilliseconds});
  checks.add('desktop_session_seek_dispatch');
  final sought = await _waitForState(
    core,
    (state) => (state.position - seekTarget).inMilliseconds.abs() <= 700,
    'seek_timeout',
  );
  checks.add('seek_observed');
  observations['seekTargetMs'] = seekTarget.inMilliseconds;
  observations['seekObservedMs'] = sought.position.inMilliseconds;

  final eofTarget = duration - const Duration(milliseconds: 900);
  await dispatch('playback.seek', {'positionMs': eofTarget.inMilliseconds});
  await _waitForState(
    core,
    (state) => (state.position - eofTarget).inMilliseconds.abs() <= 700,
    'eof_seek_timeout',
  );
  await dispatch('playback.play');
  await _waitForState(
    core,
    (state) => state.status == PlaybackStatus.ended,
    'eof_timeout',
  );
  checks.add('eof_observed');
  observations['atEof'] = _stateObservation(core);

  await dispatch('playback.play');
  checks.add('eof_replay_dispatch');
  observations['afterReplayDispatch'] = _stateObservation(core);
  final replaySamples = <Map<String, Object?>>[];
  observations['replaySamples'] = replaySamples;
  final sampleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (replaySamples.length < 32) replaySamples.add(_stateObservation(core));
  });
  late final PlaybackState replayed;
  try {
    replayed = await _waitForState(
      core,
      (state) =>
          state.status == PlaybackStatus.playing &&
          state.position >= const Duration(milliseconds: 250) &&
          state.position < Duration(milliseconds: duration.inMilliseconds ~/ 2),
      'eof_replay_timeout',
    );
  } finally {
    sampleTimer.cancel();
  }
  checks.add('replay_clock_advanced');
  observations['replayObservedMs'] = replayed.position.inMilliseconds;
  await dispatch('playback.pause');
}

Map<String, Object?> _stateObservation(MediaKitVideoCore core) => {
  'status': core.state.status.name,
  'positionMs': core.state.position.inMilliseconds,
  'nativePlaying': core.player.state.playing,
  'nativeCompleted': core.player.state.completed,
  'nativePositionMs': core.player.state.position.inMilliseconds,
};

Future<PlaybackState> _waitForState(
  MediaKitVideoCore core,
  bool Function(PlaybackState state) matches,
  String timeoutCode,
) async {
  final current = core.state;
  if (current.status == PlaybackStatus.error) {
    throw const _SmokeFailure('playback_error');
  }
  if (matches(current)) return current;
  try {
    final state = await core.stateStream
        .firstWhere(
          (state) => state.status == PlaybackStatus.error || matches(state),
        )
        .timeout(_stateTimeout);
    if (state.status == PlaybackStatus.error) {
      throw const _SmokeFailure('playback_error');
    }
    return state;
  } on TimeoutException {
    throw _SmokeFailure(timeoutCode);
  }
}

final class _PlayerProbeApp extends StatelessWidget {
  const _PlayerProbeApp({required this.core});

  final MediaKitVideoCore core;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(
              controller: core.videoController,
              controls: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

final class _SmokeFailure implements Exception {
  const _SmokeFailure(this.code);

  final String code;
}
