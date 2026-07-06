import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/song.dart';

const Duration _kConnectTimeout = Duration(seconds: 10);
const Duration _kRequestTimeout = Duration(seconds: 15);
const Duration _kDownloadTimeout = Duration(minutes: 5);

enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  server,
  invalidResponse,
  invalidRequest,
  conflict,
  notFound,
  unknown,
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.details,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? details;

  bool get isAuthFailure => kind == ApiErrorKind.unauthorized || kind == ApiErrorKind.forbidden;

  @override
  String toString() => message;
}

String normalizeServerUrl(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    throw const ApiException(
      kind: ApiErrorKind.invalidRequest,
      message: 'Enter a server address.',
    );
  }
  if (!normalized.contains('://')) {
    normalized = 'http://$normalized';
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const ApiException(
      kind: ApiErrorKind.invalidRequest,
      message: 'Enter a valid server URL.',
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const ApiException(
      kind: ApiErrorKind.invalidRequest,
      message: 'Server URL must start with http:// or https://.',
    );
  }
  return normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
}

class ApiService {
  Uri _uri(String base, String path, [Map<String, String>? query]) {
    final url = Uri.parse('${normalizeServerUrl(base)}$path');
    if (query == null) {
      return url;
    }
    return url.replace(queryParameters: query);
  }

