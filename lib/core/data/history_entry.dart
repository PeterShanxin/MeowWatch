import 'package:flutter/foundation.dart';

/// A file the user has watched, with the position to resume from.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.durationMs,
    required this.lastPositionMs,
    required this.playedAt,
    this.room,
    this.username,
    this.server,
    this.port,
  });

  final int id;
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int? durationMs;
  final int lastPositionMs;
  final DateTime playedAt;

  /// Room code and the name used when this file was last opened in a room.
  /// Null for entries recorded before the schema added them (or outside a room).
  final String? room;
  final String? username;

  /// Syncplay endpoint used for this watch. This lets a history row resume
  /// without borrowing another saved room's connection details.
  final String? server;
  final int? port;

  HistoryEntry copyWith({
    int? id,
    String? filePath,
    String? fileName,
    int? fileSizeBytes,
    int? durationMs,
    int? lastPositionMs,
    DateTime? playedAt,
    String? room,
    String? username,
    String? server,
    int? port,
  }) {
    return HistoryEntry(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationMs: durationMs ?? this.durationMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playedAt: playedAt ?? this.playedAt,
      room: room ?? this.room,
      username: username ?? this.username,
      server: server ?? this.server,
      port: port ?? this.port,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.id == id &&
      other.filePath == filePath &&
      other.fileName == fileName &&
      other.fileSizeBytes == fileSizeBytes &&
      other.durationMs == durationMs &&
      other.lastPositionMs == lastPositionMs &&
      other.playedAt == playedAt &&
      other.room == room &&
      other.username == username &&
      other.server == server &&
      other.port == port;

  @override
  int get hashCode => Object.hash(
    id,
    filePath,
    fileName,
    fileSizeBytes,
    durationMs,
    lastPositionMs,
    playedAt,
    room,
    username,
    server,
    port,
  );
}
