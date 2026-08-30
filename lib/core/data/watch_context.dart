import 'package:flutter/foundation.dart';

/// Sentinel identity for a legacy roomless Local history row.
const String kLocalWatchContextKey = 'local';

/// Every code point Dart's [String.trim] strips. SQLite's one-argument TRIM
/// only strips ASCII spaces, so migrations and queries use this as the second
/// argument when deriving the same stable room key as Dart.
final String kDartTrimWhitespace = String.fromCharCodes(const <int>[
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
  0xFEFF,
]);

/// Kind of watch context a history row belongs to.
enum WatchContextKind { local, synced }

/// Where a watch happened: roomless Local, or a real room endpoint whose
/// current session may be Local or synced.
///
/// Progress identity is `(media, local)` only for legacy roomless playback, or
/// `(media, server, port, room)` whenever a real room exists. Effective Local
/// mode and username are metadata, never identity.
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

  /// Unique context key stored on the history row. A real room always wins over
  /// effective mode, so toggling Local in-player keeps writing the same row.
  String get key {
    final roomKey = room?.trim() ?? '';
    if (roomKey.isNotEmpty) {
      return syncedWatchContextKey(
        server: server ?? '',
        port: port ?? 0,
        room: roomKey,
      );
    }
    return isLocal
        ? kLocalWatchContextKey
        : syncedWatchContextKey(
            server: server ?? '',
            port: port ?? 0,
            room: roomKey,
          );
  }

  /// Session identity stored as metadata and used by [key] whenever roomful.
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

/// Latest-per-room grouping key: roomless Local is one legacy bucket; every
/// real endpoint is its own bucket regardless of effective mode.
String historyContextBucketKey(WatchContext context) => context.key;

/// History context for the current player session. [local] preserves the
/// effective mode on the object, while [WatchContext.key] remains the same room
/// endpoint through an in-player mode switch.
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
