class SharedUrlParser {
  SharedUrlParser._();

  static final RegExp _urlPattern = RegExp(
    "https?:\\/\\/[^\\s<>\"']+",
    caseSensitive: false,
  );

  static List<String> extractYoutubeUrls(String text) {
    final urls = <String>[];
    final seen = <String>{};

    for (final match in _urlPattern.allMatches(text)) {
      final normalized = _trimUrl(match.group(0) ?? '');
      final uri = Uri.tryParse(normalized);
      if (uri == null || !_isYoutubeHost(uri.host)) {
        continue;
      }
      final value = uri.toString();
      if (seen.add(value)) {
        urls.add(value);
      }
    }

    return urls;
  }

  static String _trimUrl(String url) {
    var value = url.trim();
    while (value.endsWith('.') ||
        value.endsWith(',') ||
        value.endsWith(';') ||
        value.endsWith(')') ||
        value.endsWith(']')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool _isYoutubeHost(String host) {
    final value = host.toLowerCase();
    return value == 'youtu.be' ||
        value == 'youtube.com' ||
        value.endsWith('.youtube.com') ||
        value == 'youtube-nocookie.com' ||
        value.endsWith('.youtube-nocookie.com');
  }
}
