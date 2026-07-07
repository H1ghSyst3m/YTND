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

  test('trims common trailing punctuation from YouTube links', () {
    final urls = SharedUrlParser.extractYoutubeUrls(
      'Watch https://youtu.be/paren) and https://youtu.be/bracket] plus https://youtu.be/bang! and https://youtu.be/question?',
    );

    expect(urls, [
      'https://youtu.be/paren',
      'https://youtu.be/bracket',
      'https://youtu.be/bang',
      'https://youtu.be/question',
    ]);
  });

  test('accepts http YouTube links and keeps balanced punctuation', () {
    final urls = SharedUrlParser.extractYoutubeUrls(
      'http://www.youtube.com/watch?v=plain https://www.youtube.com/watch?v=(abc)',
    );

    expect(urls, [
      'http://www.youtube.com/watch?v=plain',
      'https://www.youtube.com/watch?v=(abc)',
    ]);
  });
}
