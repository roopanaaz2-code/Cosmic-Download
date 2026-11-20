import 'package:cosmic_download/youtube_403_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes YouTube 403 and SABR failures', () {
    expect(
      isYoutube403('https://www.youtube.com/watch?v=x', 'HTTP Error 403: Forbidden'),
      isTrue,
    );
    expect(
      isYoutube403('https://youtu.be/x', 'YouTube is forcing SABR streaming'),
      isTrue,
    );
  });

  test('does not retry unrelated hosts or unrelated YouTube errors', () {
    expect(
      isYoutube403('https://facebook.com/video', 'HTTP Error 403: Forbidden'),
      isFalse,
    );
    expect(
      isYoutube403('https://youtube.com/watch?v=x', 'HTTP Error 404: Not Found'),
      isFalse,
    );
  });
}
