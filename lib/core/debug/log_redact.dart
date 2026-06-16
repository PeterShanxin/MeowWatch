/// Pure redaction for diagnostic log lines (#140).
///
/// Freeform text we log — most importantly raw mpv error strings — can embed a
/// source URL, and a streamed source's URL can carry a credential in three
/// places: the query string (`?token=…`), the fragment (`#token=…`), or the
/// userinfo (`user:token@host`). We must never write any of them to disk.
/// [redactUrls] strips all three from every `http(s)` URL it finds, leaving the
/// scheme/host/port/path intact (enough to diagnose, nothing secret). Non-URL
/// text is returned unchanged. Mirrors the rule the Syncplay log redactor
/// (`redactUrlSecrets`) already applies. Pure — unit-tested without any I/O.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Matches an `http(s)` URL run up to the next whitespace. [redactUrls] then
/// strips the query/fragment (from the first `?`/`#`) and any `user:pass@`
/// userinfo from each match.
final RegExp _urlRun = RegExp(r'https?://\S+', caseSensitive: false);

/// Strip the query string, fragment, and userinfo from every `http(s)` URL in
/// [text].
///
/// `https://user:token@cdn.example/clip.mp4?exp=123#x` becomes
/// `https://cdn.example/clip.mp4`. Trailing punctuation that isn't part of the
/// query (e.g. a sentence-ending `.` or a closing paren) is preserved because we
/// only ever trim from the first `?`/`#` onward.
/// A safe label for a room name in the diagnostic log.
///
/// For a generated private room the room name *is* the unguessable access code
/// (no separate password on the public server), so writing it verbatim — even
/// on a neat-kept lifecycle line — would leak the live room credential into an
/// exportable log (#146 review). We log a short, stable, non-reversible hash
/// instead: `room#<8 hex>` lets the same room be correlated across a run's lines
/// without exposing how to join it. Empty → `(none)`.
String roomLogLabel(String room) {
  if (room.isEmpty) return '(none)';
  final digest = sha256.convert(utf8.encode(room)).toString().substring(0, 8);
  return 'room#$digest';
}

String redactUrls(String text) {
  return text.replaceAllMapped(_urlRun, (match) {
    var url = match.group(0)!;
    // Drop query + fragment first (signed tokens commonly live here).
    final cut = url.indexOf(RegExp(r'[?#]'));
    if (cut >= 0) url = url.substring(0, cut);
    // Then drop any `user:token@` userinfo between the scheme and the host — a
    // credential can ride there too (review #146).
    final schemeEnd = url.indexOf('://');
    if (schemeEnd >= 0) {
      final authStart = schemeEnd + 3;
      final slash = url.indexOf('/', authStart);
      final authEnd = slash >= 0 ? slash : url.length;
      final at = url.lastIndexOf('@', authEnd - 1);
      if (at >= authStart) {
        url = url.substring(0, authStart) + url.substring(at + 1);
      }
    }
    return url;
  });
}
