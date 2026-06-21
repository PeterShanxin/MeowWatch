// test/core/platform/open_external_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/platform/open_external.dart';

void main() {
  // Best-effort by contract: on a non-Windows CI runner the `cmd` spawn fails
  // and is swallowed, so the call must complete without throwing on any host.
  test('openExternalUrl never throws', () async {
    await expectLater(
      openExternalUrl('https://example.test/x'),
      completes,
    );
  });
}
