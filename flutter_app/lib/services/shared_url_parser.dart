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
    while (value.isNotEmpty && _hasTrailingPunctuation(value)) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool _hasTrailingPunctuation(String value) {
    final last = value[value.length - 1];
    return last == '.' ||
        last == ',' ||
        last == ';' ||
        last == '!' ||
        last == '?' ||
        (last == ')' && _hasUnbalancedClosing(value, '(', ')')) ||
        (last == ']' && _hasUnbalancedClosing(value, '[', ']'));
  }

  static bool _hasUnbalancedClosing(String value, String open, String close) {
    var depth = 0;
    for (final codeUnit in value.codeUnits) {
      final char = String.fromCharCode(codeUnit);
      if (char == open) {
        depth++;
      } else if (char == close) {
        depth--;
      }
    }
    return depth < 0;
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
