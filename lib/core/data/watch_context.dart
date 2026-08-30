import 'package:flutter/foundation.dart';

/// Sentinel identity for a Local-context history row.
const String kLocalWatchContextKey = 'local';

/// Kind of watch context a history row belongs to.
enum WatchContextKind { local, synced }

/// Where a watch happened: Local, or a specific Syncplay room endpoint.
///
/// Progress is per context, not per media. Identity is
/// `(media, local)` or `(media, server, port, room)` — username is metadata.
@immutable
class WatchContext {
  const WatchContext._({required this.kind, this.server, this.port, this.room});

  const WatchContext.local({this.server, this.port, this.room})
    : kind = WatchContextKind.local;

  factory WatchContext.synced({
    required String server,
    required int port,
    required String room,
  }) {
    return WatchContext._(
      kind: WatchContextKind.synced,
      server: server.trim(),
      port: port,
      room: room.trim(),
    );
  }

  final WatchContextKind kind;
  final String? server;
  final int? port;
  final String? room;

  bool get isLocal => kind == WatchContextKind.local;
  bool get isSynced => kind == WatchContextKind.synced;

  /// Unique context key stored on the history row.
  String get key => isLocal
      ? kLocalWatchContextKey
      : syncedWatchContextKey(server: server!, port: port!, room: room!);

  /// Session identity stored as metadata. It never participates in the Local
  /// context key, but preserves the real random room assigned to that session.
  String? get storedRoom => room;
  String? get storedServer => server;
  int? get storedPort => port;

  @override
  bool operator ==(Object other) =>
      other is WatchContext &&
      other.kind == kind &&
      other.server == server &&
      other.port == port &&
      other.room == room;

  @override
  int get hashCode => Object.hash(kind, server, port, room);
}

/// Synced-context key: server + port + room. Room name alone is not enough
/// because the same code can exist on different servers.
String syncedWatchContextKey({
  required String server,
  required int port,
  required String room,
}) => 'synced|${server.trim()}|$port|${room.trim()}';

/// Map a pre-v5 history row onto a context key.
///
/// Non-empty room → synced (even if server/port are missing).
/// Roomless → Local. Does not invent a room that was never stored.
String migrateHistoryContextKey({String? room, String? server, int? port}) {
  final trimmed = room?.trim() ?? '';
  if (trimmed.isEmpty) return kLocalWatchContextKey;
  return syncedWatchContextKey(
    server: server ?? '',
    port: port ?? 0,
    room: trimmed,
  );
}

/// Latest-per-room grouping key: Local is one bucket; each synced endpoint
/// is its own bucket.
String historyContextBucketKey(WatchContext context) => context.key;

/// History context for the current player session. Local writes the Local
/// row; synced writes this room's endpoint — never the other way around.
WatchContext watchContextForSession({
  required bool local,
  required String server,
  required int port,
  required String room,
}) {
  if (local) {
    return WatchContext.local(
      server: server.trim(),
      port: port,
      room: room.trim(),
    );
  }
  return WatchContext.synced(server: server, port: port, room: room);
}
