import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/update/update_service.dart';
import 'package:path/path.dart' as p;

/// Zip-slip / path-traversal containment for update extraction.
///
/// `applyUpdate` extracts an attacker-influenced zip (whoever can write the R2
/// bucket controls the entry names). Every entry must land *inside* the staging
/// dir; a `..`-traversal or absolute-path entry must be rejected and abort the
/// whole extraction before anything is written outside.
void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mw_extract_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  ArchiveFile fileEntry(String name, String content) {
    final bytes = Uint8List.fromList(content.codeUnits);
    return ArchiveFile(name, bytes.length, bytes);
  }

  test('extracts a normal archive into the target dir', () {
    final archive = Archive()
      ..addFile(fileEntry('meowwatch.exe', 'exe'))
      ..addFile(fileEntry('data/app.so', 'so'));

    UpdateService.extractArchive(archive, tempRoot);

    expect(
      File(p.join(tempRoot.path, 'meowwatch.exe')).readAsStringSync(),
      'exe',
    );
    expect(
      File(p.join(tempRoot.path, 'data', 'app.so')).readAsStringSync(),
      'so',
    );
  });

  test('rejects a parent-traversal entry and writes nothing outside', () {
    final extractDir = Directory(p.join(tempRoot.path, 'extracted'))
      ..createSync();
    // `..` from extractDir lands in tempRoot — outside the staging dir.
    final escaped = File(p.join(tempRoot.path, 'mw_escaped.txt'));
    if (escaped.existsSync()) escaped.deleteSync();

    final archive = Archive()
      ..addFile(fileEntry('..${p.separator}mw_escaped.txt', 'pwned'));

    expect(
      () => UpdateService.extractArchive(archive, extractDir),
      throwsA(isA<UnsafeArchiveEntryException>()),
    );
    expect(escaped.existsSync(), isFalse);
  });

  test('rejects a forward-slash traversal entry', () {
    final extractDir = Directory(p.join(tempRoot.path, 'extracted'))
      ..createSync();
    final archive = Archive()..addFile(fileEntry('../../mw_escaped2.txt', 'x'));

    expect(
      () => UpdateService.extractArchive(archive, extractDir),
      throwsA(isA<UnsafeArchiveEntryException>()),
    );
  });

  test('rejects an absolute-path entry pointing outside the dir', () {
    final extractDir = Directory(p.join(tempRoot.path, 'extracted'))
      ..createSync();
    // Absolute path outside extractDir; p.join returns it verbatim.
    final abs = p.join(tempRoot.path, 'sibling', 'abs.txt');
    final archive = Archive()..addFile(fileEntry(abs, 'x'));

    expect(
      () => UpdateService.extractArchive(archive, extractDir),
      throwsA(isA<UnsafeArchiveEntryException>()),
    );
  });

  test('allows a nested subdirectory entry (legit release layout)', () {
    final archive = Archive()
      ..addFile(fileEntry('data/flutter_assets/AssetManifest.json', '{}'));

    UpdateService.extractArchive(archive, tempRoot);

    expect(
      File(
        p.join(tempRoot.path, 'data', 'flutter_assets', 'AssetManifest.json'),
      ).existsSync(),
      isTrue,
    );
  });
}
