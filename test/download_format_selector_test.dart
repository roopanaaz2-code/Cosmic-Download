import 'package:cosmic_download/download_format_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mediaFormatSelector', () {
    test('prefers H.264/AAC MP4 for the compatible default', () {
      final selector = mediaFormatSelector(
        audioOnly: false,
        quality: 'Most compatible MP4',
      );
      expect(selector, contains('vcodec^=avc1'));
      expect(selector, contains('acodec^=mp4a'));
      expect(selector, contains('[ext=mp4]'));
      expect(selector, contains('[ext=m4a]'));
      expect(selector, isNot(contains('bestvideo+bestaudio/best')));
    });

    test('keeps the chosen resolution as a maximum on both branches', () {
      final selector = mediaFormatSelector(audioOnly: false, quality: '720p');
      expect(selector, contains('bestvideo[height<=720]'));
      expect(selector, contains('best[height<=720]'));
      expect(selector, contains('vcodec^=avc1'));
      expect(selector, contains('acodec^=mp4a'));
    });

    test('uses the best audio source for MP3 extraction', () {
      expect(
        mediaFormatSelector(audioOnly: true, quality: 'Most compatible MP4'),
        'bestaudio/best',
      );
    });

    test('does not codec-filter a fixed direct media URL', () {
      expect(
        mediaFormatSelector(
          audioOnly: false,
          quality: 'Most compatible MP4',
          directMedia: true,
        ),
        'best',
      );
    });
  });
}
