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
  /// Used for a saved room or Continue Watching whose stored provenance
  /// is discoverable — not merely because the address is on the public list.
  discoverFromRoom,
}

/// Launch policy for a stored profile or history row. The pin is written
/// when the room is saved, so a later join does not guess from the public list.
SyncplayEndpointPolicy endpointPolicyFromPin(bool pinned) => pinned
    ? SyncplayEndpointPolicy.pinned
    : SyncplayEndpointPolicy.discoverFromRoom;

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
    this.persistUsername,
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
    // New Local Start keeps the typed destination exact if it later
    // becomes synced. Continue Watching must pass the stored pin.
    bool endpointPinned = true,
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
      endpointPolicy: endpointPolicyFromPin(endpointPinned),
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

  /// Username written to the saved-room card after Hello. A one-session
  /// name override (Join as alice this time) keeps the room's stored
  /// identity so it does not mint a second card.
  final String? persistUsername;

  /// Persist this session as a pin, not as a discoverable public room.
  bool get persistEndpointPinned =>
      endpointPolicy == SyncplayEndpointPolicy.pinned;

  /// Identity [ProfileStore.saveUsed] writes after Hello.
  String get persistAsUsername => persistUsername ?? username;

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
    String? persistUsername,
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
      persistUsername: persistUsername ?? this.persistUsername,
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
      other.copyShareCode == copyShareCode &&
      other.persistUsername == persistUsername;

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
    persistUsername,
  );
}
