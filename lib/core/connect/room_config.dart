import 'package:flutter/foundation.dart';

import '../session/session_mode.dart';

/// How a synced session picks its Syncplay address (#234).
enum SyncplayEndpointPolicy {
  /// Use [RoomConfig.server] / [RoomConfig.port] exactly. Advanced, a
  /// `room@host:port` share code, a bare share code, and any self-hosted
  /// host. A bare code is a legacy compatibility pin — both copies of the
  /// app must agree without talking, so it always means the first public
  /// candidate, not a scan.
  pinned,

  /// Walk the public candidates. The remembered winner is tried first.
  /// Used for a default Start (no Advanced override).
  discover,

  /// Walk the public candidates, trying this room's saved address first.
  /// Used for a saved room or Continue Watching on a public endpoint.
  discoverFromRoom,
}

/// Everything the watch screen needs to join a room and optionally resume a
/// previously-watched file. Built by [ConnectScreen], consumed by HomeScreen.
@immutable
class RoomConfig {
  const RoomConfig({
    required this.server,
    required this.port,
    required this.room,
    required this.username,
    this.password,
    this.resumeFilePath,
    this.resumePositionMs = 0,
    this.sessionMode = SessionMode.synced,
    this.endpointPolicy = SyncplayEndpointPolicy.pinned,
    this.copyShareCode = false,
  });

  /// A Local playback session: real room identity, no Syncplay yet.
  /// [room]/[server]/[port] stay so the same session can become synced later.
  factory RoomConfig.local({
    required String username,
    required String server,
    required int port,
    required String room,
    String? password,
    String? resumeFilePath,
    int resumePositionMs = 0,
  }) {
    return RoomConfig(
      sessionMode: SessionMode.local,
      server: server,
      port: port,
      room: room,
      username: username,
      password: password,
      resumeFilePath: resumeFilePath,
      resumePositionMs: resumePositionMs,
    );
  }

  final SessionMode sessionMode;

  final String server;
  final int port;

  /// The room to join on the server. This is the *effective* room — and the
  /// whole shareable code. For a freshly started private room it's a short
  /// "magic sentence" (`sleepy-otter-counts-cozy-stars`) whose entropy makes it
  /// unguessable; an old room-only code (`happy-cat-11`) or folded
  /// `happy-cat-11-k3pn` code is just the bare string. See
  /// `core/connect/room_code.dart`.
  final String room;
  final String username;

  /// The Syncplay *server* password, sent in the handshake. It matters only on a
  /// private / self-hosted server; a public server ignores it. Room privacy does
  /// not come from this field — it comes from the unguessable [room] code.
  final String? password;

  /// If set, the watch screen loads this file and seeks to [resumePositionMs].
  final String? resumeFilePath;
  final int resumePositionMs;

  /// Whether this session may walk public candidates, or must use [server] /
  /// [port] exactly.
  final SyncplayEndpointPolicy endpointPolicy;

  /// After a successful Hello, copy a share code that names the endpoint the
  /// host actually landed on.
  final bool copyShareCode;

  RoomConfig copyWith({
    SessionMode? sessionMode,
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    String? resumeFilePath,
    int? resumePositionMs,
    SyncplayEndpointPolicy? endpointPolicy,
    bool? copyShareCode,
  }) {
    return RoomConfig(
      sessionMode: sessionMode ?? this.sessionMode,
      server: server ?? this.server,
      port: port ?? this.port,
      room: room ?? this.room,
      username: username ?? this.username,
      password: password ?? this.password,
      resumeFilePath: resumeFilePath ?? this.resumeFilePath,
      resumePositionMs: resumePositionMs ?? this.resumePositionMs,
      endpointPolicy: endpointPolicy ?? this.endpointPolicy,
      copyShareCode: copyShareCode ?? this.copyShareCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomConfig &&
      other.sessionMode == sessionMode &&
      other.server == server &&
      other.port == port &&
      other.room == room &&
      other.username == username &&
      other.password == password &&
      other.resumeFilePath == resumeFilePath &&
      other.resumePositionMs == resumePositionMs &&
      other.endpointPolicy == endpointPolicy &&
      other.copyShareCode == copyShareCode;

  @override
  int get hashCode => Object.hash(
    sessionMode,
    server,
    port,
    room,
    username,
    password,
    resumeFilePath,
    resumePositionMs,
    endpointPolicy,
    copyShareCode,
  );
}
