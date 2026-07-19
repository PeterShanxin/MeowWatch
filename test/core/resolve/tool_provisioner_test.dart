import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  List<int> denoZipBytes() {
    final archive = Archive()
      ..addFile(ArchiveFile('deno.exe', 4, [0x4D, 0x5A, 0x00, 0x01]));
    return ZipEncoder().encode(archive);
  }

  MockClient happyClient({
    bool denoFails = false,
    String? sumsOverride,
    void Function(Uri uri)? onRequest,
  }) {
    return MockClient((request) async {
      onRequest?.call(request.url);
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('/SHA2-256SUMS')) {
        final sums = sumsOverride ??
            'deadbeef  yt-dlp\n$ytDlpSha  yt-dlp.exe\ncafef00d  yt-dlp_x86.exe\n';
        return http.Response(sums, 200);
      }
      if (path.endsWith('.zip')) {
        if (denoFails) return http.Response('server error', 500);
        return http.Response.bytes(denoZipBytes(), 200);
      }
      if (path.endsWith('.sha256sum')) {
        // No sidecar published — provisioner must tolerate this.
        return http.Response('not found', 404);
      }
      return http.Response('unexpected ${request.url}', 404);
    });
  }

  test('fresh dir downloads yt-dlp (verified) and deno, returns exe path',
      () async {
    final statuses = <String>[];
    final provisioner =
        ToolProvisioner(toolsDir: tempDir, client: happyClient());
    final exePath = await provisioner.ensureYtDlp(onStatus: statuses.add);

    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
    expect(File(exePath).readAsBytesSync(), ytDlpBytes);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isTrue);
    expect(statuses, isNotEmpty);
    // No stray partial files left behind.
    expect(
      tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('existing tools short-circuit with zero network calls', () async {
    File(p.join(tempDir.path, 'yt-dlp.exe')).writeAsBytesSync([1, 2, 3]);
    File(p.join(tempDir.path, 'deno.exe')).writeAsBytesSync([4, 5, 6]);
    final throwingClient = MockClient((request) async {
      fail('network call made for ${request.url}');
    });
    final provisioner =
        ToolProvisioner(toolsDir: tempDir, client: throwingClient);
    final exePath = await provisioner.ensureYtDlp();
    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
  });

  test('checksum mismatch throws toolMissing and leaves no exe behind',
      () async {
    final provisioner = ToolProvisioner(
      toolsDir: tempDir,
      client: happyClient(
        sumsOverride: '${'0' * 64}  yt-dlp.exe\n',
      ),
    );
    await expectLater(
      provisioner.ensureYtDlp(),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.toolMissing)),
    );
    expect(File(p.join(tempDir.path, 'yt-dlp.exe')).existsSync(), isFalse);
    expect(
      tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('missing SUMS entry for yt-dlp.exe throws toolMissing', () async {
    final provisioner = ToolProvisioner(
      toolsDir: tempDir,
      client: happyClient(sumsOverride: 'deadbeef  something-else.exe\n'),
    );
    await expectLater(
      provisioner.ensureYtDlp(),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.toolMissing)),
    );
  });

  test('deno download failure is non-fatal: yt-dlp path still returned',
      () async {
    final provisioner =
        ToolProvisioner(toolsDir: tempDir, client: happyClient(denoFails: true));
    final exePath = await provisioner.ensureYtDlp();
    expect(File(exePath).existsSync(), isTrue);
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isFalse);
  });

  test('network failure downloading yt-dlp maps to network kind', () async {
    final provisioner = ToolProvisioner(
      toolsDir: tempDir,
      client: MockClient(
          (request) async => throw const SocketException('no route')),
    );
    await expectLater(
      provisioner.ensureYtDlp(),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.network)),
    );
  });

  test('concurrent first-use calls share one download (single-flight)',
      () async {
    var ytDlpDownloads = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/yt-dlp.exe')) {
        ytDlpDownloads++;
        // Small delay so the second call starts while this one is in flight.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response.bytes(ytDlpBytes, 200);
      }
      if (path.endsWith('/SHA2-256SUMS')) {
        return http.Response('$ytDlpSha  yt-dlp.exe\n', 200);
      }
      if (path.endsWith('.zip')) {
        return http.Response.bytes(denoZipBytes(), 200);
      }
      return http.Response('nope', 404);
    });
    final provisioner = ToolProvisioner(toolsDir: tempDir, client: client);
    final results = await Future.wait([
      provisioner.ensureYtDlp(),
      provisioner.ensureYtDlp(),
    ]);
    expect(results[0], results[1]);
    expect(ytDlpDownloads, 1, reason: 'must not download yt-dlp twice');
    expect(File(results[0]).existsSync(), isTrue);
  });

  test('existing yt-dlp but missing deno fetches only deno', () async {
    File(p.join(tempDir.path, 'yt-dlp.exe')).writeAsBytesSync([1, 2, 3]);
    final requested = <Uri>[];
    final provisioner = ToolProvisioner(
      toolsDir: tempDir,
      client: happyClient(onRequest: requested.add),
    );
    final exePath = await provisioner.ensureYtDlp();
    expect(exePath, p.join(tempDir.path, 'yt-dlp.exe'));
    expect(File(p.join(tempDir.path, 'deno.exe')).existsSync(), isTrue);
    expect(
      requested.where((u) => u.path.endsWith('/yt-dlp.exe')),
      isEmpty,
      reason: 'yt-dlp must not be re-downloaded',
    );
  });
}
