import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/video/picker_initial_directory.dart';
import 'package:path/path.dart' as p;

void main() {
  // An async usability predicate that resolves true only for the given paths.
  Future<bool> Function(String) usableFor(Set<String> existing) =>
      (path) async => existing.contains(path);

  group('resolvePickerInitialDirectory', () {
    test('prefers the folder of the last loaded local file', () async {
      final last = p.join('D', 'Movies', 'show.mkv');
      final lastDir = p.dirname(last);
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: last,
        recentFilePath: p.join('E', 'Other', 'old.mp4'),
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        isDirectoryUsable: usableFor({lastDir}),
      );
      expect(result, lastDir);
    });

    test('falls back to recent history folder when no last load', () async {
      final recent = p.join('E', 'Anime', 'ep1.mkv');
      final recentDir = p.dirname(recent);
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: recent,
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        isDirectoryUsable: usableFor({recentDir}),
      );
      expect(result, recentDir);
    });

    test('skips a URL last source and uses the recent folder', () async {
      final recent = p.join('E', 'Anime', 'ep1.mkv');
      final recentDir = p.dirname(recent);
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: 'https://cdn.example.com/stream.m3u8',
        recentFilePath: recent,
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        isDirectoryUsable: usableFor({recentDir}),
      );
      expect(result, recentDir);
    });

    test('skips a URL recent source too', () async {
      final home = p.join('C', 'Users', 'me');
      final videos = p.join(home, 'Videos');
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: 'http://a.example/v.mp4',
        recentFilePath: 'https://b.example/v.mp4',
        environment: {'USERPROFILE': home},
        isDirectoryUsable: usableFor({videos, home}),
      );
      expect(result, videos);
    });

    test('falls back to the Videos folder when no file candidates exist',
        () async {
      final home = p.join('C', 'Users', 'me');
      final videos = p.join(home, 'Videos');
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: p.join('D', 'gone', 'x.mkv'),
        recentFilePath: null,
        environment: {'USERPROFILE': home},
        isDirectoryUsable: usableFor({videos, home}),
      );
      expect(result, videos);
    });

    test('falls back to home when Videos is missing', () async {
      final home = p.join('C', 'Users', 'me');
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: {'USERPROFILE': home},
        isDirectoryUsable: usableFor({home}),
      );
      expect(result, home);
    });

    test('uses HOME when USERPROFILE is unset (non-Windows)', () async {
      final home = p.join('home', 'me');
      final videos = p.join(home, 'Videos');
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: {'HOME': home},
        isDirectoryUsable: usableFor({videos}),
      );
      expect(result, videos);
    });

    test('returns null when nothing exists', () async {
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: p.join('D', 'gone', 'x.mkv'),
        recentFilePath: p.join('E', 'gone', 'y.mkv'),
        environment: {'USERPROFILE': p.join('C', 'Users', 'me')},
        isDirectoryUsable: usableFor({}),
      );
      expect(result, isNull);
    });

    test('returns null when there are no candidates at all', () async {
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: const {},
        isDirectoryUsable: (_) async => true,
      );
      expect(result, isNull);
    });

    test('ignores empty-string sources', () async {
      final home = p.join('C', 'Users', 'me');
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: '',
        recentFilePath: '',
        environment: {'USERPROFILE': home},
        isDirectoryUsable: usableFor({home}),
      );
      expect(result, home);
    });

    test('stops at the first existing candidate without probing later ones',
        () async {
      final home = p.join('C', 'Users', 'me');
      final videos = p.join(home, 'Videos');
      final probed = <String>[];
      final result = await resolvePickerInitialDirectory(
        lastLoadedFilePath: null,
        recentFilePath: null,
        environment: {'USERPROFILE': home},
        isDirectoryUsable: (path) async {
          probed.add(path);
          return path == videos; // Videos exists; home should never be probed.
        },
      );
      expect(result, videos);
      expect(probed, [videos]);
    });
  });
}
