/// Pure formatting for otherwise-uncaught error lines in the diagnostic log
/// (#156).
///
/// Before #156 nothing installed `FlutterError.onError` or
/// `PlatformDispatcher.instance.onError`, so a widget-build crash or an
/// async error that escaped a callback went to stderr only — invisible in the
/// Release build users actually run, and absent from any exported log. The
/// run-level log promised in #140 ("a single exported log can diagnose any
/// reported problem") therefore had a hole exactly where it mattered most.
///
/// [errorLogLine] builds the line both global handlers write. It carries no
/// `trace:` / raw-traffic / `apply=false` marker, so it is kept at
/// [LogLevel.neat] — an uncaught error is always a key event. The message (and
/// any stack) is run through [redactUrls] so a credential embedded in a source
/// URL inside the error text never lands on disk.
library;

import 'log_redact.dart';

/// One diagnostic line for an uncaught [error] of the given [kind]
/// (`flutter` for framework errors, `uncaught` for async/platform errors).
///
/// When a [stack] is supplied and non-blank it is appended on following lines
/// so the trace travels with the message; an empty or null stack yields just
/// the single summary line. Both halves are URL-redacted.
String errorLogLine(String kind, Object error, [StackTrace? stack]) {
  final head = 'error: $kind: ${redactUrls(error.toString())}';
  if (stack == null) return head;
  final trace = stack.toString().trim();
  if (trace.isEmpty) return head;
  return '$head\n${redactUrls(trace)}';
}
