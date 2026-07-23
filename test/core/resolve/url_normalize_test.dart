import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/resolve/url_normalize.dart';

void main() {
  group('normalizePageUrl — YouTube', () {
    const canonical = 'https://youtu.be/g3COomyetSc';

    test('strips the ?si= share tracking token', () {
      expect(
        normalizePageUrl('https://youtu.be/g3COomyetSc?si=sdY1nOA0HQQVwjCm'),
        canonical,
      );
    });

    test('two different ?si= values collapse to the same canonical URL', () {
      final a = normalizePageUrl('https://youtu.be/g3COomyetSc?si=_mTivww8G77');
      final b = normalizePageUrl('https://youtu.be/g3COomyetSc?si=qBYBrj8mknu');
      expect(a, b);
      expect(a, canonical);
    });

    test('canonicalizes the watch?v= form and drops &t= start time', () {
      expect(
        normalizePageUrl('https://www.youtube.com/watch?v=g3COomyetSc&t=17s'),
        canonical,
      );
    });

    test('drops a &list= playlist so both peers watch the same single video',
        () {
      expect(
        normalizePageUrl(
            'https://www.youtube.com/watch?v=g3COomyetSc&list=PLxyz&index=3'),
        canonical,
      );
    });

    test('handles m. and music. hosts and shorts', () {
      expect(normalizePageUrl('https://m.youtube.com/watch?v=g3COomyetSc'),
          canonical);
      expect(normalizePageUrl('https://music.youtube.com/watch?v=g3COomyetSc'),
          canonical);
      expect(normalizePageUrl('https://www.youtube.com/shorts/g3COomyetSc'),
          canonical);
    });

    test('an already-canonical URL is unchanged (idempotent)', () {
      expect(normalizePageUrl(canonical), canonical);
      expect(normalizePageUrl(normalizePageUrl(canonical)), canonical);
    });

    test('trims surrounding whitespace', () {
      expect(normalizePageUrl('  https://youtu.be/g3COomyetSc?si=x  '),
          canonical);
    });
  });

  group('normalizePageUrl — other sites', () {
    test('strips generic tracking params but keeps meaningful ones', () {
      // Bilibili `p=` (which sub-video) is meaningful and must survive; the
      // `spm_id_from`/`vd_source` trackers should not.
      expect(
        normalizePageUrl(
            'https://www.bilibili.com/video/BV1xx?p=2&spm_id_from=333&vd_source=abc'),
        'https://www.bilibili.com/video/BV1xx?p=2',
      );
    });

    test('a URL with no tracking params is returned unchanged', () {
      const url = 'https://www.bilibili.com/video/BV1xx';
      expect(normalizePageUrl(url), url);
    });

    test('leaves a non-http string untouched', () {
      expect(normalizePageUrl('not a url'), 'not a url');
      expect(normalizePageUrl(r'C:\videos\clip.mp4'), r'C:\videos\clip.mp4');
    });
  });
}
