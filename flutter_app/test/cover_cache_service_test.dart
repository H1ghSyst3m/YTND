import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ytnd/services/cover_cache_service.dart';

void main() {
  test('reuses cached cover files without another fetch', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_cover_cache');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final cookies = <String?>[];
    final serverDone = server.listen((request) async {
      requests++;
      cookies.add(request.headers.value(HttpHeaders.cookieHeader));
      request.response
        ..headers.contentType = ContentType.binary
        ..add([1, 2, 3, 4]);
      await request.response.close();
    });
    addTearDown(() async {
      await serverDone.cancel();
      await server.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = CoverCacheService(cacheDirectory: temp);
    final coverUrl =
        'http://127.0.0.1:${server.port}/api/cover?user_id=u1&filename=cover.jpg';

    final first = await service.cachedFileFor(
      coverUrl: coverUrl,
      cookieHeader: 'ytnd_uid=u1',
    );
    final second = await service.cachedFileFor(
      coverUrl: coverUrl,
      cookieHeader: 'ytnd_uid=u1',
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.path, first!.path);
    expect(await second.readAsBytes(), [1, 2, 3, 4]);
    expect(requests, 1);
    expect(cookies.single, 'ytnd_uid=u1');
  });

  test('sanitizes traversal-like cache path segments', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_cover_safe_cache');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = server.listen((request) async {
      request.response
        ..headers.contentType = ContentType.binary
        ..add([5, 6, 7, 8]);
      await request.response.close();
    });
    addTearDown(() async {
      await serverDone.cancel();
      await server.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = CoverCacheService(cacheDirectory: temp);
    final coverUrl = Uri.http(
      '127.0.0.1:${server.port}',
      '/api/cover',
      {'user_id': '..', 'filename': '../..'},
    ).toString();

    final file = await service.cachedFileFor(
      coverUrl: coverUrl,
      cookieHeader: 'ytnd_uid=u1',
    );

    expect(file, isNotNull);
    expect(p.isWithin(temp.path, file!.path), isTrue);
    expect(
      p.split(p.relative(file.path, from: temp.path)),
      isNot(anyElement(anyOf('.', '..'))),
    );
    expect(await file.readAsBytes(), [5, 6, 7, 8]);
  });

  test('rejects cover responses with oversized content length', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_cover_big_header');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = server.listen((request) async {
      try {
        request.response.contentLength = 10 * 1024 * 1024 + 1;
        final chunk = List<int>.filled(1024 * 1024, 1);
        for (var i = 0; i < 10; i++) {
          request.response.add(chunk);
        }
        request.response.add([1]);
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() async {
      await serverDone.cancel();
      await server.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = CoverCacheService(cacheDirectory: temp);
    final file = await service.cachedFileFor(
      coverUrl:
          'http://127.0.0.1:${server.port}/api/cover?user_id=u1&filename=big.jpg',
      cookieHeader: 'ytnd_uid=u1',
    );

    expect(file, isNull);
    expect(await _filesUnder(temp), isEmpty);
  });

  test('rejects cover streams that exceed the size limit', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_cover_big_stream');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = server.listen((request) async {
      try {
        final chunk = List<int>.filled(1024 * 1024, 1);
        for (var i = 0; i < 11; i++) {
          request.response.add(chunk);
          await request.response.flush();
        }
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() async {
      await serverDone.cancel();
      await server.close(force: true);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = CoverCacheService(cacheDirectory: temp);
    final file = await service.cachedFileFor(
      coverUrl:
          'http://127.0.0.1:${server.port}/api/cover?user_id=u1&filename=huge.jpg',
      cookieHeader: 'ytnd_uid=u1',
    );

    expect(file, isNull);
    expect(await _filesUnder(temp), isEmpty);
  });
}

Future<List<File>> _filesUnder(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }
  return directory
      .list(recursive: true)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}
