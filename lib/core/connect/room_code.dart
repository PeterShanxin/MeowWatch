import 'dart:math';

const List<String> _adjectives = <String>[
  'cozy', 'sleepy', 'fuzzy', 'happy', 'silly', 'mellow', 'sunny', 'snug',
  'witty', 'jolly', 'breezy', 'plucky', 'dreamy', 'peppy', 'swift', 'gentle',
];

const List<String> _animals = <String>[
  'fox', 'cat', 'owl', 'panda', 'otter', 'koala', 'lynx', 'hare',
  'wolf', 'seal', 'crow', 'moth', 'newt', 'toad', 'wren', 'yak',
];

/// The shape of a generated room code: `adjective-animal-NN` (two-digit number).
/// Shared with the join-code parser so it can tell a generated room apart from a
/// trailing password. Not anchored — callers add `^`/`$` as needed.
final RegExp roomCodePattern = RegExp(r'[a-z]+-[a-z]+-\d{2}');

/// Generates a friendly room code like `cozy-fox-42`.
///
/// Pass a seeded [Random] in tests for deterministic output.
String generateRoomCode([Random? random]) {
  final r = random ?? Random();
  final adjective = _adjectives[r.nextInt(_adjectives.length)];
  final animal = _animals[r.nextInt(_animals.length)];
  final number = r.nextInt(90) + 10; // 10..99
  return '$adjective-$animal-$number';
}
