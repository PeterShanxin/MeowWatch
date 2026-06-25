/// One short, low-emphasis line shown late under the launch wordmark. The first
/// is always the skip hint; later tips are an extensible list — add one line
/// each (e.g. "Drag a video anywhere to load it.", "Press Tab to open chat.").
/// One tip shows per launch.
const List<String> kLaunchTips = <String>[
  'Click or press any key to skip.',
  'Drag a video anywhere to load it.',
  'Press Tab to open chat.',
  'Share your room code — your friend joins from one paste.',
];

/// The tip for [index], wrapping around the list so any seed is valid.
String launchTip(int index) => kLaunchTips[index % kLaunchTips.length];
