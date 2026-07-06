import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/services/api_service.dart';

void main() {
  test('normalizeServerUrl adds http scheme and trims trailing slash', () {
    expect(normalizeServerUrl('ytnd.local:8080/'), 'http://ytnd.local:8080');
    expect(normalizeServerUrl('https://ytnd.example.com/'), 'https://ytnd.example.com');
  });

  test('login maps unauthorized response to ApiException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'detail': 'Invalid credentials'}));
      await request.response.close();
    });

    final api = ApiService();
    final call = api.login(
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'demo',
      password: 'wrong',
    );

    await expectLater(
      call,
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)
            .having((e) => e.message, 'message', 'Username or password is incorrect.'),
      ),
    );
  });
}
