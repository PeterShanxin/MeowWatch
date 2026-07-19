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
  }) {
    return ResolveFlow(
      toolsDirProvider: () async => Directory.systemTemp,
      provision: (dir, onStatus) async {
        onStatus?.call('Setting up the video finder…');
        return provision != null ? provision() : 'C:/tools/yt-dlp.exe';
      },
      resolve: (exe, pageUrl) =>
          resolve != null ? resolve(pageUrl) : Future.value(resolved),
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
}
