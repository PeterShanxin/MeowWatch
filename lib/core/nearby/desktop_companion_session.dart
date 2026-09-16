import 'dart:async';
import 'dart:convert';

// The public constructor keeps descriptive, non-private getter names while the
// stored callbacks stay implementation details.
// ignore_for_file: prefer_initializing_formals

import 'package:crypto/crypto.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import '../chat/chat_store.dart';
import '../connect/room_config.dart';
import '../session/session_mode.dart';
import '../sync/peer_state.dart';
import '../sync/sync_core.dart';
import '../sync/syncplay_constants.dart';
import '../video/playback_state.dart';
import '../video/video_core.dart';

typedef SessionValue<T> = T Function();

/// Adapts one already-running desktop player session to the Nearby protocol.
///
/// The owner replaces this adapter whenever [registeredGeneration] changes.
/// It borrows the existing video, chat and Syncplay objects; it never creates a
/// second session or exposes a source that the desktop has not accepted.
/// [sessionEpoch] must be the owning NearbyAuthority's current session epoch;
/// the owner replaces authority before binding a new generation.
final class DesktopCompanionSession implements NearbyCommandHandler {
  DesktopCompanionSession({
    required this.video,
    required this.desktopId,
    required this.desktopName,
    required this.sessionEpoch,
    required this.registeredGeneration,
    required SessionValue<SessionMode> currentMode,
    required SessionValue<RoomConfig> currentRoom,
    required SessionValue<String> currentUsername,
    required SessionValue<String?> acceptedSource,
    required SessionValue<Iterable<String>> participants,
    required SessionValue<int> currentGeneration,
    required SessionValue<int> currentMediaGeneration,
    required SessionValue<ChatStore?> currentChat,
    required SessionValue<SyncCore?> currentSync,
    DateTime Function() now = DateTime.now,
  }) : _currentMode = currentMode,
       _currentRoom = currentRoom,
       _currentUsername = currentUsername,
       _acceptedSource = acceptedSource,
       _participants = participants,
       _currentGeneration = currentGeneration,
       _currentMediaGeneration = currentMediaGeneration,
       _currentChat = currentChat,
       _currentSync = currentSync,
       _now = now {
    decodeBytes(desktopId, 16);
    decodeBytes(sessionEpoch, 16);
    validateName(desktopName);
    if (desktopName.length > 64) {
      throw const NearbyException('invalid_argument');
    }
    _lastVideoState = video.state;
    _bindExistingSession();
  }

  static const _snapshotThrottle = Duration(milliseconds: 250);
  static const _weekMilliseconds = 7 * 24 * 60 * 60 * 1000;
  static const _participantBudgetBytes = 12 * 1024;
  static const _chatBudgetBytes = 32 * 1024;
  static const _allowedReactions = {'❤️', '😂', '😮', '😢', '👏', '👍'};
  static const _capabilities = <String>[
    'playback.play',
    'playback.pause',
    'playback.seek',
    'chat.send',
    'chat.reaction',
    'chat.typing',
  ];

  final VideoCore video;
  final String desktopId;
  final String desktopName;
  final String sessionEpoch;
  final int registeredGeneration;
  final SessionValue<SessionMode> _currentMode;
  final SessionValue<RoomConfig> _currentRoom;
  final SessionValue<String> _currentUsername;
  final SessionValue<String?> _acceptedSource;
  final SessionValue<Iterable<String>> _participants;
  final SessionValue<int> _currentGeneration;
  final SessionValue<int> _currentMediaGeneration;
  final SessionValue<ChatStore?> _currentChat;
  final SessionValue<SyncCore?> _currentSync;
  final DateTime Function() _now;

  final _events = StreamController<NearbyServerEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _chatIds = Expando<String>('nearby-chat-id');
  late PlaybackState _lastVideoState;
  List<ChatMessage> _lastChat = const [];
  Timer? _snapshotTimer;
  bool _snapshotMicrotaskQueued = false;
  bool _disposed = false;
  int _stateRevision = 0;
  int _nextChatId = 0;

  @override
  int get stateRevision => _stateRevision;

  @override
  Stream<NearbyServerEvent> get events => _events.stream;

