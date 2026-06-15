import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/picker_initial_directory.dart';
import 'package:path/path.dart' as p;

void main() {
  // A directoryExists that returns true only for the given set of paths.
  bool Function(String) existsFor(Set<String> existing) =>
      (path) => existing.contains(path);

  group('resolvePickerInitialDirectory', () {
    test('prefers the folder of the last loaded local file', () {
      final last = p.join('D', 'Movies', 'show.mkv');
      final lastDir = p.dirname(last);
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: last,
        recentFilePath: p.join('E', 'Other', 'old.mp4'),
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        directoryExists: existsFor({lastDir}),
      );
      expect(result, lastDir);
    });

    test('falls back to recent history folder when no last load', () {
      final recent = p.join('E', 'Anime', 'ep1.mkv');
      final recentDir = p.dirname(recent);
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: recent,
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        directoryExists: existsFor({recentDir}),
      );
      expect(result, recentDir);
    });

    test('skips a URL last source and uses the recent folder', () {
      final recent = p.join('E', 'Anime', 'ep1.mkv');
      final recentDir = p.dirname(recent);
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: 'https://cdn.example.com/stream.m3u8',
        recentFilePath: recent,
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        directoryExists: existsFor({recentDir}),
      );
      expect(result, recentDir);
    });

    test('skips a URL recent source too', () {
      final home = p.join('C', 'Users', 'me');
      final videos = p.join(home, 'Videos');
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: 'http://a.example/v.mp4',
        recentFilePath: 'https://b.example/v.mp4',
        environment: {'USERPROFILE': home},
        directoryExists: existsFor({videos, home}),
      );
      expect(result, videos);
    });

    test('falls back to the Videos folder when no file candidates exist', () {
      final home = p.join('C', 'Users', 'me');
      final videos = p.join(home, 'Videos');
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: p.join('D', 'gone', 'x.mkv'),
        recentFilePath: null,
        environment: {'USERPROFILE': home},
        directoryExists: existsFor({videos, home}),
      );
      expect(result, videos);
    });

    test('falls back to home when Videos is missing', () {
      final home = p.join('C', 'Users', 'me');
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: {'USERPROFILE': home},
        directoryExists: existsFor({home}),
      );
      expect(result, home);
    });

    test('uses HOME when USERPROFILE is unset (non-Windows)', () {
      final home = p.join('home', 'me');
      final videos = p.join(home, 'Videos');
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: {'HOME': home},
        directoryExists: existsFor({videos}),
      );
      expect(result, videos);
    });

    test('returns null when nothing exists', () {
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: p.join('D', 'gone', 'x.mkv'),
        recentFilePath: p.join('E', 'gone', 'y.mkv'),
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        directoryExists: existsFor({}),
      );
      expect(result, isNull);
    });

    test('returns null when there are no candidates at all', () {
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: const {},
        directoryExists: (_) => true,
      );
      expect(result, isNull);
    });

    test('ignores empty-string sources', () {
      final home = p.join('C', 'Users', 'me');
      final result = resolvePickerInitialDirectory(
        lastLoadedFilePath: '',
        recentFilePath: '',
        environment: {'USERPROFILE': home},
        directoryExists: existsFor({home}),
      );
      expect(result, home);
    });
  });
}
