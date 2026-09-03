/// Short, low-emphasis lines shown late under the launch wordmark — one per
/// launch, chosen by [launchTip]. The first is the skip hint; the rest are
/// one-line feature nudges. Every line must be true of the shipping app and fit
/// on one row. To add one, append it here (the reveal picks up the bigger pool
/// automatically — nothing else to wire).
const List<String> kLaunchTips = <String>[
  'Click or press any key to skip.',
  'Drag a video anywhere to load it.',
  'Share your room code — a friend joins from one paste.',
  'No account needed — just a name and a code.',
  'Your spot is saved — pick up where you left off.',
  'Find themes and sounds in the gear, top-right.',
  'Press Tab to show or hide chat.',
  'Go fullscreen from the player bar — or double-click the video.',
  'MeowWatch keeps itself up to date.',
  'No name? Leave it blank — the dice picks you a cute one.',
  'Friend watching a link? One click loads it for you too.',
  'Paste a YouTube or Bilibili link — MeowWatch digs out the video.',
  'Want to watch alone? Turn on Local Player Mode in the lobby gear.',
  'If one public server is down, Start new room tries the others.',
];

/// The tip for [index], wrapping around the list so any seed is valid.
String launchTip(int index) => kLaunchTips[index % kLaunchTips.length];
