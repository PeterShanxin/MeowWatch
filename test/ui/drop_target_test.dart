import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch/ui/drop_target.dart';

void main() {
  group('isVideoFile', () {
    test('accepts common video extensions', () {
      expect(isVideoFile('foo.mkv'), isTrue);
      expect(isVideoFile('foo.MP4'), isTrue);
      expect(isVideoFile('C:\\path\\foo.avi'), isTrue);
      expect(isVideoFile('foo.webm'), isTrue);
      expect(isVideoFile('foo.mov'), isTrue);
    });

    test('rejects non-video files', () {
      expect(isVideoFile('foo.txt'), isFalse);
      expect(isVideoFile('foo.jpg'), isFalse);
      expect(isVideoFile('foo'), isFalse);
    });
  });
}
