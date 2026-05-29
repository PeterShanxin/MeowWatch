/// Result of comparing the locally loaded file to a peer's announced file.
enum FileMatch {
  /// Not enough info yet (one side hasn't announced a file).
  unknown,

  /// The files look like the same media.
  match,

  /// The files clearly differ — warn the watchers.
  mismatch,
}

/// Decide whether the local file and a peer's file are the same media.
///
/// Byte size is the strongest signal: the same file is the same number of
/// bytes, regardless of filename. So when both sizes are known we trust them
/// outright. When size is unavailable we fall back to a normalized filename
/// comparison. With neither comparable, the result is [FileMatch.unknown] (no
/// warning — better silent than crying wolf).
FileMatch compareFiles({
  String? localName,
  int? localSize,
  String? peerName,
  int? peerSize,
}) {
  final haveLocal = (localName != null && localName.isNotEmpty) ||
      (localSize != null && localSize > 0);
  final havePeer = (peerName != null && peerName.isNotEmpty) ||
      (peerSize != null && peerSize > 0);
  if (!haveLocal || !havePeer) return FileMatch.unknown;

  // Strongest: byte size when both sides report it.
  if (localSize != null && localSize > 0 && peerSize != null && peerSize > 0) {
    return localSize == peerSize ? FileMatch.match : FileMatch.mismatch;
  }

  // Fallback: normalized filename.
  final ln = _normalize(localName);
  final pn = _normalize(peerName);
  if (ln.isNotEmpty && pn.isNotEmpty) {
    return ln == pn ? FileMatch.match : FileMatch.mismatch;
  }

  return FileMatch.unknown;
}

String _normalize(String? name) =>
    (name ?? '').trim().toLowerCase();
