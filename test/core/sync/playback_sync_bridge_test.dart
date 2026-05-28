import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/peer_state.dart';
import 'package:meowwatch/core/sync/playback_sync_bridge.dart';
import 'package:meowwatch/core/sync/sync_core.dart';
import 'package:meowwatch/core/video/playback_state.dart';
import 'package:meowwatch/core/video/video_core.dart';

class _FakeVideoCore extends VideoCore {
  @override
  Future<void> load(String filePath) async {
    emit(state.copyWith(fileName: filePath, status: PlaybackStatus.paused));
  }

  @override
  Future<void> play() async =>
      emit(state.copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async =>
      emit(state.copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> seek(Duration position) async =>
      emit(state.copyWith(position: position));

  @override
  Future<void> setVolume(double volume) async =>
      emit(state.copyWith(volume: volume));

  @override
  Future<void> disposeBackend() async {}

  void push(PlaybackState s) => emit(s);
}

class _RecordingSyncCore extends SyncCore {
  final List<({Duration position, bool paused})> localUpdates = [];
  final List<bool> changes = []; // doSeek values

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile(
      {required String name, required int size, required Duration duration}) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {
    localUpdates.add((position: position, paused: paused));
  }

  @override
  void notifyLocalChange({required bool doSeek}) => changes.add(doSeek);

  @override
  void sendChat(String text) {}

  @override
  Future<void> disposeBackend() async {}

  void pushPeer(PeerPlayState s) => emitPeerState(s);
}

void main() {
  late _FakeVideoCore video;
  late _RecordingSyncCore sync;
  late PlaybackSyncBridge bridge;

  setUp(() {
    video = _FakeVideoCore();
    sync = _RecordingSyncCore();
    bridge = PlaybackSyncBridge(video: video, sync: sync)..start();
  });

  tearDown(() async {
    await bridge.dispose();
    await video.dispose();
    await sync.dispose();
  });

  test('local pause toggle notifies a non-seek change', () async {
    video.push(
        const PlaybackState(status: PlaybackStatus.playing, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    video.push(
        const PlaybackState(status: PlaybackStatus.paused, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(false));
  });

  test('a large position jump is detected as a seek', () async {
    video.push(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 1),
        fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    video.push(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 30),
        fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    expect(sync.changes, contains(true));
  });

  test('applying a remote peer state does not re-notify a local change',
      () async {
    sync.changes.clear();
    sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 10), paused: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(sync.changes, isEmpty);
    expect(video.state.position, const Duration(seconds: 10));
  });

  test('remote paused transition pauses and aligns the local video', () async {
    video.push(
        const PlaybackState(status: PlaybackStatus.playing, fileName: 'a'));
    await Future<void>.delayed(Duration.zero);
    // First peer state (playing) is the initial adopt; then a pause flip.
    sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 4), paused: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 5), paused: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.status, PlaybackStatus.paused);
    expect(video.state.position, const Duration(seconds: 5));
  });

  test('steady peer heartbeats with unchanged paused flag do not seek',
      () async {
    // First state adopts position 10 (playing).
    sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 10), paused: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.position, const Duration(seconds: 10));
    // A later heartbeat reports a drifted position but no transition — the
    // bridge must NOT chase it (that chasing caused the fighting loop).
    sync.pushPeer(
        const PeerPlayState(position: Duration(seconds: 13), paused: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(video.state.position, const Duration(seconds: 10));
  });
}
