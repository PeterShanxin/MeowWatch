import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Environment variable that overrides the base directory for all persistent
/// app data (the Drift DB *and* the rotating logs).
///
/// Why this exists: `getApplicationSupportDirectory()` derives its path from the
/// executable's identity (`com.shanxin` / `meowwatch`), NOT from where the .exe
/// lives. So a released production copy and an in-development build on the same
/// machine resolve to the *same* store and share one `last_seen_version` — which
/// made the post-update "what's new" modal misfire as the version ping-ponged
/// between them. Point a dev/test build at its own dir with this variable to
/// keep production's DB, logs, and last-seen version untouched.
const String kDataDirEnvVar = 'MEOWWATCH_DATA_DIR';

/// The override [Directory] named by [kDataDirEnvVar] in [environment], or null
/// when unset/blank. Pure and total — no I/O — so the precedence rule is unit
/// testable without a platform path provider.
Directory? overrideDirFor(Map<String, String> environment) {
  final override = environment[kDataDirEnvVar]?.trim();
  if (override == null || override.isEmpty) return null;
  return Directory(override);
}

/// Resolve the base directory for persistent app data.
///
/// Honors [kDataDirEnvVar] (creating it if missing) so dev/test builds stay
/// isolated from a production copy; otherwise falls back to the platform
/// app-support directory. [environment] defaults to the process environment and
/// is injectable for tests.
Future<Directory> resolveAppSupportDir({
  Map<String, String>? environment,
}) async {
  final override = overrideDirFor(environment ?? Platform.environment);
  if (override != null) {
    await override.create(recursive: true);
    return override;
  }
  return getApplicationSupportDirectory();
}
