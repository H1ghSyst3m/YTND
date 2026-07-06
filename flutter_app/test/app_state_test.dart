import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/services/api_service.dart';
import 'package:ytnd/services/sync_service.dart';
import 'package:ytnd/services/websocket_service.dart';
import 'package:ytnd/state/app_state.dart';

import 'fakes.dart';

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
  test('initialize keeps server editable when saved server is unreachable',
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
  });

  test('initial shared links are persisted while signed out', () async {
    final settings = FakeSettingsService();
    final share =
        FakeShareIntentService(initialUrls: const ['https://youtu.be/abc123']);
    final state =
        _buildState(settingsService: settings, shareIntentService: share);

    await state.initialize();

    expect(state.pendingShareUrls, ['https://youtu.be/abc123']);
    expect(settings.pendingShareUrls, ['https://youtu.be/abc123']);
    expect(state.connectionStatus, ConnectionStatus.setupRequired);
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

  test('failed login keeps the edited server saved and reachable', () async {
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
  });

  test('websocket download errors do not expose raw backend text', () async {
    final settings = FakeSettingsService(
      settings: const AppSettings(
        serverUrl: 'http://ytnd.local:8080',
        username: 'demo',
        password: 'secret',
        userId: 'u1',
        sessionCookie: 'cookie',
        storagePath: 'test-storage',
      ),
    );
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

  test('saving a different server clears the session but keeps the new server',
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
          serverUrl: 'http://new.local', username: 'demo', password: 'secret'),
    );

    expect(state.isAuthenticated, isFalse);
    expect(state.settings.serverUrl, 'http://new.local');
    expect(state.settings.userId, isEmpty);
    expect(state.connectionStatus, ConnectionStatus.signedOut);
  });
}
