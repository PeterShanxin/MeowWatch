import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/debug/debug_log.dart';
import 'package:meowwatch/core/debug/log_level.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('meow_log_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes timestamped lines that survive close', () async {
    final file = File('${dir.path}${Platform.pathSeparator}a.log');
    final log = DebugLog(file)..start();
    log('>> hello');
    log('<< world');
    await log.close();

    final text = file.readAsStringSync();
    expect(text, contains('>> hello'));
    expect(text, contains('<< world'));
    // ISO-8601 timestamp prefix on each line.
    expect(RegExp(r'\d{4}-\d{2}-\d{2}T').hasMatch(text), isTrue);
  });

  test('start truncates a previous run', () async {
    final file = File('${dir.path}${Platform.pathSeparator}b.log')
      ..writeAsStringSync('STALE CONTENT FROM LAST RUN');
    final log = DebugLog(file)..start();
    log('fresh');
    await log.close();

    final text = file.readAsStringSync();
    expect(text, isNot(contains('STALE CONTENT')));
    expect(text, contains('fresh'));
  });

  test('logging before start is a silent no-op', () {
    final file = File('${dir.path}${Platform.pathSeparator}c.log');
    // Never started — must not throw, must not create content.
    expect(() => DebugLog(file)('orphan line'), returnsNormally);
    expect(file.existsSync(), isFalse);
  });

  List<File> logsIn(Directory d) =>
      d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  group('isVerboseOnly', () {
    test('flags raw protocol traffic and no-op follows', () {
      expect(isVerboseOnly('<< {"State": {}}'), isTrue);
      expect(isVerboseOnly('>> {"State": {}}'), isTrue);
      expect(
        isVerboseOnly('FOLLOW global(...) local(...) => apply=false'),
        isTrue,
      );
    });

    test('keeps meaningful events', () {
      expect(isVerboseOnly('=== log started ==='), isFalse);
      expect(
        isVerboseOnly('FOLLOW global(...) local(...) => apply=true seek'),
        isFalse,
      );
      expect(isVerboseOnly('reconnect: room emptied, ignoring'), isFalse);
      expect(isVerboseOnly('ERROR socket closed'), isFalse);
    });
  });

  group('level filtering', () {
    test('off writes nothing and opens no file', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.off)
        ..start();
      log('>> spam');
      log('meaningful');
      await log.close();
      expect(logsIn(dir), isEmpty);
    });

    test('neat drops verbose-only lines but keeps events', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.neat)
        ..start();
      log('<< heartbeat');
      log('>> heartbeat');
      log('FOLLOW g l => apply=false');
      log('FOLLOW g l => apply=true seek');
      log('reconnect: room emptied');
      await log.close();

      final text = logsIn(dir).single.readAsStringSync();
      expect(text, isNot(contains('heartbeat')));
      expect(text, isNot(contains('apply=false')));
      expect(text, contains('apply=true seek'));
      expect(text, contains('reconnect: room emptied'));
    });

    test('verbose keeps everything', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.verbose)
        ..start();
      log('<< heartbeat');
      log('FOLLOW g l => apply=false');
      await log.close();

      final text = logsIn(dir).single.readAsStringSync();
      expect(text, contains('<< heartbeat'));
      expect(text, contains('apply=false'));
    });

    test('flush makes buffered lines readable without closing', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.verbose)
        ..start();
      log('mid-session line');
      await log.flush();
      // Still open (not closed) — yet the line is on disk for an export read.
      final text = logsIn(dir).single.readAsStringSync();
      expect(text, contains('mid-session line'));
      await log.close();
    });

    test('flush after switching off awaits the in-flight close', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.verbose)
        ..start();
      log('line before off');
      log.level = LogLevel.off; // kicks off an async flush+close
      // Export calls flush() right after — it must wait for that close so the
      // last buffered line is on disk before the zip reads it.
      await log.flush();
      final text = logsIn(dir).single.readAsStringSync();
      expect(text, contains('line before off'));
    });

    test('switching off mid-session stops writing', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.verbose)
        ..start();
      log('before');
      log.level = LogLevel.off;
      log('after');
      // Sink closed asynchronously by the setter; let it settle, then the
      // file holds only what was written before the switch.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final text = logsIn(dir).single.readAsStringSync();
      expect(text, contains('before'));
      expect(text, isNot(contains('after')));
    });

    test('switching on from off opens a fresh file', () async {
      final log = DebugLog.inDir(dir, baseName: 'x', level: LogLevel.off)
        ..start();
      expect(logsIn(dir), isEmpty);
      log.level = LogLevel.verbose;
      log('now recording');
      await log.close();
      expect(logsIn(dir).single.readAsStringSync(), contains('now recording'));
    });
  });

  group('rotation', () {
    test('each start writes a new file', () async {
      var t = DateTime(2026, 6, 11, 16, 0, 0);
      DateTime clock() => t;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(seconds: 1));
        final log = DebugLog.inDir(dir, baseName: 'sync', clock: clock)
          ..start();
        log('session $i');
        await log.close();
      }
      expect(logsIn(dir).length, 3);
    });

    test('prunes to the newest <retain> logs', () async {
      var t = DateTime(2026, 6, 11, 16, 0, 0);
      DateTime clock() => t;
      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(seconds: 1));
        final log = DebugLog.inDir(
          dir,
          baseName: 'sync',
          retain: 10,
          clock: clock,
        )..start();
        log('session $i');
        await log.close();
      }
      final remaining = logsIn(dir);
      expect(remaining.length, 10);
      // Oldest two (sessions 0 and 1) were pruned; newest survives. Anchor on
      // the trailing newline so 'session 1' doesn't match 'session 11'.
      final allText = remaining.map((f) => f.readAsStringSync()).join('\n');
      expect(allText, isNot(contains('session 0\n')));
      expect(allText, isNot(contains('session 1\n')));
      expect(allText, contains('session 11\n'));
    });

    test('only prunes our own base-named logs', () async {
      File(
        '${dir.path}${Platform.pathSeparator}other.log',
      ).writeAsStringSync('keep me');
      var t = DateTime(2026, 6, 11, 16, 0, 0);
      DateTime clock() => t;
      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(seconds: 1));
        final log = DebugLog.inDir(
          dir,
          baseName: 'sync',
          retain: 10,
          clock: clock,
        )..start();
        log('session $i');
        await log.close();
      }
      expect(
        File('${dir.path}${Platform.pathSeparator}other.log').existsSync(),
        isTrue,
      );
    });
  });
}
