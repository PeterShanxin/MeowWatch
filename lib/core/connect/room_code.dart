import 'dart:math';

/// Generates a friendly room code that reads like a little **magic sentence**,
/// e.g. `the-sleepy-otter-naps-and-the-brave-fox-dreams`.
///
/// ## Why a sentence
/// On a public Syncplay server the room name is the only thing that keeps a room
/// private: rooms are isolated and unlisted, and the wire `password` field is a
/// *server* password that public servers ignore. So privacy here comes from
/// making the room name unguessable. The whole generated string IS the room — to
/// join, a friend hands it to the server verbatim. We do NOT split it back out or
/// re-send any part as a server password; that's a separate axis (the Advanced
/// "Server password" field), and conflating the two would both mangle real room
/// names and misuse the server password.
///
/// Earlier builds bought that unguessability with a random gibberish suffix
/// (`cozy-fox-42-k3pn`). This generator instead spends the entropy on *real,
/// friendly words* so the code stays cute and easy to dictate aloud while still
/// being unguessable — the threat model is blocking accidental / guessed joins,
/// not resisting a determined brute-forcer.
///
/// ## Entropy
/// Two clauses, each an independent (adjective, animal, verb) draw, gives
/// `64 * 64 * 48 * 64 * 64 * 48 == 64^4 * 48^2 ≈ 3.9e10` distinct codes — far
/// beyond the ~2.3e4 of the old `adjective-animal-number` format and comfortably
/// past the ~2e10 of the `…-k3pn` scheme it replaces.
///
/// ## Backward compatibility
/// Falls out for free: an old room-only code (`cozy-fox-42`) or a folded
/// `…-k3pn` code is just some string, and any string is a valid room name. A
/// friend pasting one into "Enter code from friend" joins that exact room, so
/// existing saved profiles and already-shared codes keep working unchanged.

/// Friendly, easy-to-say adjectives. Drawn twice (one per clause).
const List<String> roomAdjectives = <String>[
  'cozy', 'sleepy', 'fuzzy', 'happy', 'silly', 'mellow', 'sunny', 'snug',
  'witty', 'jolly', 'breezy', 'plucky', 'dreamy', 'peppy', 'swift', 'gentle',
  'brave', 'calm', 'chirpy', 'chubby', 'classy', 'clever', 'comfy', 'dapper',
  'eager', 'fancy', 'fluffy', 'frisky', 'golden', 'jaunty', 'kindly', 'lively',
  'lucky', 'merry', 'nifty', 'nimble', 'perky', 'proud', 'quiet', 'quirky',
  'rosy', 'sandy', 'shiny', 'smiley', 'snowy', 'soft', 'spry', 'starry',
  'sturdy', 'sweet', 'tender', 'tidy', 'tiny', 'toasty', 'velvet', 'warm',
  'wavy', 'wise', 'zesty', 'amber', 'bouncy', 'bubbly', 'cuddly', 'dusky',
];

/// Friendly, easy-to-say animals. Drawn twice (one per clause).
const List<String> roomAnimals = <String>[
  'fox', 'cat', 'owl', 'panda', 'otter', 'koala', 'lynx', 'hare',
  'wolf', 'seal', 'crow', 'moth', 'newt', 'toad', 'wren', 'yak',
  'deer', 'bear', 'hawk', 'dove', 'swan', 'mole', 'mouse', 'finch',
  'robin', 'sparrow', 'badger', 'beaver', 'bison', 'camel', 'crab', 'duck',
  'eagle', 'ferret', 'gecko', 'goat', 'goose', 'heron', 'jay', 'lamb',
  'lark', 'llama', 'lemur', 'mink', 'parrot', 'pony', 'quail', 'rabbit',
  'raven', 'shrew', 'skunk', 'sloth', 'snail', 'stoat', 'stork', 'puffin',
  'tapir', 'tiger', 'turtle', 'vole', 'walrus', 'weasel', 'whale', 'zebra',
];

/// Gentle, intransitive verbs (3rd-person singular) so each clause reads as a
/// complete little thought with no dangling object. Drawn twice (one per clause).
const List<String> roomVerbs = <String>[
  'naps', 'dreams', 'purrs', 'yawns', 'snoozes', 'dozes', 'wanders', 'tiptoes',
  'giggles', 'wiggles', 'stretches', 'ponders', 'drifts', 'snuggles', 'blinks',
  'sighs', 'hums', 'twirls', 'hops', 'skips', 'sways', 'floats', 'glows',
  'dances', 'prances', 'frolics', 'ambles', 'saunters', 'dawdles', 'lingers',
  'rests', 'relaxes', 'unwinds', 'daydreams', 'wonders', 'wibbles', 'wobbles',
  'shimmers', 'sparkles', 'glimmers', 'tumbles', 'bounces', 'scampers',
  'scurries', 'waddles', 'shuffles', 'mooches', 'lounges',
];

/// The number of distinct codes this generator can produce. Each clause is an
/// independent (adjective, animal, verb) draw, and there are two clauses.
final int roomCodeCombinations = roomAdjectives.length *
    roomAnimals.length *
    roomVerbs.length *
    roomAdjectives.length *
    roomAnimals.length *
    roomVerbs.length;

/// Generates a friendly room code like
/// `the-sleepy-otter-naps-and-the-brave-fox-dreams`.
///
/// The two clauses are drawn independently, so they may occasionally share a
/// word (`the-sleepy-fox-naps-and-the-sleepy-owl-dreams`) — that still reads
/// fine and a full subject repeat is a ~1-in-4096 cosmetic edge, not worth a
/// redraw that would muddy the deterministic seeding below.
///
/// Pass a seeded [Random] in tests for deterministic output.
String generateRoomCode([Random? random]) {
  final r = random ?? Random();
  String clause() {
    final adjective = roomAdjectives[r.nextInt(roomAdjectives.length)];
    final animal = roomAnimals[r.nextInt(roomAnimals.length)];
    final verb = roomVerbs[r.nextInt(roomVerbs.length)];
    return 'the-$adjective-$animal-$verb';
  }

  return '${clause()}-and-${clause()}';
}
