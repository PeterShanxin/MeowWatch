import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Max fraction of pixels (0–1) that may differ on hosted `windows-2025`.
///
/// Goldens were captured on the maintainer Windows box. Hosted
/// `windows-2025` ClearType / font hinting is not pixel-identical.
/// Run 33264970792 (`Analyze & Test (hosted)`):
/// - `chat_overlay_expanded.png`: 0.05%, 444px
/// - `chat_overlay_empty.png`: 0.00%, 15px
/// Both are well under 0.1% of a 1280×720 frame (~922px). A real
/// layout or theme change is far larger. Do not raise this to "skip".
const double kHostedWindowsGoldenMaxDiffFraction = 0.001;

/// Whether [diffPercent] from [ComparisonResult] is an allowed
/// hosted-Windows rasterization miss (exact match always passes).
bool hostedWindowsGoldenPassed({
  required bool exactMatch,
  required double diffPercent,
}) {
  return exactMatch || diffPercent <= kHostedWindowsGoldenMaxDiffFraction;
}

/// [LocalFileComparator] that accepts the tiny hosted-Windows delta.
///
/// Same shape as Flutter's documented tolerant comparator. Still fails
/// (and writes the usual `failures/` diffs) when the fraction is over
/// [kHostedWindowsGoldenMaxDiffFraction].
class HostedWindowsGoldenComparator extends LocalFileComparator {
  HostedWindowsGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (hostedWindowsGoldenPassed(
      exactMatch: result.passed,
      diffPercent: result.diffPercent,
    )) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
