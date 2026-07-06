import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/services/shared_url_parser.dart';

void main() {
  test('extracts unique YouTube links from shared text', () {
    final urls = SharedUrlParser.extractYoutubeUrls('''
Check this out: https://youtu.be/abc123?si=share.
Title line
https://www.youtube.com/watch?v=abc123&list=one
Duplicate: https://youtu.be/abc123?si=share
Not supported: https://example.com/watch?v=abc123
''');

    expect(
      urls,
      [
        'https://youtu.be/abc123?si=share',
        'https://www.youtube.com/watch?v=abc123&list=one',
      ],
    );
  });

  test('accepts mobile, music, and nocookie YouTube hosts', () {
    final urls = SharedUrlParser.extractYoutubeUrls(
      'https://m.youtube.com/watch?v=1 https://music.youtube.com/watch?v=2 https://www.youtube-nocookie.com/embed/3',
    );

    expect(urls, hasLength(3));
  });
}
