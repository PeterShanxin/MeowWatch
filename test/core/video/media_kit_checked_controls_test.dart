import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:meowwatch/core/video/media_kit_video_core.dart';

final class _Streams extends PlatformPlayer {
  _Streams() : super(configuration: const PlayerConfiguration());

  void endPlayback() {
    playingController.add(false);
    completedController.add(true);
  }
}

/// Records native dispatch, while the production MediaKitVideoCore owns the
/// recovery, load token, initialization waits and actual media_kit lock.
final class _Native implements NativePlayer {
  final data = _Streams();
  final dispatched = <List<String>>[];
  final ordinarySeeks = <Duration>[];
  bool decodeOnPlay = false;
  bool emitSeekPositions = false;
  Completer<void>? commandGate;
  @override
  PlayerState state = const PlayerState();
  @override
  PlayerStream get stream => data.stream;
  @override
  final completer = Completer<void>()..complete();
  Completer<void>? initialization;
  Completer<void>? videoInitialization;
  @override
  Future<void> get waitForPlayerInitialization =>
      initialization?.future ?? completer.future;
  @override
  Future<void> get waitForVideoControllerInitializationIfAttached =>
      videoInitialization?.future ?? Future.value();
  @override
  bool isPlayingStateChangeAllowed = false;
  @override
  bool isBufferingStateChangeAllowed = true;
  @override
  StreamController<bool> get completedController => data.completedController;
  @override
  StreamController<bool> get playingController => data.playingController;
  @override
  Future<void> command(
    List<String> command, {
    bool waitForInitialization = true,
  }) async {
    expect(waitForInitialization, isFalse);
    dispatched.add(List.of(command));
    if (emitSeekPositions && command.first == 'seek') {
      data.positionController.add(
        Duration(milliseconds: (double.parse(command[1]) * 1000).round()),
      );
    }
    await commandGate?.future;
  }

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) => NativePlayer.lock.synchronized(() async {
    data.videoParamsController.add(const VideoParams());
    if (!decodeOnPlay) {
      data.videoParamsController.add(const VideoParams(w: 640, h: 360));
      data.durationController.add(const Duration(minutes: 1));
    }
    data.playingController.add(false);
    await Future<void>.delayed(Duration.zero);
  });
  @override
  Future<void> stop({
    bool open = false,
    bool notify = true,
    bool synchronized = true,
  }) async {}
  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {}
  @override
  Future<void> play({bool synchronized = true}) async {
    if (state.completed) {
      await seek(Duration.zero, synchronized: false);
      if (emitSeekPositions) data.positionController.add(Duration.zero);
      state = state.copyWith(completed: false, playing: true);
    }
    data.videoParamsController.add(const VideoParams());
    data.videoParamsController.add(const VideoParams(w: 640, h: 360));
    data.durationController.add(const Duration(minutes: 1));
    data.playingController.add(true);
  }

  @override
  Future<void> pause({bool synchronized = true}) async {
    data.playingController.add(false);
  }

  @override
  Future<void> seek(Duration position, {bool synchronized = true}) async {
    ordinarySeeks.add(position);
  }

  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) async {}
  @override
  Future<void> dispose({bool synchronized = true}) => data.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final operation in ['play', 'seek']) {
    test(
      '$operation does not dispatch after revocation during probe recovery',
      () async {
        final native = _Native();
        final recovery = Completer<void>();
        final core = MediaKitVideoCore.forTesting(
          player: Player(platformPlayer: native),
          probeRecovery: recovery.future,
        );
        addTearDown(core.dispose);
        var active = true;
        void check() {
          if (!active) throw StateError('Revoked');
        }

        final pending = operation == 'play'
            ? core.playChecked(checkActive: check)
            : core.seekChecked(const Duration(seconds: 10), checkActive: check);
        final result = expectLater(pending, throwsStateError);
        active = false;
        recovery.complete();
        await result;
        expect(native.dispatched, isEmpty);
      },
    );

    test(
      '$operation does not dispatch after a same-source reload while queued',
      () async {
        final native = _Native();
        final recovery = Completer<void>();
        final core = MediaKitVideoCore.forTesting(
          player: Player(platformPlayer: native),
        );
        addTearDown(core.dispose);
        // A real load supplies the first source token, including native stream markers.
        await core.load('same.mkv');
        final held = Completer<void>();
        final blocker = NativePlayer.lock.synchronized(() async {
          held.complete();
          await recovery.future;
        });
        await held.future;
        final pending = operation == 'play'
            ? core.playChecked(checkActive: () {})
            : core.seekChecked(const Duration(seconds: 10), checkActive: () {});
        final result = expectLater(pending, throwsStateError);
        final replacement = core.load('same.mkv');
        recovery.complete();
        await blocker;
        await replacement;
        await result;
        expect(native.dispatched, isEmpty);
      },
    );
  }

  for (final wait in [
    'native lock',
    'player initialization',
    'video initialization',
  ]) {
    test('revoked pause cannot dispatch after $wait', () async {
      final native = _Native();
      final core = MediaKitVideoCore.forTesting(
        player: Player(platformPlayer: native),
      );
      addTearDown(core.dispose);
      final gate = Completer<void>();
      Future<void>? blocker;
      if (wait == 'native lock') {
        final acquired = Completer<void>();
        blocker = NativePlayer.lock.synchronized(() async {
          acquired.complete();
          await gate.future;
        });
        await acquired.future;
      } else if (wait == 'player initialization') {
        native.initialization = gate;
      } else {
        native.videoInitialization = gate;
      }
      var active = true;
      final result = expectLater(
        core.pauseChecked(
          checkActive: () {
            if (!active) throw StateError('Revoked');
          },
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      active = false;
      gate.complete();
      await blocker;
      await result;
      expect(native.dispatched, isEmpty);
    });
  }

  test('reset invalidates a play waiting on probe recovery', () async {
    final native = _Native();
    final recovery = Completer<void>();
    final core = MediaKitVideoCore.forTesting(
      player: Player(platformPlayer: native),
      probeRecovery: recovery.future,
    );
    addTearDown(core.dispose);
    final result = expectLater(
      core.playChecked(checkActive: () {}),
      throwsStateError,
    );
    await core.reset();
    recovery.complete();
    await result;
    expect(native.dispatched, isEmpty);
  });

  test(
    'valid checked controls dispatch exactly the expected native actions',
    () async {
      final native = _Native();
      final core = MediaKitVideoCore.forTesting(
        player: Player(platformPlayer: native),
      );
      addTearDown(core.dispose);
      await core.playChecked(checkActive: () {});
      await core.pauseChecked(checkActive: () {});
      await core.seekChecked(
        const Duration(milliseconds: 1250),
        checkActive: () {},
      );
      expect(native.dispatched, [
        ['set', 'pause', 'no'],
        ['set', 'pause', 'yes'],
        ['seek', '1.2500', 'absolute'],
      ]);
    },
  );

  test('dispose prevents a checked action waiting on initialization', () async {
    final native = _Native()..initialization = Completer<void>();
    final core = MediaKitVideoCore.forTesting(
      player: Player(platformPlayer: native),
    );
    final result = expectLater(
      core.playChecked(checkActive: () {}),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    await core.dispose();
    native.initialization!.complete();
    await result;
    expect(native.dispatched, isEmpty);
  });

  test('EOF replay publishes playing when mpv pause does not change', () async {
    final native = _Native();
    final core = MediaKitVideoCore.forTesting(
      player: Player(platformPlayer: native),
    );
    addTearDown(core.dispose);
    await core.load('same.mkv');
    native.state = const PlayerState(completed: true);
    native.data.endPlayback();
    await Future<void>.delayed(Duration.zero);
    expect(core.state.status.name, 'ended');

    final completions = <bool>[];
    final subscription = native.stream.completed.listen(completions.add);
    addTearDown(subscription.cancel);
    // The fake emits no property events for commands, like unpausing an mpv
    // player whose pause property is already false after EOF.
    await core.playChecked(checkActive: () {});
    await Future<void>.delayed(Duration.zero);
    expect(native.state.playing, isTrue);
    expect(native.state.completed, isFalse);
    expect(core.state.status.name, 'playing');
    expect(completions, [false]);
    expect(native.dispatched, [
      ['seek', '0.0000', 'absolute'],
      ['set', 'playlist-pos', '0'],
      ['set', 'pause', 'no'],
    ]);
  });

  test(
    'checked pause publishes state and gates native playing events',
    () async {
      final native = _Native()..state = const PlayerState(playing: true);
      final core = MediaKitVideoCore.forTesting(
        player: Player(platformPlayer: native),
      );
      addTearDown(core.dispose);
      await core.pauseChecked(checkActive: () {});
      await Future<void>.delayed(Duration.zero);
      expect(native.state.playing, isFalse);
      expect(native.isPlayingStateChangeAllowed, isFalse);
      expect(native.isBufferingStateChangeAllowed, isFalse);
      expect(core.state.status.name, 'paused');
    },
  );

  for (final checked in [false, true]) {
    test(
      '${checked ? 'checked' : 'ordinary'} EOF replay zero cannot trigger a paused-load probe recovery seek',
      () async {
        final native = _Native()
          ..decodeOnPlay = true
          ..emitSeekPositions = true;
        final core = MediaKitVideoCore.forTesting(
          player: Player(platformPlayer: native),
        );
        addTearDown(core.dispose);
        // The source only confirms after decode starts. Its probe seek to zero
        // emits no event, as mpv may coalesce an unchanged zero position.
        await core.load('same.mkv');
        expect(native.ordinarySeeks, [Duration.zero]);
        await core.seekChecked(const Duration(seconds: 59), checkActive: () {});
        await Future<void>.delayed(Duration.zero);
        expect(core.state.position, const Duration(seconds: 59));
        native.state = const PlayerState(completed: true);
        native.data.endPlayback();
        await Future<void>.delayed(Duration.zero);

        if (checked) {
          await core.playChecked(checkActive: () {});
        } else {
          await core.play();
        }
        await Future<void>.delayed(Duration.zero);
        // This tests actual backend side effects: replay must not enqueue the old
        // 59-second cursor as an ordinary corrective seek after its intended zero.
        expect(native.ordinarySeeks, [
          Duration.zero,
          if (!checked) Duration.zero,
        ]);
        expect(core.state.position, Duration.zero);
        expect(core.state.status.name, 'playing');
      },
    );
  }

  test(
    'invalidation after EOF seek stops the remaining restart actions',
    () async {
      final native = _Native()..state = const PlayerState(completed: true);
      final gate = native.commandGate = Completer<void>();
      final core = MediaKitVideoCore.forTesting(
        player: Player(platformPlayer: native),
      );
      addTearDown(core.dispose);
      var active = true;
      final result = expectLater(
        core.playChecked(
          checkActive: () {
            if (!active) throw StateError('Revoked');
          },
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(native.dispatched, [
        ['seek', '0.0000', 'absolute'],
      ]);
      active = false;
      gate.complete();
      await result;
      expect(native.dispatched, [
        ['seek', '0.0000', 'absolute'],
      ]);
    },
  );
}
