import 'dart:math';

import 'room_code.dart';

/// A friendly join code, optionally carrying a room password folded into one
/// shareable string.
///
/// On a public Syncplay server the room name is the only thing that keeps a
/// room private: rooms are isolated and unlisted, and the wire `password` field
/// is a *server* password that public servers ignore. So privacy here comes
/// from making the room name unguessable — we append a short secret to the
/// readable room (`happy-cat-11` -> `happy-cat-11-k3pn`). Two friends who share
/// the full code land in the same private room; someone who only knows the
/// readable part lands in a different (public) room and never meets them.
///
/// Backward compatibility falls out for free: an old room-only code has no
/// secret, so it folds back to the bare room name and still meets anyone using
/// that same name.

/// Characters used for a generated passphrase. Excludes visually ambiguous
/// glyphs (0/o, 1/l/i) so the code stays easy to read and retype out loud.
const String _passphraseAlphabet = '23456789abcdefghjkmnpqrstuvwxyz';

/// Length of a generated passphrase. Four characters over a 30-symbol alphabet
/// is ~810k combinations — far more than enough to block accidental or guessed
/// joins, which is the whole threat model here (not resisting a determined
/// brute-forcer). Pass a seeded [Random] in tests for deterministic output.
const int _passphraseLength = 4;

/// Generates a short, readable room secret like `k3pn`.
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

/// A join code split into its room and (optional) password parts.
typedef ParsedJoinCode = ({String room, String? password});

/// Splits a pasted join code into room + password.
///
/// Recognises our generated `adjective-animal-NN` room shape and treats
/// whatever follows it as the password; anything else (a plain word, a custom
/// room) is returned whole as the room with no password. That keeps old
/// room-only codes and custom rooms working unchanged, and makes
/// [buildJoinCode] of the result reproduce the original string.
ParsedJoinCode parseJoinCode(String code) {
  final trimmed = code.trim();
  final match = _generatedWithPassword.firstMatch(trimmed);
  if (match != null) {
    return (room: match.group(1)!, password: match.group(2));
  }
  return (room: trimmed, password: null);
}

/// A generated room (`adjective-animal-NN`) followed by a `-password` tail.
final RegExp _generatedWithPassword =
    RegExp('^(${roomCodePattern.pattern})-(.+)\$');
