import 'package:flutter/foundation.dart';

/// Process-wide "an update was found this session" flag. Set by the connect
/// screen's once-per-session silent check ([VersionBadge]) and read by any
/// surface that wants to show an update dot without running its own check —
/// e.g. the in-room gear's version footer. Mirrors the badge's dot so both
/// surfaces agree. Reset in tests via VersionBadge.resetForTest().
final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);
