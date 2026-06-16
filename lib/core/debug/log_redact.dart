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
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Random per-run salt for [roomLogLabel]. A generated room code is drawn from
/// small published word lists (~7e8 combinations), so a *deterministic* digest
/// of it could be reversed offline by hashing that whole space. Salting with a
/// secret that only lives in this process (never logged, regenerated each run)
/// makes the label opaque while still correlating within one run. Lazy so it
/// isn't computed in runs that never log a room.
final String _roomLabelSalt = _newRoomLabelSalt();

String _newRoomLabelSalt() {
  final rnd = Random.secure();
  return List<int>.generate(16, (_) => rnd.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

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
/// exportable log (#146 review). We log an opaque per-run label instead:
/// `room#<8 hex>` of a salted digest. The salt ([_roomLabelSalt]) is random per
/// process and never logged, so the low-entropy room code can't be recovered by
/// hashing the word-list space offline; the same room still maps to one label
/// within a run for correlation. Empty → `(none)`.
String roomLogLabel(String room) {
  if (room.isEmpty) return '(none)';
  final digest = sha256
      .convert(utf8.encode('$_roomLabelSalt:$room'))
      .toString()
      .substring(0, 8);
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
