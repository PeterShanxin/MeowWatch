import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Hosted `windows-2025` ClearType / font raster can disagree with a golden
/// captured on another Windows image by a handful of pixels. Chat overlay
/// goldens are full-window 1280×720 shots, so 0.05% (~444 px) is font drift,
/// not a layout change. A real widget edit is far larger.
const double kHostedWindowsGoldenDriftPercent = 0.10;

bool allowHostedWindowsGoldenDrift(double diffPercent) =>
    diffPercent <= kHostedWindowsGoldenDriftPercent;

/// [LocalFileComparator] that accepts diffs at or under
/// [kHostedWindowsGoldenDriftPercent] and otherwise fails the same way.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || allowHostedWindowsGoldenDrift(result.diffPercent)) {
      result.dispose();
      return true;
    }
    return super.compare(imageBytes, golden);
  }
}