  @override
  Map<String, Object?> get snapshot {
    _requireCurrentGeneration();
    final generation = _currentGeneration();
    final mode = _currentMode();
    final room = _currentRoom();
    final username = _safeName(_currentUsername(), fallback: desktopName);
    final source = _acceptedSource();
    final playback = video.state;
    final sync = _currentSync();
    final chat = _currentChat();
    final peers = _participantSnapshot(username);
    final messages = _chatSnapshot(chat);
    if (generation != _currentGeneration() ||
        generation != registeredGeneration) {
      throw const NearbyException('session_changed');
    }

    return <String, Object?>{
      'desktop': <String, Object?>{
        'id': desktopId,
        'name': desktopName,
        'protocolVersion': 1,
        'capabilities': _capabilities,
      },
      'session': <String, Object?>{
        'epoch': sessionEpoch,
        'mode': mode.isSynced ? 'synced' : 'local',
        'username': username,
        'connection': mode.isSynced
            ? _connectionName(sync?.lastConnectionState?.status)
            : 'disconnected',
        if (mode.isSynced) ...<String, Object?>{
          'room': room.room,
          'server': room.server,
          'port': room.port,
        },
      },
      'playback': _playbackSnapshot(playback, source),
      'participants': peers,
      'chat': messages,
    };
  }

  void _bindExistingSession() {
    _subscriptions.add(
      video.stateStream.listen((state) {
        final immediate =
            state.status != _lastVideoState.status ||
            state.filePath != _lastVideoState.filePath;
        _lastVideoState = state;
        _changed(immediate: immediate);
      }),
    );
    final chat = _currentChat();
    if (chat != null) {
      _lastChat = chat.messages;
      _subscriptions
        ..add(
          chat.stream.listen((messages) {
            final added = appendedMessages(_lastChat, messages);
            _lastChat = messages;
            _changed(immediate: true);
            for (final message in added) {
              _publish('chat.message', _chatMessage(message));
            }
          }),
        )
        ..add(
          chat.reactions.listen((event) {
            _publish('chat.reaction', <String, Object?>{
              'username': _safeName(event.username, fallback: 'Peer'),
              'reaction': event.emoji,
            });
          }),
        )
        ..add(
          chat.typing.listen((event) {
            _publish('chat.typing', <String, Object?>{
              'username': _safeName(event.username, fallback: 'Peer'),
              'typing': event.isTyping,
            });
          }),
        );
    }
    final sync = _currentSync();
    if (sync != null) {
      _subscriptions
        ..add(sync.connectionState.listen((_) => _changed(immediate: true)))
        ..add(
          sync.presence.listen((event) {
            _publish('presence', <String, Object?>{
              'username': _safeName(event.username, fallback: 'Peer'),
              'kind': event.kind == PresenceKind.joined ? 'joined' : 'left',
            });
            // Home updates its participant set from the same broadcast event.
            // Defer the snapshot so all synchronous listeners observe one view.
            _changed(immediate: true);
          }),
        );
    }
  }

  void _changed({required bool immediate}) {
    if (_disposed || _currentGeneration() != registeredGeneration) return;
    _stateRevision++;
    if (immediate) {
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      if (_snapshotMicrotaskQueued) return;
      _snapshotMicrotaskQueued = true;
      scheduleMicrotask(() {
        _snapshotMicrotaskQueued = false;
        _emitSnapshot();
      });
      return;
    }
    _snapshotTimer ??= Timer(_snapshotThrottle, () {
      _snapshotTimer = null;
      _emitSnapshot();
    });
  }

  void _emitSnapshot() {
    if (_disposed || _currentGeneration() != registeredGeneration) return;
    try {
      _publish('state.snapshot', snapshot);
    } on NearbyException catch (error) {
      if (error.code != 'session_changed') rethrow;
    }
  }

  void _publish(String type, Map<String, Object?> body) {
    if (_disposed || _currentGeneration() != registeredGeneration) return;
    _events.add(NearbyServerEvent(type, body));
  }

