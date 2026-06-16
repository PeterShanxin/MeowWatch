/// Pure redaction for diagnostic log lines (#140).
///
/// Freeform text we log — most importantly raw mpv error strings — can embed a
/// source URL, and a streamed source's URL may carry a signed token in its query
/// string. We must never write that token to disk. [redactUrls] strips the query
/// and fragment from every `http(s)` URL it finds, leaving the scheme/host/path
/// intact (enough to diagnose, nothing secret). Non-URL text is returned
/// unchanged. Kept pure so it can be unit-tested without any I/O.
library;

/// Matches an `http(s)` URL run up to the next whitespace. The query/fragment
/// (everything from the first `?` or `#`) is cut off by [redactUrls].
final RegExp _urlRun = RegExp(r'https?://\S+', caseSensitive: false);

/// Strip the query string and fragment from every `http(s)` URL in [text].
///
/// `https://cdn.example/clip.mp4?token=secret&exp=123` becomes
/// `https://cdn.example/clip.mp4`. Trailing punctuation that isn't part of the
/// query (e.g. a sentence-ending `.` or a closing paren) is preserved because we
/// only ever trim from the first `?`/`#` onward.
String redactUrls(String text) {
  return text.replaceAllMapped(_urlRun, (match) {
    final url = match.group(0)!;
    final cut = url.indexOf(RegExp(r'[?#]'));
    return cut >= 0 ? url.substring(0, cut) : url;
  });
}
