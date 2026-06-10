import 'dart:math';

/// A friendly join code: a readable room name with a short random secret folded
/// onto the end (`happy-cat-11` -> `happy-cat-11-k3pn`).
///
/// On a public Syncplay server the room name is the only thing that keeps a room
/// private: rooms are isolated and unlisted, and the wire `password` field is a
/// *server* password that public servers ignore. So privacy here comes from
/// making the room name unguessable. Two friends who share the full code land in
/// the same private room; someone who only knows the readable part lands in a
/// different (public) room and never meets them.
///
/// The whole code is the room: to join, we hand it to the server verbatim. We do
/// NOT split it back out and re-send the secret as a server password — that's a
/// separate axis (the Advanced "Room password" field), and conflating the two
/// would both leak the secret as a server password and mangle real room names.
///
/// Backward compatibility falls out for free: an old room-only code has no
/// secret, so it is just the bare room name and still meets anyone using it.

/// Characters used for a generated passphrase. Excludes visually ambiguous
/// glyphs (0/o, 1/l/i) so the code stays easy to read and retype out loud.
const String _passphraseAlphabet = '23456789abcdefghjkmnpqrstuvwxyz';

/// Length of a generated passphrase. Four characters over a 30-symbol alphabet
/// is ~810k combinations — far more than enough to block accidental or guessed
/// joins, which is the whole threat model here (not resisting a determined
/// brute-forcer).
const int _passphraseLength = 4;

/// Generates a short, readable room secret like `k3pn`.
///
/// Pass a seeded [Random] in tests for deterministic output.
String generatePassphrase([Random? random]) {
  final r = random ?? Random();
  return List<String>.generate(
    _passphraseLength,
    (_) => _passphraseAlphabet[r.nextInt(_passphraseAlphabet.length)],
  ).join();
}

/// Builds the shareable join code for [room], folding [password] in when one is
/// present. With no password the code is just the room — so old room-only codes
/// are produced (and read) unchanged.
String buildJoinCode(String room, [String? password]) =>
    (password == null || password.isEmpty) ? room : '$room-$password';
