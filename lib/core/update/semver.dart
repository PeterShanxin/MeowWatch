// lib/core/update/semver.dart
//
// Pure, dependency-free semver comparison shared by the updater (is a remote
// release newer than ours?) and the post-update catch-up modal (which versions
// are newer than the last one the user saw?). Total — never throws; unparseable
// segments degrade to 0 rather than failing.

/// True when [a] is a strictly newer version than [b].
///
/// Compares the three numeric MAJOR.MINOR.PATCH slots first; on a tie, a build
/// with no pre-release tag (e.g. `1.2.0`) outranks one that has a tag
/// (`1.2.0-alpha`), and two tags compare lexically. A leading `v` is ignored.
bool isVersionNewer(String a, String b) {
  final aP = _parseSemver(a);
  final bP = _parseSemver(b);

  for (var i = 0; i < 3; i++) {
    if (aP.$1[i] > bP.$1[i]) return true;
    if (aP.$1[i] < bP.$1[i]) return false;
  }

  // Numeric parts equal — compare pre-release: no pre-release > any pre-release.
  if (aP.$2 == null && bP.$2 != null) return true;
  if (aP.$2 != null && bP.$2 == null) return false;
  if (aP.$2 != null && bP.$2 != null) {
    return aP.$2!.compareTo(bP.$2!) > 0;
  }
  return false; // Exactly equal.
}

/// Parse `"0.1.0-alpha"` → `([0, 1, 0], "alpha")`. Missing slots pad with 0.
(List<int>, String?) _parseSemver(String v) {
  final s = v.startsWith('v') ? v.substring(1) : v;
  final dashIdx = s.indexOf('-');
  final numPart = dashIdx >= 0 ? s.substring(0, dashIdx) : s;
  final prePart = dashIdx >= 0 ? s.substring(dashIdx + 1) : null;
  final nums = numPart.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (nums.length < 3) {
    nums.add(0);
  }
  return (nums, prePart);
}
