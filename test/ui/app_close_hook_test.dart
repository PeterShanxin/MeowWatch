import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/app_close_hook.dart';

void main() {
  tearDown(() => appCloseHook.value = null);

  test('runAppCloseHook is a no-op when no hook is set', () async {
    appCloseHook.value = null;
    await runAppCloseHook(); // must not throw
  });

  test('runAppCloseHook invokes the registered hook', () async {
    var ran = false;
    appCloseHook.value = () async {
      ran = true;
    };

    await runAppCloseHook();

    expect(ran, isTrue);
  });

  test('runAppCloseHook is bounded by its timeout when the hook hangs',
      () async {
    appCloseHook.value = () => Future<void>.delayed(const Duration(seconds: 10));

    final sw = Stopwatch()..start();
    await runAppCloseHook(timeout: const Duration(milliseconds: 50));
    sw.stop();

    // Returns promptly rather than waiting the full 10s — a wedged/half-open
    // socket must never trap the quit.
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('runAppCloseHook swallows a hook that throws', () async {
    appCloseHook.value = () async => throw StateError('boom');

    await runAppCloseHook(); // must not rethrow
  });

  test('appCloseHook notifies listeners on change (drives preventClose)',
      () async {
    var notified = 0;
    void listener() => notified++;
    appCloseHook.addListener(listener);

    appCloseHook.value = () async {};
    expect(notified, 1);
    appCloseHook.value = null;
    expect(notified, 2);

    appCloseHook.removeListener(listener);
  });
}