  Future<T> _withClient<T>(Future<T> Function(HttpClient client) run) async {
    final client = HttpClient()..connectionTimeout = _kConnectTimeout;
    try {
      return await run(client);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        kind: ApiErrorKind.timeout,
        message: 'The server took too long to respond.',
      );
    } on SocketException catch (e) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message: 'Cannot reach the server. Check the address and your network connection.',
        details: e.message,
      );
    } on HandshakeException catch (e) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message: 'The secure connection failed. Check the server certificate or use the correct URL.',
        details: e.message,
      );
    } on FormatException catch (e) {
      throw ApiException(
        kind: ApiErrorKind.invalidResponse,
        message: 'The server returned data YTND could not read.',
        details: e.message,
      );
    } catch (e) {
      throw ApiException(
        kind: ApiErrorKind.unknown,
        message: 'Something went wrong while talking to the server.',
        details: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _readBody(HttpClientResponse response) {
    return utf8.decodeStream(response).timeout(_kRequestTimeout);
  }

  Map<String, dynamic> _jsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiException(
      kind: ApiErrorKind.invalidResponse,
      message: 'The server returned an unexpected response.',
    );
  }

  String _detailFromBody(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'] ?? decoded['message'] ?? decoded['error'];
        if (detail != null) {
          return detail.toString();
        }
      }
    } catch (_) {
      // Fall through to a short plain-text detail for diagnostics.
    }
    return body.length > 240 ? '${body.substring(0, 240)}...' : body;
  }

  ApiException _httpError({
    required int statusCode,
    required String body,
    required String fallbackMessage,
  }) {
    final detail = _detailFromBody(body);
    final message = detail.isEmpty ? fallbackMessage : detail;
    switch (statusCode) {
      case 400:
        return ApiException(
          kind: ApiErrorKind.invalidRequest,
          statusCode: statusCode,
          message: message,
          details: body,
        );
      case 401:
        return ApiException(
          kind: ApiErrorKind.unauthorized,
          statusCode: statusCode,
          message: fallbackMessage,
          details: body,
        );
      case 403:
        return ApiException(
          kind: ApiErrorKind.forbidden,
          statusCode: statusCode,
          message: 'This account cannot access that resource.',
          details: body,
        );
      case 404:
        return ApiException(
          kind: ApiErrorKind.notFound,
          statusCode: statusCode,
          message: message.isEmpty ? 'The requested item was not found.' : message,
          details: body,
        );
      case 409:
        return ApiException(
          kind: ApiErrorKind.conflict,
          statusCode: statusCode,
          message: message,
          details: body,
        );
      default:
        return ApiException(
          kind: statusCode >= 500 ? ApiErrorKind.server : ApiErrorKind.unknown,
          statusCode: statusCode,
          message: statusCode >= 500 ? 'The server had a problem. Try again later.' : message,
          details: body,
        );
    }
  }

  void _throwIfNotOk(
    HttpClientResponse response,
    String body,
    String fallbackMessage,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw _httpError(
      statusCode: response.statusCode,
      body: body,
      fallbackMessage: fallbackMessage,
    );
  }

  Future<(String userId, String cookieHeader)> login({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    return _withClient((client) async {
      final request = await client.postUrl(_uri(serverUrl, '/api/login')).timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      final form = Uri(
        queryParameters: <String, String>{
          'username': username,
          'password': password,
        },
      ).query;
      request.add(utf8.encode(form));

      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Username or password is incorrect.');

      final jsonMap = _jsonObject(body);
      final userId = (jsonMap['userId'] as String?) ?? '';
      if (userId.isEmpty) {
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'Login succeeded, but the server did not return a user id.',
        );
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
        throw const ApiException(
          kind: ApiErrorKind.invalidResponse,
          message: 'Login succeeded, but the server did not return a session.',
        );
      }

      return (userId, cookieParts.join('; '));
    });
  }

  Future<bool> ping({
    required String serverUrl,
    required String cookieHeader,
  }) {
    return _withClient((client) async {
      final request = await client.getUrl(_uri(serverUrl, '/api/ping')).timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Your session expired. Sign in again.');
      final jsonMap = _jsonObject(body);
      return (jsonMap['authorized'] as bool?) ?? false;
    });
  }

  Future<List<Song>> fetchSongs({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) {
    return _withClient((client) async {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/songs', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not load your library.');

      final jsonMap = _jsonObject(body);
      return (jsonMap['songs'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList();
    });
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
  }) {
    return _withClient((client) async {
      final query = <String, String>{'user_id': userId};
      if (song.id != null && song.id!.isNotEmpty) {
        query['id'] = song.id!;
      } else {
        query['title'] = song.title;
        query['artist'] = song.artist;
      }

      final request = await client.deleteUrl(_uri(serverUrl, '/api/songs', query)).timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not delete this song.');
    });
  }

  Future<void> redownloadSong({
    required String serverUrl,
    required String userId,
    required Song song,
    required String cookieHeader,
    bool force = false,
  }) {
    return _withClient((client) async {
      final query = <String, String>{
        'user_id': userId,
        'force': force.toString(),
      };
      if (song.id != null && song.id!.isNotEmpty) {
        query['id'] = song.id!;
      } else {
        query['title'] = song.title;
        query['artist'] = song.artist;
      }
      final request = await client.postUrl(_uri(serverUrl, '/api/redownload', query)).timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not queue this song for redownload.');
    });
  }

  Future<void> downloadSong({
    required String serverUrl,
    required String userId,
    required String filename,
    required String cookieHeader,
    required File targetFile,
  }) {
    return _withClient((client) async {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/download', {
            'user_id': userId,
            'filename': filename,
          }))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      if (response.statusCode != 200) {
        final body = await _readBody(response);
        throw _httpError(
          statusCode: response.statusCode,
          body: body,
          fallbackMessage: 'Could not download $filename.',
        );
      }

      final tmpFile = File('${targetFile.path}.tmp');
      await tmpFile.parent.create(recursive: true);
      IOSink? sink;
      try {
        sink = tmpFile.openWrite();
        await response.pipe(sink).timeout(_kDownloadTimeout);
        await tmpFile.rename(targetFile.path);
      } catch (_) {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
        rethrow;
      }
    });
  }

  Future<List<String>> fetchQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) {
    return _withClient((client) async {
      final request = await client
          .getUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not load the queue.');
      final jsonMap = _jsonObject(body);
      return (jsonMap['queue'] as List<dynamic>? ?? const <dynamic>[]).whereType<String>().toList();
    });
  }

  Future<void> addToQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    required List<String> urls,
  }) {
    return _withClient((client) async {
      final request = await client
          .postUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
      request.add(utf8.encode(jsonEncode({'urls': urls})));
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not add the link to the queue.');
    });
  }

  Future<void> removeFromQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    List<String>? urls,
  }) {
    return _withClient((client) async {
      final request = await client
          .deleteUrl(_uri(serverUrl, '/api/queue', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      if (urls != null && urls.isNotEmpty) {
        request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
        request.add(utf8.encode(jsonEncode({'urls': urls})));
      }
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not update the queue.');
    });
  }

  Future<int> processQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) {
    return _withClient((client) async {
      final request = await client
          .postUrl(_uri(serverUrl, '/api/queue/process', {'user_id': userId}))
          .timeout(_kRequestTimeout);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      request.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
      request.add(utf8.encode('{}'));
      final response = await request.close().timeout(_kRequestTimeout);
      final body = await _readBody(response);
      _throwIfNotOk(response, body, 'Could not start the queue.');
      final jsonMap = _jsonObject(body);
      return (jsonMap['queued'] as int?) ?? 0;
    });
  }
}
