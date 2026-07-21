import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meowwatch/core/resolve/installed_versions.dart';
import 'package:meowwatch/core/resolve/resolve_error.dart';
import 'package:meowwatch/core/resolve/tool_provisioner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('meow_tools_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final ytDlpBytes = List<int>.generate(64, (i) => i)
    ..setRange(0, 2, 'MZ'.codeUnits);
  final ytDlpSha = sha256.convert(ytDlpBytes).toString();

  // Build the fake deno zip once so its bytes (and hash) are stable — the
  // provisioner verifies both tools against pinned hashes, so tests pass the
  // fakes' own hashes via ytDlpSha256 / denoSha256.
  final denoZipBytes = ZipEncoder().encode(
    Archive()..addFile(ArchiveFile('deno.exe', 4, [0x4D, 0x5A, 0x00, 0x01])),
  );
  final denoZipSha = sha256.convert(denoZipBytes).toString();

  /// A client serving the fake yt-dlp.exe and deno zip at the pinned URLs.
  MockClient happyClient({
    bool denoFails = false,
    void Function(Uri uri)? onRequest,
  }) {
    return MockClient((request) async {
      onRequest?.call(request.url);
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('.zip')) {
        if (denoFails) return http.Response('server error', 500);
        return http.Response.bytes(denoZipBytes, 200);
      }
      return http.Response('unexpected ${request.url}', 404);
    });
  }

  /// A provisioner pre-wired with the fakes' hashes so the pinned-hash checks
  /// accept the test payloads.
  ToolProvisioner provisioner(http.Client client, {String? ytSha}) =>
      ToolProvisioner(
        toolsDir: tempDir,
        client: client,
        ytDlpSha256: ytSha ?? ytDlpSha,
        denoSha256: denoZipSha,
      );

  test('fresh dir downloads yt-dlp (verified) and deno, returns exe path',
      () async {
    final statuses = <String>[];
    final exePath = await provisioner(happyClient())
        .ensureYtDlp(onStatus: statuses.add);

    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
    expect(File(exePath).readAsBytesSync(), ytDlpBytes);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isTrue);
    expect(statuses, isNotEmpty);
    expect(
      tempDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.part'),
          ),
      isEmpty,
    );
  });

  test('existing tools short-circuit with zero network calls', () async {
    File(p.join(tempDir.path, 'yt-dlp.exe')).writeAsBytesSync([1, 2, 3]);
    File(p.join(tempDir.path, 'deno.exe')).writeAsBytesSync([4, 5, 6]);
    final throwingClient = MockClient((request) async {
      fail('network call made for ${request.url}');
    });
    final exePath = await provisioner(throwingClient).ensureYtDlp();
    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
  });

  test('yt-dlp failing the pinned hash throws toolMissing, no exe behind',
      () async {
    // The downloaded bytes don't match the baked hash (wrong pin / tampered
    // release) — fail closed, install nothing.
    final prov = provisioner(happyClient(), ytSha: '0' * 64);
    await expectLater(
      prov.ensureYtDlp(),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.toolMissing)),
    );
    expect(File(p.join(tempDir.path, 'yt-dlp.exe')).existsSync(), isFalse);
    expect(
      tempDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.part'),
          ),
      isEmpty,
    );
  });

  test('deno download failure is non-fatal: yt-dlp path still returned',
      () async {
    final exePath =
        await provisioner(happyClient(denoFails: true)).ensureYtDlp();
    expect(File(exePath).existsSync(), isTrue);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isFalse);
  });

  test('deno zip failing the pinned hash is skipped (non-fatal), no deno.exe',
      () async {
    // A real _kDenoZipSha256 ≠ the fake zip's hash, so deno is rejected but
    // yt-dlp still succeeds.
    final prov = ToolProvisioner(
      toolsDir: tempDir,
      client: happyClient(),
      ytDlpSha256: ytDlpSha, // deno hash left at the baked default
    );
    final exePath = await prov.ensureYtDlp();
    expect(File(exePath).readAsBytesSync(), ytDlpBytes);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isFalse);
  });

  test('network failure downloading yt-dlp maps to network kind', () async {
    final prov = provisioner(
      MockClient((request) async => throw const SocketException('no route')),
    );
    await expectLater(
      prov.ensureYtDlp(),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.network)),
    );
  });

  test('another process installing mid-download wins; we reuse theirs',
      () async {
    // Simulate a second MeowWatch process finishing first: the target yt-dlp
    // appears (with different bytes) while our download is in flight. Our
    // atomic install must detect it and reuse theirs, not clobber it.
    final theirBytes = [9, 9, 9, 9];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        File(p.join(tempDir.path, 'yt-dlp.exe')).writeAsBytesSync(theirBytes);
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('.zip')) {
        return http.Response.bytes(denoZipBytes, 200);
      }
      return http.Response('nope', 404);
    });
    final exePath = await provisioner(client).ensureYtDlp();
    expect(File(exePath).readAsBytesSync(), theirBytes);
    expect(
      tempDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.part'),
          ),
      isEmpty,
    );
    // The bytes on disk are the other process's, and the two co-watch copies
    // on one PC are routinely different builds sharing one tools dir — so its
    // pin may differ from ours. Claiming our pin here would let ToolUpdater
    // see a matching record and skip reconciliation forever, stranding the
    // older resolver (Codex #225 P2).
    expect(InstalledVersions(tempDir)[InstalledVersions.ytDlp], isNull);
  });

  test('records the pin when this process actually installed the tool',
      () async {
    await provisioner(happyClient()).ensureYtDlp();
    final versions = InstalledVersions(tempDir);
    expect(versions[InstalledVersions.ytDlp], ToolProvisioner.ytDlpVersion);
    expect(versions[InstalledVersions.deno], ToolProvisioner.denoVersion);
  });

  test('concurrent first-use calls share one download (single-flight)',
      () async {
    var ytDlpDownloads = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        ytDlpDownloads++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('.zip')) {
        return http.Response.bytes(denoZipBytes, 200);
      }
      return http.Response('nope', 404);
    });
    final prov = provisioner(client);
    final results = await Future.wait([
      prov.ensureYtDlp(),
      prov.ensureYtDlp(),
    ]);
    expect(results[0], results[1]);
    expect(ytDlpDownloads, 1, reason: 'must not download yt-dlp twice');
    expect(File(results[0]).existsSync(), isTrue);
  });

  test('a hash-matching deno zip still cannot overwrite the verified yt-dlp',
      () async {
    // Even a zip that passes the pinned hash must yield only its deno.exe: a
    // smuggled yt-dlp.exe entry can't clobber the verified one. Pass the
    // hostile zip's own hash to isolate the extract-scope guard.
    final hostileZip = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('deno.exe', 4, [0x4D, 0x5A, 0x00, 0x01]))
        ..addFile(ArchiveFile('yt-dlp.exe', 3, [0x66, 0x66, 0x66])),
    );
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('.zip')) {
        return http.Response.bytes(hostileZip, 200);
      }
      return http.Response('nope', 404);
    });
    final prov = ToolProvisioner(
      toolsDir: tempDir,
      client: client,
      ytDlpSha256: ytDlpSha,
      denoSha256: sha256.convert(hostileZip).toString(),
    );
    final exePath = await prov.ensureYtDlp();
    expect(File(exePath).readAsBytesSync(), ytDlpBytes);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isTrue);
  });

  test('existing yt-dlp but missing deno fetches only deno', () async {
    File(p.join(tempDir.path, 'yt-dlp.exe')).writeAsBytesSync([1, 2, 3]);
    final requested = <Uri>[];
    final exePath =
        await provisioner(happyClient(onRequest: requested.add)).ensureYtDlp();
    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isTrue);
    expect(
      requested.where((u) => u.path.endsWith('/yt-dlp.exe')),
      isEmpty,
      reason: 'yt-dlp must not be re-downloaded',
    );
  });
}
