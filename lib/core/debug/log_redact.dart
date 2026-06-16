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
