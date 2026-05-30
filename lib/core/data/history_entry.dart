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
      other.username == username;

  @override
  int get hashCode => Object.hash(id, filePath, fileName, fileSizeBytes,
      durationMs, lastPositionMs, playedAt, room, username);
}
