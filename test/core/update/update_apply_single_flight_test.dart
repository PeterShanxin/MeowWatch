import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/release_signature.dart';
import 'package:meowwatch/core/update/update_service.dart';

import 'apply_harness.dart';

/// `applyUpdate` yields to the event loop while verify+extract runs in the
/// background isolate (#197 P4), so the Install button and the window-close
/// path could start a second apply against the same temp dir — racing file
/// writes and launching duplicate updaters (#205 review). The service must be
/// single-flight: one apply per downloaded zip, with an observable
/// `installing` phase so the UI can disable its triggers.
void main() {
  test('applyUpdate enters the installing phase and launches one updater',
      () async {
    final h = await ApplyHarness.create(holdLauncher: true);
    addTearDown(h.dispose);

    final apply = h.service.applyUpdate(h.zipPath);
    expect(h.service.phase, UpdatePhase.installing);

    h.launchGate.complete();
    await apply;

    expect(h.launches, hasLength(1));
    expect(h.exits, [0]);
  });

  test('a second applyUpdate while one is in flight shares it — no second '
      'launch', () async {
    final h = await ApplyHarness.create(holdLauncher: true);
    addTearDown(h.dispose);

    final first = h.service.applyUpdate(h.zipPath);
    // Double-click on Install, or the window-close path firing during the
    // multi-second verify+extract.
    final second = h.service.applyUpdate(h.zipPath);

    h.launchGate.complete();
    await first;
    await second;

    expect(h.launches, hasLength(1));
    expect(h.exits, [0]);
  });

  test('checkUpdateForDialog is a no-op while installing', () async {
    final h = await ApplyHarness.create(holdLauncher: true);
    addTearDown(h.dispose);

    final apply = h.service.applyUpdate(h.zipPath);
    expect(h.service.phase, UpdatePhase.installing);

    await h.service.checkUpdateForDialog();
    expect(h.service.phase, UpdatePhase.installing);

    h.launchGate.complete();
    await apply;
  });

  test('a failed apply lands in error with a user-facing message and allows '
      'a retry', () async {
    final h = await ApplyHarness.create(corruptSignature: true);
    addTearDown(h.dispose);

    await expectLater(
      h.service.applyUpdate(h.zipPath),
      throwsA(isA<UpdateSignatureException>()),
    );
    expect(h.service.phase, UpdatePhase.error);
    expect(h.service.errorMessage, isNotEmpty);
    expect(h.launches, isEmpty);

    // The failure must clear the single-flight slot: a retry attempts the
    // pipeline again rather than returning the dead future.
    await expectLater(
      h.service.applyUpdate(h.zipPath),
      throwsA(isA<UpdateSignatureException>()),
    );
  });
}
