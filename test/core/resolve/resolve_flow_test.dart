import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/resolve_error.dart';
import 'package:meowwatch/core/resolve/resolve_flow.dart';
import 'package:meowwatch/core/resolve/resolved_media.dart';

void main() {
  const resolved = ResolvedMedia(
    pageUrl: 'https://example.com/watch?v=1',
    videoUrl: 'https://cdn.example.com/v.mp4',
  );

  ResolveFlow flow({
    Future<String> Function()? provision,
    Future<ResolvedMedia> Function(String pageUrl)? resolve,
    Future<void> Function(String exe)? backgroundUpdate,
    Future<bool> Function(String exe)? updateNow,
  }) {
    return ResolveFlow(
      toolsDirProvider: () async => Directory.systemTemp,
      provision: (dir, onStatus) async {
        onStatus?.call('Setting up the video finder…');
        return provision != null ? provision() : 'C:/tools/yt-dlp.exe';
      },
      resolve: (exe, pageUrl) =>
          resolve != null ? resolve(pageUrl) : Future.value(resolved),
      backgroundUpdate: backgroundUpdate ?? (_) async {},
      updateNow: updateNow ?? (_) async => false,
    );
  }

  test('happy path: provisions, emits statuses, returns resolved media',
      () async {
    final statuses = <String>[];
    final result = await flow().run(resolved.pageUrl, onStatus: statuses.add);
    expect(result.videoUrl, resolved.videoUrl);
    expect(statuses.first, 'Setting up the video finder…');
    expect(statuses.last, 'Finding the video…');
  });

  test('passes the page URL through to the resolver', () async {
    String? seen;
    await flow(resolve: (pageUrl) async {
      seen = pageUrl;
      return resolved;
    }).run('https://site/page');
    expect(seen, 'https://site/page');
  });

  test('ResolveException from provisioning propagates unchanged', () async {
    await expectLater(
      flow(
        provision: () =>
            throw const ResolveException(ResolveErrorKind.network, 'down'),
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.network)),
    );
  });

  test('ResolveException from the resolver propagates unchanged', () async {
    await expectLater(
      flow(
        resolve: (_) =>
            throw const ResolveException(ResolveErrorKind.drm, 'drm'),
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.drm)),
    );
  });

  test('unexpected exception is normalized to a ResolveException(unknown)',
      () async {
    await expectLater(
      flow(
        resolve: (_) => throw const ProcessException('yt-dlp.exe', []),
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.unknown)),
    );
  });

  test('kicks off a background update with the provisioned exe', () async {
    String? seen;
    await flow(backgroundUpdate: (exe) async => seen = exe)
        .run(resolved.pageUrl);
    expect(seen, 'C:/tools/yt-dlp.exe');
  });

  test('a never-finishing background update does not block the resolve',
      () async {
    final result = await flow(
      backgroundUpdate: (_) => Completer<void>().future,
    ).run(resolved.pageUrl).timeout(const Duration(seconds: 5));
    expect(result.videoUrl, resolved.videoUrl);
  });

  test('unsupportedSite + successful update retries once and succeeds',
      () async {
    var attempts = 0;
    final statuses = <String>[];
    final result = await flow(
      resolve: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const ResolveException(
              ResolveErrorKind.unsupportedSite, 'broke');
        }
        return resolved;
      },
      updateNow: (_) async => true,
    ).run(resolved.pageUrl, onStatus: statuses.add);
    expect(result.videoUrl, resolved.videoUrl);
    expect(attempts, 2);
    expect(
      statuses,
      contains('The video finder needed an update — retrying…'),
    );
  });

  test('unsupportedSite with no update available surfaces the original error',
      () async {
    var attempts = 0;
    var updateCalls = 0;
    await expectLater(
      flow(
        resolve: (_) async {
          attempts++;
          throw const ResolveException(
              ResolveErrorKind.unsupportedSite, 'broke');
        },
        updateNow: (_) async {
          updateCalls++;
          return false;
        },
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.unsupportedSite)),
    );
    expect(attempts, 1);
    expect(updateCalls, 1);
  });

  test('unknown resolve failure also triggers the update-and-retry path',
      () async {
    var attempts = 0;
    final result = await flow(
      resolve: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const ResolveException(ResolveErrorKind.unknown, 'json');
        }
        return resolved;
      },
      updateNow: (_) async => true,
    ).run(resolved.pageUrl);
    expect(result.videoUrl, resolved.videoUrl);
    expect(attempts, 2);
  });

  test('network failure never triggers an update attempt', () async {
    var updateCalls = 0;
    await expectLater(
      flow(
        resolve: (_) =>
            throw const ResolveException(ResolveErrorKind.network, 'down'),
        updateNow: (_) async {
          updateCalls++;
          return true;
        },
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()
          .having((e) => e.kind, 'kind', ResolveErrorKind.network)),
    );
    expect(updateCalls, 0);
  });

  test('retries at most once even if the retry fails the same way', () async {
    var attempts = 0;
    var updateCalls = 0;
    await expectLater(
      flow(
        resolve: (_) async {
          attempts++;
          throw const ResolveException(
              ResolveErrorKind.unsupportedSite, 'still broke');
        },
        updateNow: (_) async {
          updateCalls++;
          return true;
        },
      ).run(resolved.pageUrl),
      throwsA(isA<ResolveException>()),
    );
    expect(attempts, 2);
    expect(updateCalls, 1);
  });
}
