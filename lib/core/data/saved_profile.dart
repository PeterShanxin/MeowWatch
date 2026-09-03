import 'package:flutter/foundation.dart';

/// A connection the user has joined before. Auto-saved on every connect and
/// shown as a card on the Connect screen.
@immutable
class SavedProfile {
  const SavedProfile({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    required this.room,
    required this.username,
    required this.password,
    required this.lastUsedAt,
    this.endpointPinned = false,
  });

  final int id;
  final String name;
  final String server;
  final int port;
  final String room;
  final String username;
  final String? password;
  final DateTime? lastUsedAt;

  /// True when this room was saved as an exact destination (Advanced,
  /// `room@host:port`, self-hosted). False when MeowWatch chose a public
  /// candidate and a later launch may walk.
  final bool endpointPinned;

  SavedProfile copyWith({
    int? id,
    String? name,
    String? server,
    int? port,
    String? room,
    String? username,
    String? password,
    DateTime? lastUsedAt,
    bool? endpointPinned,
  }) {
    return SavedProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      room: room ?? this.room,
      username: username ?? this.username,
      password: password ?? this.password,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      endpointPinned: endpointPinned ?? this.endpointPinned,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedProfile &&
      other.id == id &&
      other.name == name &&
      other.server == server &&
      other.port == port &&
      other.room == room &&
      other.username == username &&
      other.password == password &&
      other.lastUsedAt == lastUsedAt &&
      other.endpointPinned == endpointPinned;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    server,
    port,
    room,
    username,
    password,
    lastUsedAt,
    endpointPinned,
  );
}
