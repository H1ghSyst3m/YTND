import 'dart:convert';
import 'dart:io';

import '../models/song.dart';

const Duration _kConnectTimeout = Duration(seconds: 10);
const Duration _kRequestTimeout = Duration(seconds: 15);
const Duration _kDownloadTimeout = Duration(minutes: 5);

class ApiService {
  Uri _uri(String base, String path, [Map<String, String>? query]) {
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final url = Uri.parse('$normalized$path');
    if (query == null) {
      return url;
    }
    return url.replace(queryParameters: query);
  }

  Future<(String userId, String cookieHeader)> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .postUrl(_uri(serverUrl, '/api/login'))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      final form = Uri(
        queryParameters: <String, String>{
          'username': username,
          'password': password,
        },
      ).query;
      request.add(utf8.encode(form));

      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        throw Exception('Login failed (${response.statusCode}): $body');
      }

      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      final userId = (jsonMap['userId'] as String?) ?? '';
      if (userId.isEmpty) {
        throw Exception('Login response missing userId');
      }

      final setCookies = response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
      final cookieParts = <String>[];
      for (final cookieLine in setCookies) {
        final token = cookieLine.split(';').first.trim();
        if (token.isNotEmpty) {
          cookieParts.add(token);
        }
      }
      if (cookieParts.isEmpty) {
        throw Exception('Login response missing session cookies');
      }

      return (userId, cookieParts.join('; '));
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> ping({
    required String serverUrl,
    required String cookieHeader,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/ping'))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        return false;
      }
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      return (jsonMap['authorized'] as bool?) ?? false;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Song>> fetchSongs({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/songs', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch songs (${response.statusCode}): $body');
      }

      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      final songs = (jsonMap['songs'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList();
      return songs;
    } finally {
      client.close(force: true);
    }
  }

  Uri coverUrl({
    required String serverUrl,
    required String userId,
    required String filename,
  }) {
    return _uri(serverUrl, '/api/cover', {'user_id': userId, 'filename': filename});
  }

  Future<void> deleteSong({
    required String serverUrl,
    required String userId,
    required Song song,
    required String cookieHeader,
  }) async {
    final query = <String, String>{'user_id': userId};
    if (song.id != null && song.id!.isNotEmpty) {
      query['id'] = song.id!;
    } else {
      query['title'] = song.title;
      query['artist'] = song.artist;
    }

    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .deleteUrl(_uri(serverUrl, '/api/songs', query))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete song (${response.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadSong({
    required String serverUrl,
    required String userId,
    required String filename,
    required String cookieHeader,
    required File targetFile,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/download', {
            'user_id': userId,
            'filename': filename,
          }))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
        throw Exception('Download failed for $filename (${response.statusCode}): $body');
      }

      final tmpFile = File('${targetFile.path}.tmp');
      await tmpFile.parent.create(recursive: true);
      IOSink? sink;
      try {
        sink = tmpFile.openWrite();
        await response.pipe(sink).timeout(_kDownloadTimeout);
        await tmpFile.rename(targetFile.path);
      } catch (e) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
        rethrow;
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> fetchQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch queue (${response.statusCode}): $body');
      }
      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      return (jsonMap['queue'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> addToQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    required List<String> urls,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .postUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
      request.add(utf8.encode(jsonEncode({'urls': urls})));
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to add URLs (${response.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> removeFromQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    List<String>? urls,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .deleteUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      if (urls != null && urls.isNotEmpty) {
        request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
        request.add(utf8.encode(jsonEncode({'urls': urls})));
      }
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to remove from queue (${response.statusCode}): $body');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<int> processQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      final request = await client
          .postUrl(_uri(serverUrl, '/api/queue/process', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
      request.add(utf8.encode('{}'));
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await utf8.decodeStream(response).timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to start queue processing (${response.statusCode}): $body');
      }
      final jsonMap = jsonDecode(body) as Map<String, dynamic>;
      return (jsonMap['queued'] as int?) ?? 0;
    } finally {
      client.close(force: true);
    }
  }
}