  @override
  Future<Map<String, Object?>> handle(NearbyCommand command) async {
    _check(command);
    if (command.sessionEpoch != sessionEpoch) {
      throw const NearbyException('session_changed');
    }
    switch (command.method) {
      case 'playback.play':
        _emptyArgs(command.args);
        _requireMedia();
        await _runNative(
          command,
          (controls, check) => controls.playChecked(checkActive: check),
        );
      case 'playback.pause':
        _emptyArgs(command.args);
        _requireMedia();
        await _runNative(
          command,
          (controls, check) => controls.pauseChecked(checkActive: check),
        );
      case 'playback.seek':
        final position = _integerArg(command.args, 'positionMs');
        if (command.args.length != 1 ||
            position < 0 ||
            position > _weekMilliseconds) {
          throw const NearbyException('invalid_argument');
        }
        _requireMedia();
        final duration = video.state.duration.inMilliseconds;
        final bounded = duration > 0 && position > duration
            ? duration
            : position;
        await _runNative(
          command,
          (controls, check) => controls.seekChecked(
            Duration(milliseconds: bounded),
            checkActive: check,
          ),
        );
      case 'chat.send':
        final text = _stringArg(command.args, 'text');
        if (command.args.length != 1 ||
            text.trim().isEmpty ||
            text.runes.length > SyncplayConstants.maxChatMessageLength) {
          throw const NearbyException('invalid_argument');
        }
        _runChat(command, (chat) => chat.send(text));
      case 'chat.reaction':
        final reaction = _stringArg(command.args, 'reaction');
        if (command.args.length != 1 || !_allowedReactions.contains(reaction)) {
          throw const NearbyException('invalid_argument');
        }
        _runChat(command, (chat) => chat.sendReaction(reaction));
      case 'chat.typing':
        final typing = command.args['typing'];
        if (command.args.length != 1 || typing is! bool) {
          throw const NearbyException('invalid_argument');
        }
        _runChat(command, (chat) => chat.sendTyping(isTyping: typing));
      default:
        throw const NearbyException('unsupported_command');
    }
    return const <String, Object?>{};
  }

  Future<void> _runNative(
    NearbyCommand command,
    Future<void> Function(GuardedVideoControls controls, void Function() check)
    action,
  ) async {
    final mediaGeneration = _currentMediaGeneration();
    final source = _acceptedSource();
    void check() {
      _check(command);
      if (mediaGeneration != _currentMediaGeneration() ||
          source != _acceptedSource()) {
        throw const NearbyException('session_changed');
      }
    }

    check();
    final controls = video;
    if (controls is! GuardedVideoControls) {
      throw const NearbyException('unsupported_command');
    }
    try {
      await action(controls as GuardedVideoControls, check);
    } on UnsupportedError {
      check();
      throw const NearbyException('unsupported_command');
    } catch (_) {
      check();
      throw const NearbyException('native_failure');
    }
    check();
  }

  void _runChat(NearbyCommand command, void Function(ChatStore chat) action) {
    _check(command);
    final sync = _currentSync();
    final chat = _currentChat();
    if (_currentMode().isLocal ||
        sync?.lastConnectionState?.status != SyncConnectionStatus.connected ||
        chat == null) {
      throw const NearbyException('not_connected');
    }
    try {
      action(chat);
    } catch (_) {
      _check(command);
      throw const NearbyException('native_failure');
    }
    _check(command);
  }

  void _check(NearbyCommand command) {
    command.checkActive();
    _requireCurrentGeneration();
  }

  void _requireCurrentGeneration() {
    if (_disposed || _currentGeneration() != registeredGeneration) {
      throw const NearbyException('session_changed');
    }
  }

  void _requireMedia() {
    if (_acceptedSource() == null) {
      throw const NearbyException('no_media');
    }
  }

  List<Map<String, Object?>> _participantSnapshot(String username) {
    final result = <Map<String, Object?>>[
      <String, Object?>{'username': username, 'isSelf': true},
    ];
    var encodedBytes = _jsonBytes(result.single);
    final seen = <String>{username};
    for (final peer in _participants()) {
      final safe = _safeNameOrNull(peer);
      if (safe == null || !seen.add(safe)) continue;
      final item = <String, Object?>{'username': safe, 'isSelf': false};
      final itemBytes = _jsonBytes(item) + 1;
      if (encodedBytes + itemBytes > _participantBudgetBytes) break;
      encodedBytes += itemBytes;
      result.add(item);
      if (result.length == 256) break;
    }
    return result;
  }

  List<Map<String, Object?>> _chatSnapshot(ChatStore? chat) {
    if (chat == null) return const [];
    final messages = chat.messages;
    final start = messages.length > 100 ? messages.length - 100 : 0;
    final newestFirst = <Map<String, Object?>>[];
    var encodedBytes = 0;
    for (var index = messages.length - 1; index >= start; index--) {
      final item = _chatMessage(messages[index]);
      final itemBytes = _jsonBytes(item) + 1;
      if (encodedBytes + itemBytes > _chatBudgetBytes) break;
      encodedBytes += itemBytes;
      newestFirst.add(item);
    }
    return newestFirst.reversed.toList(growable: false);
  }

