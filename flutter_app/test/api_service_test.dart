import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/services/api_service.dart';

void main() {
  test('normalizeServerUrl adds http scheme and trims trailing slash', () {
    expect(normalizeServerUrl('ytnd.local:8080/'), 'http://ytnd.local:8080');
    expect(
      normalizeServerUrl('https://ytnd.example.com/'),
      'https://ytnd.example.com',
    );
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
            .having(
              (e) => e.message,
              'message',
              'Username or password is incorrect.',
            ),
      ),
    );
  });

  test(
    'http errors use structured detail as the user-facing message',
    () async {
      final error = await _loginExceptionFor(
        statusCode: 400,
        body: jsonEncode({'detail': 'Server rejected this request.'}),
        contentType: ContentType.json,
      );

      expect(error.kind, ApiErrorKind.invalidRequest);
      expect(error.message, 'Server rejected this request.');
      expect(error.details, contains('Server rejected this request.'));
    },
  );

  test('http errors do not expose plain-text bodies as messages', () async {
    const cases = <(int, ApiErrorKind)>[
      (400, ApiErrorKind.invalidRequest),
      (404, ApiErrorKind.notFound),
      (409, ApiErrorKind.conflict),
      (418, ApiErrorKind.unknown),
    ];

    for (final (statusCode, kind) in cases) {
      final error = await _loginExceptionFor(
        statusCode: statusCode,
        body: 'raw backend text for $statusCode',
      );

      expect(error.kind, kind);
      expect(error.message, 'Username or password is incorrect.');
      expect(error.message, isNot(contains('raw backend text')));
      expect(error.details, contains('raw backend text'));
    }
  });
}

Future<ApiException> _loginExceptionFor({
  required int statusCode,
  required String body,
  ContentType? contentType,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  server.listen((request) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = contentType ?? ContentType.text;
    request.response.write(body);
    await request.response.close();
  });

  try {
    await ApiService().login(
      serverUrl: 'http://${server.address.host}:${server.port}',
      username: 'demo',
      password: 'wrong',
    );
  } on ApiException catch (error) {
    return error;
  }

  fail('Expected ApiException.');
}
