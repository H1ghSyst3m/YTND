import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/services/api_service.dart';
import 'package:ytnd/services/sync_service.dart';
import 'package:ytnd/services/websocket_service.dart';
import 'package:ytnd/state/app_state.dart';

import 'fakes.dart';

const _connectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

const _signedInSettings = AppSettings(
  serverUrl: 'http://ytnd.local:8080',
  username: 'demo',
  password: 'secret',
  userId: 'u1',
  sessionCookie: 'cookie',
  storagePath: 'test-storage',
);

AppState _buildState({
  FakeSettingsService? settingsService,
  FakeApiService? apiService,
  FakeBackgroundSyncService? backgroundSyncService,
  FakeWebsocketService? websocketService,
  FakeShareIntentService? shareIntentService,
}) {
  final api = apiService ?? FakeApiService();
  return AppState(
    settingsService: settingsService ?? FakeSettingsService(),
    apiService: api,
    syncService: SyncService(api),
    backgroundSyncService: backgroundSyncService ?? FakeBackgroundSyncService(),
    websocketService: websocketService ?? FakeWebsocketService(),
    shareIntentService: shareIntentService ?? FakeShareIntentService(),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initialize keeps server editable when saved server is unreachable',
    () async {
      final settings = FakeSettingsService(
        settings: const AppSettings(
          serverUrl: 'http://ytnd.local:8080',
          username: 'demo',
          password: 'secret',
          userId: 'u1',
          sessionCookie: 'ytnd_uid=u1; ytnd_sig=sig',
          storagePath: 'test-storage',
        ),
      );
      final api = FakeApiService()
        ..pingError = const ApiException(
          kind: ApiErrorKind.network,
          message:
              'Cannot reach the server. Check the address and your network connection.',
        );
      final state = _buildState(settingsService: settings, apiService: api);

      await state.initialize();

      expect(state.initialized, isTrue);
      expect(state.settings.serverUrl, 'http://ytnd.local:8080');
      expect(state.connectionStatus, ConnectionStatus.unreachable);
      expect(state.connectionMessage, contains('Cannot reach the server'));
    },
  );

  test('initial shared links are persisted while signed out', () async {
    final settings = FakeSettingsService();
    final share = FakeShareIntentService(
      initialUrls: const ['https://youtu.be/abc123'],
    );
    final state = _buildState(
      settingsService: settings,
      shareIntentService: share,
    );

    await state.initialize();

    expect(state.pendingShareUrls, ['https://youtu.be/abc123']);
    expect(settings.pendingShareUrls, ['https://youtu.be/abc123']);
    expect(state.connectionStatus, ConnectionStatus.setupRequired);
  });

  test('manual queue add is deferred while signed out', () async {
    final settings = FakeSettingsService();
    final state = _buildState(settingsService: settings);
    await state.initialize();

    final result = await state.addUrlsToQueue(['https://youtu.be/new123']);

    expect(result, QueueAddResult.deferred);
    expect(state.pendingShareUrls, ['https://youtu.be/new123']);
    expect(settings.pendingShareUrls, ['https://youtu.be/new123']);
    expect(state.statusMessage, 'Saved 1 link(s) until you sign in.');
  });

  test('login flushes pending shared links into the queue', () async {
    final settings = FakeSettingsService(
      pendingShareUrls: const ['https://youtu.be/abc123'],
    );
    final api = FakeApiService();
    final state = _buildState(settingsService: settings, apiService: api);
    await state.initialize();

    final signedIn = await state.login(
      serverUrl: 'http://ytnd.local:8080',
      username: 'demo',
      password: 'secret',
    );

    expect(signedIn, isTrue);
    expect(api.queue, ['https://youtu.be/abc123']);
    expect(state.pendingShareUrls, isEmpty);
    expect(settings.pendingShareUrls, isEmpty);
    expect(state.connectionStatus, ConnectionStatus.connected);
  });

  test(
    'failed login with bad credentials shows invalid credentials copy',
    () async {
      final api = FakeApiService()
        ..loginError = const ApiException(
          kind: ApiErrorKind.unauthorized,
          message: 'Username or password is incorrect.',
          statusCode: 401,
        );
      final state = _buildState(apiService: api);
      await state.initialize();

      await expectLater(
        state.login(
          serverUrl: 'ytnd.local:8080',
          username: 'demo',
          password: 'wrong-secret',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(state.connectionStatus, ConnectionStatus.invalidCredentials);
      expect(state.connectionTitle, 'Invalid credentials');
      expect(
        state.connectionMessage,
        'Check your username and password, then try again.',
      );
      expect(state.lastErrorMessage, 'Username or password is incorrect.');
      expect(state.settings.userId, isEmpty);
      expect(state.settings.sessionCookie, isEmpty);
    },
  );

  test(
    'failed login keeps the edited server saved and marks it unreachable',
    () async {
      final settings = FakeSettingsService(
        settings: const AppSettings(
          serverUrl: 'http://old.local',
          username: 'demo',
          password: 'secret',
          userId: 'u1',
          sessionCookie: 'cookie',
          storagePath: 'test-storage',
        ),
      );
      final api = FakeApiService()
        ..loginError = const ApiException(
          kind: ApiErrorKind.network,
          message:
              'Cannot reach the server. Check the address and your network connection.',
        );
      final state = _buildState(settingsService: settings, apiService: api);
      await state.initialize();

      await expectLater(
        state.login(
          serverUrl: 'new.local:8080',
          username: 'new-user',
          password: 'new-secret',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(state.settings.serverUrl, 'http://new.local:8080');
      expect(settings.settings.serverUrl, 'http://new.local:8080');
      expect(state.settings.username, 'new-user');
      expect(state.settings.userId, isEmpty);
      expect(state.connectionStatus, ConnectionStatus.unreachable);
    },
  );

  test('session restore auth failure expires the saved session', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService()
      ..pingError = const ApiException(
        kind: ApiErrorKind.unauthorized,
        message: 'Your session expired. Sign in again.',
        statusCode: 401,
      );
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(state.isAuthenticated, isFalse);
    expect(state.connectionStatus, ConnectionStatus.unauthorized);
    expect(state.settings.userId, isEmpty);
    expect(state.settings.sessionCookie, isEmpty);
    expect(settings.settings.userId, isEmpty);
    expect(settings.settings.sessionCookie, isEmpty);
    expect(state.lastErrorMessage, 'Your session expired. Sign in again.');
  });

  test('websocket download errors do not expose raw backend text', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService()..queue = ['https://youtu.be/abc123'];
    final websocket = FakeWebsocketService();
    final state = _buildState(
      settingsService: settings,
      apiService: api,
      websocketService: websocket,
    );
    await state.initialize();

    websocket.controller.add(
      const WsEvent({
        'type': 'download_progress',
        'url': 'https://youtu.be/abc123',
        'status': 'error',
        'error': 'Traceback: extractor crashed with ValueError',
      }),
    );
    await pumpEventQueue();

    expect(
      state.downloadQueue.single.error,
      'Download failed. Check the link and try again.',
    );

    websocket.controller.add(
      const WsEvent({
        'type': 'download_error',
        'error': 'Traceback: extractor crashed with ValueError',
      }),
    );
    await pumpEventQueue();

    expect(
      state.lastErrorMessage,
      'Download failed. Check the link and try again.',
    );
  });

  for (final kind in [
    ApiErrorKind.notFound,
    ApiErrorKind.conflict,
    ApiErrorKind.invalidResponse,
    ApiErrorKind.unknown,
    ApiErrorKind.server,
    ApiErrorKind.invalidRequest,
  ]) {
    test(
      'operation error $kind preserves the global connection state',
      () async {
        final settings = FakeSettingsService(settings: _signedInSettings);
        final api = FakeApiService()
          ..addError = ApiException(kind: kind, message: 'Operation failed.');
        final state = _buildState(settingsService: settings, apiService: api);
        await state.initialize();

        final result = await state.addUrlsToQueue(['https://youtu.be/new123']);

        expect(result, QueueAddResult.failed);
        expect(state.connectionStatus, ConnectionStatus.connected);
        expect(state.lastErrorMessage, 'Operation failed.');
        expect(state.statusMessage, 'Operation failed.');
      },
    );
  }

  for (final kind in [ApiErrorKind.network, ApiErrorKind.timeout]) {
    test('operation error $kind marks the server unreachable', () async {
      final settings = FakeSettingsService(settings: _signedInSettings);
      final api = FakeApiService()
        ..addError = ApiException(
          kind: kind,
          message: 'Cannot reach the server.',
        );
      final state = _buildState(settingsService: settings, apiService: api);
      await state.initialize();

      final result = await state.addUrlsToQueue(['https://youtu.be/new123']);

      expect(result, QueueAddResult.failed);
      expect(state.connectionStatus, ConnectionStatus.unreachable);
      expect(state.lastErrorMessage, 'Cannot reach the server.');
    });
  }

  test('syncNow locks before checking connectivity', () async {
    final connectivity = Completer<List<String>>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _connectivityChannel,
      (call) {
        expect(call.method, 'check');
        return connectivity.future;
      },
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _connectivityChannel,
        null,
      );
    });

    final settings = FakeSettingsService(settings: _signedInSettings);
    final state = _buildState(settingsService: settings);
    await state.initialize();

    final firstSync = state.syncNow();
    expect(state.isSyncing, isTrue);

    final secondSync = await state.syncNow();
    expect(secondSync, isFalse);

    connectivity.complete(['none']);

    expect(await firstSync, isFalse);
    expect(state.isSyncing, isFalse);
    expect(state.connectionStatus, ConnectionStatus.unreachable);
  });

  test('dispose makes websocket and share events inert', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService()..queue = ['https://youtu.be/abc123'];
    final websocket = FakeWebsocketService();
    final share = FakeShareIntentService();
    final state = _buildState(
      settingsService: settings,
      apiService: api,
      websocketService: websocket,
      shareIntentService: share,
    );
    await state.initialize();

    final initialQueue = List.of(state.downloadQueue);
    state.dispose();

    websocket.controller.add(
      const WsEvent({
        'type': 'download_progress',
        'url': 'https://youtu.be/new456',
        'status': 'downloading',
        'percentage': 50,
      }),
    );
    share.controller.add(['https://youtu.be/shared789']);
    await pumpEventQueue();

    expect(state.downloadQueue, initialQueue);
    expect(state.pendingShareUrls, isEmpty);
    expect(settings.pendingShareUrls, isEmpty);
    expect(websocket.connected, isFalse);
  });

  test(
    'saving a different server clears the session but keeps the new server',
    () async {
      final settings = FakeSettingsService(
        settings: const AppSettings(
          serverUrl: 'http://old.local',
          username: 'demo',
          password: 'secret',
          userId: 'u1',
          sessionCookie: 'cookie',
          storagePath: 'test-storage',
        ),
      );
      final state = _buildState(settingsService: settings);
      await state.initialize();

      await state.saveSettings(
        state.settings.copyWith(
          serverUrl: 'http://new.local',
          username: 'demo',
          password: 'secret',
        ),
      );

      expect(state.isAuthenticated, isFalse);
      expect(state.settings.serverUrl, 'http://new.local');
      expect(state.settings.userId, isEmpty);
      expect(state.connectionStatus, ConnectionStatus.signedOut);
    },
  );
}
