import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/installed_versions.dart';
import 'package:meowwatch/core/resolve/tool_provisioner.dart';
import 'package:meowwatch/core/resolve/tool_updater.dart';

void main() {
  late Directory toolsDir;
  late List<String> installed;
  late List<String> logs;

  setUp(() async {
    toolsDir = await Directory.systemTemp.createTemp('tool_updater_test');
    installed = [];
    logs = [];
  });

  tearDown(() async {
    if (toolsDir.existsSync()) await toolsDir.delete(recursive: true);
  });

  /// Pretend the tools dir already holds [ytDlp] / [deno].
  void recordInstalled({String? ytDlp, String? deno}) {
    final versions = InstalledVersions(toolsDir);
    if (ytDlp != null) versions.record(InstalledVersions.ytDlp, ytDlp);
    if (deno != null) versions.record(InstalledVersions.deno, deno);
  }

  ToolUpdater updater({
    Future<void> Function()? installYtDlp,
    Future<void> Function()? installDeno,
    bool denoPresent = false,
  }) {
    if (denoPresent) {
      File('${toolsDir.path}/deno.exe').writeAsBytesSync([0x4D, 0x5A]);
    }
    return ToolUpdater(
      toolsDir: toolsDir,
      installYtDlp: installYtDlp ??
          () async {
            installed.add('ytdlp');
            recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion);
          },
      installDeno: installDeno ??
          () async {
            installed.add('deno');
            recordInstalled(deno: ToolProvisioner.denoVersion);
          },
      log: logs.add,
    );
  }

  group('drift detection', () {
    test('does nothing when the installed version matches the pin', () async {
      recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion);
      await updater().maybeUpdate();
      expect(installed, isEmpty);
    });

    test('re-provisions when an app update advanced the pin', () async {
      recordInstalled(ytDlp: '2020.01.01');
      await updater().maybeUpdate();
      expect(installed, contains('ytdlp'));
      expect(
        logs,
        contains(contains('yt-dlp 2020.01.01 → ${ToolProvisioner.ytDlpVersion}')),
      );
    });

    test('re-provisions when nothing is recorded', () async {
      // No record: the copy on disk came from somewhere this app cannot vouch
      // for (an older build that let yt-dlp update itself), so re-establish
      // the verified baseline rather than trusting it.
      await updater().maybeUpdate();
      expect(installed, contains('ytdlp'));
    });

    test('a second check after a successful install is a no-op', () async {
      recordInstalled(ytDlp: '2020.01.01');
      final u = updater();
      await u.maybeUpdate();
      installed.clear();
      await u.maybeUpdate();
      expect(installed, isEmpty);
    });
  });

  group('deno', () {
    test('re-provisions a drifted deno when it is installed', () async {
      recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion, deno: 'v1.0.0');
      await updater(denoPresent: true).maybeUpdate();
      expect(installed, contains('deno'));
    });

    test('leaves deno alone when it was never installed', () async {
      recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion);
      await updater().maybeUpdate();
      expect(installed, isEmpty);
    });

    test('a failing deno install never breaks the yt-dlp update', () async {
      recordInstalled(ytDlp: '2020.01.01', deno: 'v1.0.0');
      await updater(
        denoPresent: true,
        installDeno: () async => throw const SocketException('down'),
      ).maybeUpdate();
      expect(installed, contains('ytdlp'));
    });
  });

  group('failure contract', () {
    test('a failed install never throws out of maybeUpdate', () async {
      recordInstalled(ytDlp: '2020.01.01');
      await updater(
        installYtDlp: () async => throw const SocketException('offline'),
      ).maybeUpdate();
      expect(logs, contains(contains('update failed')));
    });

    test('a failed install leaves the pin drifted so it retries later',
        () async {
      recordInstalled(ytDlp: '2020.01.01');
      final u = updater(
        installYtDlp: () async => throw const SocketException('offline'),
      );
      await u.maybeUpdate();
      installed.clear();
      await ToolUpdater(
        toolsDir: toolsDir,
        installYtDlp: () async => installed.add('ytdlp'),
        installDeno: () async {},
        log: logs.add,
      ).maybeUpdate();
      expect(installed, contains('ytdlp'));
    });

    test('concurrent calls share one install', () async {
      recordInstalled(ytDlp: '2020.01.01');
      final gate = Completer<void>();
      final u = updater(installYtDlp: () async {
        installed.add('ytdlp');
        await gate.future;
        recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion);
      });
      final first = u.maybeUpdate();
      final second = u.maybeUpdate();
      gate.complete();
      await Future.wait([first, second]);
      expect(installed, hasLength(1));
    });
  });

  group('updateNow', () {
    test('returns false without doing work when already on the pin', () async {
      recordInstalled(ytDlp: ToolProvisioner.ytDlpVersion);
      final changed = await updater().updateNow();
      expect(changed, isFalse);
      expect(installed, isEmpty,
          reason: 'a failed resolve must surface its error immediately when '
              'no newer pinned resolver exists to try');
    });

    test('returns true after installing a newer pin', () async {
      recordInstalled(ytDlp: '2020.01.01');
      final changed = await updater().updateNow();
      expect(changed, isTrue);
      expect(installed, contains('ytdlp'));
    });

    test('returns false when the install fails', () async {
      recordInstalled(ytDlp: '2020.01.01');
      final changed = await updater(
        installYtDlp: () async => throw const SocketException('offline'),
      ).updateNow();
      expect(changed, isFalse);
    });
  });
}
