/// Pure builder for the run's startup environment header (#156).
///
/// Before #156 the run header logged only the app version, so
/// environment-specific reports ("only on Win10", "the overlay is off-screen",
/// date/RTL glitches) couldn't be confirmed from an exported log. This stamps
/// the run once with the facts support needs: OS, window geometry/DPI, locale,
/// where the log file itself lives, and the settings that shape the UI.
///
/// All lines are neat-kept (no `trace:`/raw/`apply=false` marker) — a one-shot,
/// high-value header. Caller gathers the values (window manager, platform
/// dispatcher, settings) and passes them already stringified so this stays pure
/// and unit-testable.
library;

/// Build the startup header lines, newest-run first. The leading line is the
/// versioned app-start marker (folding in the line `main()` used to log on its
/// own); the `env:` lines carry the rest.
List<String> startupEnvLines({
  required String version,
  required String os,
  required String logPath,
  required String window,
  required double dpr,
  required String locale,
  required String theme,
  required String cardSize,
  required String logLevel,
}) {
  return <String>[
    'life: app start (version=$version)',
    'env: os=$os',
    'env: window=$window dpr=${dpr.toStringAsFixed(2)} locale=$locale',
    'env: logfile=$logPath',
    'env: settings theme=$theme cardSize=$cardSize logLevel=$logLevel',
  ];
}
