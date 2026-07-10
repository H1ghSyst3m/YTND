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

  static String queueKeyFor(String url) {
    final value = url.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !_isYoutubeHost(uri.host)) {
      return value;
    }

    final videoId = _videoIdFor(uri);
    if (videoId != null && videoId.isNotEmpty) {
      return 'youtube:video:$videoId';
    }

    final playlistId = uri.queryParameters['list'];
    if (playlistId != null && playlistId.isNotEmpty) {
      return 'youtube:playlist:$playlistId';
    }

    return uri.replace(fragment: '').toString();
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

  static String? _videoIdFor(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      return uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    }

    final watchId = uri.queryParameters['v'];
    if (watchId != null && watchId.isNotEmpty) {
      return watchId;
    }

    if (uri.pathSegments.length >= 2) {
      final section = uri.pathSegments.first.toLowerCase();
      if (section == 'shorts' || section == 'embed' || section == 'live') {
        return uri.pathSegments[1];
      }
    }

    return null;
  }
}
