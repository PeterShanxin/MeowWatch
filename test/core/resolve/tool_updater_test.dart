import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/tool_updater.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory toolsDir;
  late List<List<String>> calls;

  setUp(() async {
    toolsDir = await Directory.systemTemp.createTemp('tool_updater_test');
    calls = [];
  });

  tearDown(() async {
    if (toolsDir.existsSync()) await toolsDir.delete(recursive: true);
  });

  String exePath() => p.join(toolsDir.path, 'yt-dlp.exe');

  /// Fake runner scripted per (basename, first arg) — records every call.
  Future<ProcessResult> Function(String, List<String>) runner({
    List<String> versions = const ['2026.07.04', '2026.08.01'],
    bool failUpdate = false,
    bool throwAll = false,
  }) {
    var versionCall = 0;
    return (exe, args) async {
      calls.add([p.basename(exe), ...args]);
      if (throwAll) throw const ProcessException('yt-dlp.exe', ['-U']);
      if (p.basename(exe) == 'deno.exe') {
        return ProcessResult(1, 0, '', '');
      }
      if (args.first == '--version') {
        final v = versions[versionCall.clamp(0, versions.length - 1)];
        versionCall++;
        return ProcessResult(1, 0, '$v\n', '');
      }
      // -U
      if (failUpdate) return ProcessResult(1, 1, '', 'update failed');
      return ProcessResult(1, 0, 'Updated yt-dlp\n', '');
    };
  }

  ToolUpdater updater({
    Future<ProcessResult> Function(String, List<String>)? run,
    DateTime Function()? now,
    void Function(String)? log,
  }) {
    return ToolUpdater(
      toolsDir: toolsDir,
      runner: run ?? runner(),
      now: now,
      log: log ?? (_) {},
    );
  }

  test('first check runs version probe, -U, version probe, writes stamp',
      () async {
    await updater().maybeUpdate(exePath());
    expect(calls, [
      ['yt-dlp.exe', '--version'],
      ['yt-dlp.exe', '-U'],
      ['yt-dlp.exe', '--version'],
    ]);
    expect(File(p.join(toolsDir.path, '.update-stamp')).existsSync(), isTrue);
  });

  test('fresh stamp skips the check entirely', () async {
    final u = updater();
    await u.maybeUpdate(exePath());
    calls.clear();
    await u.maybeUpdate(exePath());
    expect(calls, isEmpty);
  });

  test('stale stamp re-runs the check', () async {
    var current = DateTime(2026, 7, 20);
    final u = updater(now: () => current);
    await u.maybeUpdate(exePath());
    calls.clear();
    current = current.add(const Duration(hours: 25));
    await u.maybeUpdate(exePath());
    expect(calls, isNotEmpty);
  });

  test('offline (runner throws) is silent and still stamps', () async {
    await updater(run: runner(throwAll: true)).maybeUpdate(exePath());
    expect(File(p.join(toolsDir.path, '.update-stamp')).existsSync(), isTrue);
  });

  test('updateNow returns true when the version changed', () async {
    final changed = await updater().updateNow(exePath());
    expect(changed, isTrue);
  });

  test('updateNow returns false when already up to date', () async {
    final changed = await updater(
      run: runner(versions: ['2026.08.01', '2026.08.01']),
    ).updateNow(exePath());
    expect(changed, isFalse);
  });

  test('updateNow returns false when the runner throws', () async {
    final changed =
        await updater(run: runner(throwAll: true)).updateNow(exePath());
    expect(changed, isFalse);
  });

  test('updateNow ignores a fresh stamp', () async {
    // Four version probes: maybeUpdate sees 07.04 → 08.01, the later
    // updateNow sees 08.01 → 09.01 (a second real update landing).
    final u = updater(
      run: runner(
        versions: ['2026.07.04', '2026.08.01', '2026.08.01', '2026.09.01'],
      ),
    );
    await u.maybeUpdate(exePath());
    calls.clear();
    final changed = await u.updateNow(exePath());
    expect(changed, isTrue);
    expect(calls, isNotEmpty);
  });

  test('runs deno upgrade when deno.exe sits beside yt-dlp', () async {
    File(p.join(toolsDir.path, 'deno.exe')).writeAsBytesSync([0x4D, 0x5A]);
    await updater().maybeUpdate(exePath());
    expect(calls, anyElement(equals(['deno.exe', 'upgrade', '-q'])));
  });

  test('skips deno upgrade when deno.exe is absent', () async {
    await updater().maybeUpdate(exePath());
    expect(calls.where((c) => c.first == 'deno.exe'), isEmpty);
  });

  test('a deno upgrade failure never fails the yt-dlp update', () async {
    File(p.join(toolsDir.path, 'deno.exe')).writeAsBytesSync([0x4D, 0x5A]);
    await updater(run: (exe, args) async {
      calls.add([p.basename(exe), ...args]);
      if (p.basename(exe) == 'deno.exe') {
        throw const ProcessException('deno.exe', ['upgrade']);
      }
      return ProcessResult(1, 0, '2026.08.01\n', '');
    }).maybeUpdate(exePath());
    // yt-dlp calls all completed despite the deno throw.
    expect(calls.where((c) => c.first == 'yt-dlp.exe'), hasLength(3));
  });

  test('concurrent maybeUpdate calls share one in-flight run', () async {
    final gate = Completer<void>();
    final u = updater(run: (exe, args) async {
      calls.add([p.basename(exe), ...args]);
      await gate.future;
      return ProcessResult(1, 0, '2026.08.01\n', '');
    });
    final first = u.maybeUpdate(exePath());
    final second = u.maybeUpdate(exePath());
    gate.complete();
    await Future.wait([first, second]);
    expect(calls.where((c) => c.contains('-U')), hasLength(1));
  });

  test('a hung runner is abandoned after the timeout without throwing',
      () async {
    final u = ToolUpdater(
      toolsDir: toolsDir,
      runner: (exe, args) => Completer<ProcessResult>().future,
      timeout: const Duration(milliseconds: 20),
      log: (_) {},
    );
    await u.maybeUpdate(exePath()).timeout(const Duration(seconds: 5));
  });

  test('logs the version transition', () async {
    final lines = <String>[];
    await updater(log: lines.add).maybeUpdate(exePath());
    expect(
      lines,
      contains(contains('yt-dlp 2026.07.04 → 2026.08.01')),
    );
  });
}
