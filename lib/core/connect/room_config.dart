import 'package:flutter/foundation.dart';

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
  });

  final String server;
  final int port;

  /// The room to join on the server. This is the *effective* room — for a
  /// private room it already has the passphrase folded in (e.g.
  /// `happy-cat-11-k3pn`), which is what shareable join codes carry. An old
  /// room-only code (`happy-cat-11`) is just the bare name. See
  /// `core/connect/join_code.dart`.
  final String room;
  final String username;

  /// The room passphrase / server password, kept alongside the folded [room]
  /// so it can still be sent in the handshake (it matters on a private server;
  /// a public server ignores it — there privacy comes from the folded [room]).
  final String? password;

  /// If set, the watch screen loads this file and seeks to [resumePositionMs].
  final String? resumeFilePath;
  final int resumePositionMs;

  RoomConfig copyWith({
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    String? resumeFilePath,
    int? resumePositionMs,
  }) {
    return RoomConfig(
      server: server ?? this.server,
      port: port ?? this.port,
      room: room ?? this.room,
      username: username ?? this.username,
      password: password ?? this.password,
      resumeFilePath: resumeFilePath ?? this.resumeFilePath,
      resumePositionMs: resumePositionMs ?? this.resumePositionMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoomConfig &&
      other.server == server &&
      other.port == port &&
      other.room == room &&
      other.username == username &&
      other.password == password &&
      other.resumeFilePath == resumeFilePath &&
      other.resumePositionMs == resumePositionMs;

  @override
  int get hashCode => Object.hash(server, port, room, username, password,
      resumeFilePath, resumePositionMs);
}
