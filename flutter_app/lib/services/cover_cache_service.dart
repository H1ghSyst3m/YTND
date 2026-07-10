import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CoverCacheService {
  CoverCacheService({
    Directory? cacheDirectory,
    HttpClient Function()? clientFactory,
  }) : _cacheDirectoryOverride = cacheDirectory,
       _clientFactory = clientFactory ?? HttpClient.new;

  static final CoverCacheService instance = CoverCacheService();

  static const _requestTimeout = Duration(seconds: 15);
  static const _downloadTimeout = Duration(seconds: 30);

  final Directory? _cacheDirectoryOverride;
  final HttpClient Function() _clientFactory;
  final Map<String, File> _memoryCache = {};
  final Map<String, Future<File?>> _inFlight = {};

  File? memoryFileFor(String coverUrl) {
    final file = _memoryCache[coverUrl];
    if (file != null && file.existsSync()) {
      return file;
    }
    if (file != null) {
      _memoryCache.remove(coverUrl);
    }
    return null;
  }

  Future<File?> cachedFileFor({
    required String coverUrl,
    required String cookieHeader,
  }) {
    final memoryFile = memoryFileFor(coverUrl);
    if (memoryFile != null) {
      return Future.value(memoryFile);
    }

    return _inFlight.putIfAbsent(coverUrl, () async {
      try {
        final file = await _fileFor(coverUrl);
        if (await file.exists()) {
          _memoryCache[coverUrl] = file;
          return file;
        }
        return await _downloadToCache(
          coverUrl: coverUrl,
          cookieHeader: cookieHeader,
          targetFile: file,
        );
      } finally {
        _inFlight.remove(coverUrl);
      }
    });
  }

  Future<void> prefetchAll({
    required Iterable<String> coverUrls,
    required String cookieHeader,
    int concurrency = 4,
  }) async {
    final urls = coverUrls.toSet().toList(growable: false);
    if (urls.isEmpty) {
      return;
    }

    var nextIndex = 0;
    final workerCount = concurrency.clamp(1, urls.length);
    Future<void> worker() async {
      while (nextIndex < urls.length) {
        final index = nextIndex++;
        try {
          await cachedFileFor(
            coverUrl: urls[index],
            cookieHeader: cookieHeader,
          );
        } catch (_) {
          // Covers are decorative; a failed prefetch should not disturb sync or
          // library refresh flows.
        }
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  Future<File?> _downloadToCache({
    required String coverUrl,
    required String cookieHeader,
    required File targetFile,
  }) async {
    final uri = Uri.parse(coverUrl);
    final tmpFile = File('${targetFile.path}.tmp');
    final client = _clientFactory()..connectionTimeout = _requestTimeout;
    IOSink? sink;

    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      if (cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      await targetFile.parent.create(recursive: true);
      sink = tmpFile.openWrite();
      await response.pipe(sink).timeout(_downloadTimeout);
      final cachedFile = await tmpFile.rename(targetFile.path);
      _memoryCache[coverUrl] = cachedFile;
      return cachedFile;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _fileFor(String coverUrl) async {
    final uri = Uri.parse(coverUrl);
    final root = _cacheDirectoryOverride ?? await getTemporaryDirectory();
    final userKey = _safePathSegment(uri.queryParameters['user_id'] ?? 'user');
    final serverKey = _safePathSegment(
      '${uri.scheme}_${uri.host}_${uri.hasPort ? uri.port : 'default'}',
    );
    final rawFilename =
        uri.queryParameters['filename'] ??
        (uri.pathSegments.isEmpty ? 'cover' : uri.pathSegments.last);
    final basename = _safeBasename(rawFilename);
    final extension = p.extension(basename).isEmpty
        ? '.jpg'
        : p.extension(basename);
    final stem = p.basenameWithoutExtension(basename);
    final filename =
        '${stem.isEmpty ? 'cover' : stem}_${_stableHash(coverUrl)}$extension';

    return File(
      p.join(root.path, 'ytnd_cover_cache', serverKey, userKey, filename),
    );
  }

  String _safeBasename(String value) {
    final basename = value.split(RegExp(r'[\\/]')).last;
    if (basename.isEmpty) {
      return 'cover';
    }
    final safe = _safePathSegment(basename);
    return safe.isEmpty ? 'cover' : safe;
  }

  String _safePathSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..') {
      return '_';
    }
    return safe;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
