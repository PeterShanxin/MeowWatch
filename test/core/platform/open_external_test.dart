// test/core/platform/open_external_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/platform/open_external.dart';

void main() {
  // The launcher is injected in tests so the suite never spawns a real browser
  // tab (the real path runs `cmd /c start`, which on a dev box opens the URL).
  tearDown(() => debugUrlLauncherOverride = null);

  test('openExternalUrl routes the url through the launcher seam', () async {
    String? launched;
    debugUrlLauncherOverride = (url) async => launched = url;
    await openExternalUrl('https://example.test/x');
    expect(launched, 'https://example.test/x');
  });

  test('openExternalUrl swallows launcher failures and never throws', () async {
    debugUrlLauncherOverride = (_) async => throw StateError('boom');
    await expectLater(
      openExternalUrl('https://example.test/x'),
      completes,
    );
  });
}
