import 'package:flutter/foundation.dart';

enum SyncConnectionStatus { disconnected, connecting, handshaking, connected, error }

@immutable
class SyncConnectionState {
  const SyncConnectionState({required this.status, this.message});

  final SyncConnectionStatus status;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is SyncConnectionState &&
      other.status == status &&
      other.message == message;

  @override
  int get hashCode => Object.hash(status, message);
}

@immutable
class PeerPlayState {
  const PeerPlayState({
    required this.position,
    required this.paused,
    this.doSeek = false,
    this.setBy,
  });

  factory PeerPlayState.fromSeconds({
    required double seconds,
    required bool paused,
    bool doSeek = false,
    String? setBy,
  }) {
    return PeerPlayState(
      position: Duration(milliseconds: (seconds * 1000).round()),
      paused: paused,
      doSeek: doSeek,
      setBy: setBy,
    );
  }

  final Duration position;
  final bool paused;
  final bool doSeek;
  final String? setBy;

  double get positionSeconds => position.inMilliseconds / 1000.0;

  @override
  bool operator ==(Object other) =>
      other is PeerPlayState &&
      other.position == position &&
      other.paused == paused &&
      other.doSeek == doSeek &&
      other.setBy == setBy;

  @override
  int get hashCode => Object.hash(position, paused, doSeek, setBy);
}

/// A file a peer has announced loading. Used to warn about mismatches (you and
/// your friend watching different files). [sizeBytes] is the strongest match
/// signal (same file ⇒ same bytes); [name]/[duration] are softer fallbacks.
@immutable
class PeerFile {
  const PeerFile({
    required this.username,
    required this.name,
    this.sizeBytes,
    this.duration,
  });

  final String username;
  final String name;
  final int? sizeBytes;
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is PeerFile &&
      other.username == username &&
      other.name == name &&
      other.sizeBytes == sizeBytes &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(username, name, sizeBytes, duration);
}

enum PresenceKind { joined, left }

@immutable
class PresenceEvent {
  const PresenceEvent({
    required this.username,
    required this.kind,
    this.room,
    this.fileName,
    this.fromRoster = false,
  });

  final String username;
  final PresenceKind kind;
  final String? room;
  final String? fileName;

  /// True when this came from the server roster (List) — i.e. a user who was
  /// already in the room when we arrived, not a live join. Roster joins update
  /// membership silently; they don't fire a "joined" banner/system message.
  final bool fromRoster;
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.username,
    required this.text,
    this.timestamp,
    this.system = false,
  });

  final String username;
  final String text;

  /// When the message arrived locally. The Syncplay protocol carries no
  /// timestamp, so the chat store stamps this on receipt; null until then.
  final DateTime? timestamp;

  /// A local-only event line (e.g. "X joined the room"), rendered centered and
  /// dim rather than as a chat bubble. Never sent over the wire.
  final bool system;

  ChatMessage copyWith({DateTime? timestamp}) => ChatMessage(
        username: username,
        text: text,
        timestamp: timestamp ?? this.timestamp,
        system: system,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.username == username &&
      other.text == text &&
      other.timestamp == timestamp &&
      other.system == system;

  @override
  int get hashCode => Object.hash(username, text, timestamp, system);
}
