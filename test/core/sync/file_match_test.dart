import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/core/sync/file_match.dart';

void main() {
  group('compareFiles', () {
    test('unknown when peer has not announced a file', () {
      expect(
        compareFiles(localName: 'movie.mkv', localSize: 100),
        FileMatch.unknown,
      );
    });

    test('unknown when local has no file', () {
      expect(
        compareFiles(peerName: 'movie.mkv', peerSize: 100),
        FileMatch.unknown,
      );
    });

    test('size match wins even when names differ', () {
      expect(
        compareFiles(
          localName: 'movie.mkv',
          localSize: 12345,
          peerName: 'renamed.mkv',
          peerSize: 12345,
        ),
        FileMatch.match,
      );
    });

    test('size mismatch wins even when names are identical', () {
      expect(
        compareFiles(
          localName: 'movie.mkv',
          localSize: 12345,
          peerName: 'movie.mkv',
          peerSize: 99999,
        ),
        FileMatch.mismatch,
      );
    });

    test('falls back to normalized name when a size is missing', () {
      expect(
        compareFiles(localName: 'Movie.MKV', peerName: 'movie.mkv'),
        FileMatch.match,
      );
      expect(
        compareFiles(localName: 'a.mkv', peerName: 'b.mkv'),
        FileMatch.mismatch,
      );
    });

    test('name fallback used when only one side reports size', () {
      expect(
        compareFiles(
          localName: 'show.mp4',
          localSize: 500,
          peerName: 'show.mp4',
        ),
        FileMatch.match,
      );
    });
  });
}
