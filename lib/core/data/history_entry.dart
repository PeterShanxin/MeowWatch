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
  });

  final int id;
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int? durationMs;
  final int lastPositionMs;
  final DateTime playedAt;

  HistoryEntry copyWith({
    int? id,
    String? filePath,
    String? fileName,
    int? fileSizeBytes,
    int? durationMs,
    int? lastPositionMs,
    DateTime? playedAt,
  }) {
    return HistoryEntry(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      durationMs: durationMs ?? this.durationMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playedAt: playedAt ?? this.playedAt,
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
      other.playedAt == playedAt;

  @override
  int get hashCode => Object.hash(id, filePath, fileName, fileSizeBytes,
      durationMs, lastPositionMs, playedAt);
}
