import 'package:cosmic_download/shared_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firstHttpUrl', () {
    test('extracts a URL from Facebook-style shared text', () {
      expect(
        firstHttpUrl('Watch this clip\nhttps://www.facebook.com/watch/?v=123'),
        'https://www.facebook.com/watch/?v=123',
      );
    });

    test('removes trailing punctuation from a copied sentence', () {
      expect(
        firstHttpUrl('Video: https://youtu.be/abc123.'),
        'https://youtu.be/abc123',
      );
    });

    test('ignores non-web schemes and text without a URL', () {
      expect(firstHttpUrl('No link here'), isNull);
      expect(firstHttpUrl('file:///sdcard/video.mp4'), isNull);
    });
  });
}