  Map<String, Object?> _chatMessage(ChatMessage message) => <String, Object?>{
    'id': _chatId(message),
    'username': message.system
        ? _safeName(message.username, fallback: 'MeowWatch')
        : _safeName(message.username, fallback: 'Peer'),
    'text': _bounded(message.text, 4096),
    'receivedAtUnixMs': (message.timestamp?.millisecondsSinceEpoch ?? 0).clamp(
      0,
      8640000000000000,
    ),
    'system': message.system,
    'isMine': message.isMine,
  };

  Map<String, Object?> _playbackSnapshot(PlaybackState state, String? source) {
    final media = source == null
        ? null
        : <String, Object?>{
            'id': _mediaId(source),
            'title': _mediaTitle(source),
            'kind': _mediaKind(source),
          };
    final ready = media != null && isPlaybackOpen(state);
    final status = switch (state.status) {
      PlaybackStatus.loading => 'loading',
      PlaybackStatus.error => 'failed',
      _ when ready => 'ready',
      _ => 'idle',
    };
    final position = state.position.inMilliseconds.clamp(0, _weekMilliseconds);
    final duration = state.duration.inMilliseconds;
    return <String, Object?>{
      'revision': _stateRevision,
      'sampledAtUnixMs': _now().millisecondsSinceEpoch.clamp(
        0,
        8640000000000000,
      ),
      'status': status,
      'positionMs': position,
      'durationMs': duration <= 0 ? null : duration.clamp(0, _weekMilliseconds),
      'playing': ready && state.status == PlaybackStatus.playing,
      'buffering': false,
      'media': media,
      if (state.status == PlaybackStatus.error) 'error': 'playback_failed',
    };
  }

  String _mediaId(String source) {
    final digest = sha256.convert(utf8.encode('$sessionEpoch\u0000$source'));
    return base64UrlEncode(digest.bytes.sublist(0, 16)).replaceAll('=', '');
  }

  String _chatId(ChatMessage message) =>
      _chatIds[message] ??= _opaqueId('chat\u0000${_nextChatId++}');

  String _opaqueId(String value) {
    final digest = sha256.convert(utf8.encode('$sessionEpoch\u0000$value'));
    return base64UrlEncode(digest.bytes.sublist(0, 16)).replaceAll('=', '');
  }

  String _mediaTitle(String source) {
    final uri = Uri.tryParse(source);
    final windowsDrive = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
    final remoteSyntax =
        !windowsDrive &&
        uri != null &&
        (uri.hasScheme || uri.hasAuthority || uri.hasQuery);
    if (remoteSyntax) {
      if (uri.host.isNotEmpty) return _bounded(uri.host, 256);
      if (uri.scheme == 'file' && uri.pathSegments.isNotEmpty) {
        final name = uri.pathSegments.last;
        if (name.trim().isNotEmpty) return _bounded(name, 256);
      }
      return 'Remote media';
    }
    final normalized = source.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash < 0 ? normalized : normalized.substring(slash + 1);
    return _bounded(name.trim().isEmpty ? 'Desktop media' : name, 256);
  }

  String _mediaKind(String source) {
    final uri = Uri.tryParse(source);
    final windowsDrive = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source);
    if (!windowsDrive &&
        uri != null &&
        (uri.hasAuthority ||
            uri.hasQuery ||
            (uri.hasScheme && uri.scheme != 'file'))) {
      return 'url';
    }
    return 'file';
  }

  String _connectionName(SyncConnectionStatus? status) => switch (status) {
    SyncConnectionStatus.connected => 'connected',
    SyncConnectionStatus.connecting => 'connecting',
    SyncConnectionStatus.handshaking => 'handshaking',
    SyncConnectionStatus.reconnecting => 'reconnecting',
    SyncConnectionStatus.disconnected ||
    SyncConnectionStatus.error ||
    null => 'disconnected',
  };

  static void _emptyArgs(Map<String, Object?> args) {
    if (args.isNotEmpty) throw const NearbyException('invalid_argument');
  }

  static String _stringArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String) throw const NearbyException('invalid_argument');
    return value;
  }

  static int _integerArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! int) throw const NearbyException('invalid_argument');
    return value;
  }

  static String _safeName(String value, {required String fallback}) =>
      _safeNameOrNull(value) ?? fallback;

  static int _jsonBytes(Map<String, Object?> value) =>
      utf8.encode(jsonEncode(value)).length;

  static String? _safeNameOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.runes.any((rune) => rune == 0)) return null;
    return _bounded(trimmed, 150);
  }

  static String _bounded(String value, int max) {
    if (value.length <= max) return value;
    var end = max;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return value.substring(0, end);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _snapshotTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _events.close();
  }
}
