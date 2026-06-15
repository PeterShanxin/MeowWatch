import 'package:flutter/foundation.dart';

import '../sync/syncplay_constants.dart';

/// Turns a room + its connection settings into a single, copy-pasteable
/// **share code**, and parses one back. This is what makes a magic sentence
/// *self-contained* (#110): when the host is on a non-default server, the code
/// carries the server address so a friend joins from one paste.
///
/// ## Shape
/// On the default public server the code stays the bare magic sentence, so the
/// common case is unchanged and short:
///
///   `sleepy-otter-counts-cozy-stars`
///
/// When the server or port differ from the defaults, the endpoint is appended
/// URL-style, and the port only when it isn't the default:
///
///   `sleepy-otter-counts-cozy-stars@cozy.example.net`        (custom host)
///   `sleepy-otter-counts-cozy-stars@cozy.example.net:9000`   (custom host+port)
///   `sleepy-otter-counts-cozy-stars@syncplay.pl:9000`        (custom port only)
///
/// ## No password, ever
/// The Advanced *server* password is deliberately NOT encoded. A cipher would
/// be a fake lock: the app must decode the code to use it, so the key has to
/// ship inside the (open-source) binary — any onlooker's copy could decode it
/// too. There is no real encryption possible for a paste-anywhere code, so the
/// only secret stays out. Server + port aren't secret, so they ride along; a
/// self-hosted server password is typed once into Advanced by the joiner.
///
/// ## Backward compatibility
/// Any string with no `@` is treated as a plain room name. Old room-only codes
/// (`happy-cat-11`), folded `happy-cat-11-k3pn` codes, and every magic sentence
/// fall here and join verbatim against the default (or Advanced-overridden)
/// server — exactly as before this feature existed.

/// Shown when a structured code (`room@…`) is present but malformed, so the
/// joiner gets clear feedback instead of a confusing failed join into a garbage
/// room name.
const String malformedShareCodeMessage =
    'That code looks off — ask your friend to copy and paste it again.';

/// The result of [parseShareCode]: the bare [room] to join plus any [server] /
/// [port] the code carried. [server]/[port] are null when the code didn't
/// specify them (the caller then falls back to its own Advanced fields). When
/// [error] is non-null the code was structured but malformed and must NOT be
/// used to join.
@immutable
class ParsedShareCode {
  const ParsedShareCode({
    required this.room,
    this.server,
    this.port,
    this.error,
  });

  final String room;
  final String? server;
  final int? port;
  final String? error;

  bool get isValid => error == null;

  @override
  bool operator ==(Object other) =>
      other is ParsedShareCode &&
      other.room == room &&
      other.server == server &&
      other.port == port &&
      other.error == error;

  @override
  int get hashCode => Object.hash(room, server, port, error);
}

/// Builds the shareable code for [room] given the [server] and [port] it's
/// hosted on. Returns the bare [room] when both are the defaults; otherwise
/// appends `@host` (and `:port` only when the port is non-default).
String encodeShareCode({
  required String room,
  required String server,
  required int port,
}) {
  final isDefaultServer = server == SyncplayConstants.defaultServer;
  final isDefaultPort = port == SyncplayConstants.defaultPort;
  if (isDefaultServer && isDefaultPort) return room;
  final portPart = isDefaultPort ? '' : ':$port';
  return '$room@$server$portPart';
}

/// Parses a pasted [raw] code into a room + optional server/port. A string with
/// no `@` is a plain room name (back-compat). A `room@host[:port]` code yields
/// the room and endpoint; anything structured-but-broken returns an [error]
/// ([malformedShareCodeMessage]) so the caller can warn instead of joining.
ParsedShareCode parseShareCode(String raw) {
  final trimmed = raw.trim();
  final at = trimmed.indexOf('@');

  // No endpoint attached: the whole thing is the room (magic sentence,
  // happy-cat-11, …). This is the backward-compatible path.
  if (at < 0) return ParsedShareCode(room: trimmed);

  final room = trimmed.substring(0, at);
  final endpoint = trimmed.substring(at + 1);
  // Empty room, empty endpoint, or a second `@` is not a code we produce.
  if (room.isEmpty || endpoint.isEmpty || endpoint.contains('@')) {
    return ParsedShareCode(room: trimmed, error: malformedShareCodeMessage);
  }

  var host = endpoint;
  int? port;
  final colon = endpoint.indexOf(':');
  if (colon >= 0) {
    host = endpoint.substring(0, colon);
    final portStr = endpoint.substring(colon + 1);
    final parsed = int.tryParse(portStr);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      return ParsedShareCode(room: trimmed, error: malformedShareCodeMessage);
    }
    port = parsed;
  }
  // A host can't be empty or contain whitespace or a stray colon.
  if (host.isEmpty || host.contains(' ') || host.contains(':')) {
    return ParsedShareCode(room: trimmed, error: malformedShareCodeMessage);
  }

  return ParsedShareCode(room: room, server: host, port: port);
}
