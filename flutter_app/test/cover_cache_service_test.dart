import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
