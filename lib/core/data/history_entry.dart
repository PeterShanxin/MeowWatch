import 'package:flutter/foundation.dart';

import 'watch_context.dart';

/// A file the user has watched in one room context, with the position to resume
/// from. Effective Local/synced mode does not split a real room into two rows.
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
    this.contextKey = kLocalWatchContextKey,
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

  /// `local` for legacy roomless playback, otherwise the stable
  /// `synced|{server}|{port}|{room}` room key (also used by Local sessions).
  final String contextKey;

  /// Room code and the name used when this file was last opened in a session.
  /// Legacy roomless rows can be null; real Local sessions retain their random
  /// room and use the same [contextKey] as synced mode in that room.
  final String? room;
  final String? username;

  /// Syncplay endpoint used for this watch. This lets a history row resume
  /// without borrowing another saved room's connection details (#194).
  final String? server;
  final int? port;

  bool get isLocalContext => contextKey == kLocalWatchContextKey;

  WatchContext get watchContext => isLocalContext
      ? WatchContext.local(server: server, port: port, room: room)
      : WatchContext.synced(
          server: server ?? '',
          port: port ?? 0,
          room: room ?? '',
        );

  HistoryEntry copyWith({
    int? id,
    String? filePath,
    String? fileName,
    int? fileSizeBytes,
    int? durationMs,
    int? lastPositionMs,
    DateTime? playedAt,
    String? contextKey,
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
      contextKey: contextKey ?? this.contextKey,
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
      other.contextKey == contextKey &&
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
    contextKey,
    room,
    username,
    server,
    port,
  );
}
