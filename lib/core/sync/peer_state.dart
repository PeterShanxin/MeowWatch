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

enum PresenceKind { joined, left }

@immutable
class PresenceEvent {
  const PresenceEvent({
    required this.username,
    required this.kind,
    this.room,
    this.fileName,
  });

  final String username;
  final PresenceKind kind;
  final String? room;
  final String? fileName;
}

@immutable
class ChatMessage {
  const ChatMessage({required this.username, required this.text});

  final String username;
  final String text;
}
