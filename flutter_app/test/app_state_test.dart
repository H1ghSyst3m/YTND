import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/models/download_queue_item.dart';
import 'package:ytnd/models/song.dart';
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

void _mockConnectivity(
  TestWidgetsFlutterBinding binding,
  List<String> results,
) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _connectivityChannel,
    (call) async {
      expect(call.method, 'check');
      return results;
    },
  );
  addTearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _connectivityChannel,
      null,
    );
  });
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

  test('dismissed connection notice reappears after status changes', () async {
    final settings = FakeSettingsService();
    final state = _buildState(settingsService: settings);
    await state.initialize();

    expect(state.shouldShowConnectionNotice, isTrue);

    await state.dismissConnectionNotice();

    expect(state.shouldShowConnectionNotice, isFalse);
    expect(settings.dismissedConnectionNoticeKey, state.connectionNoticeKey);

    await state.saveSettings(
      state.settings.copyWith(
        serverUrl: 'http://ytnd.local:8080',
        username: 'demo',
        password: 'secret',
      ),
    );

    expect(state.connectionStatus, ConnectionStatus.signedOut);
    expect(state.shouldShowConnectionNotice, isTrue);
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

  test('library status separates server availability from downloads', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_local_status');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    await File(p.join(temp.path, 'downloaded.opus')).writeAsString('audio');

    final songs = const [
      Song(
        title: 'Server only',
        artist: 'Demo',
        filename: 'server-only.opus',
        fileAvailable: true,
      ),
      Song(
        title: 'Downloaded',
        artist: 'Demo',
        filename: 'downloaded.opus',
        fileAvailable: true,
      ),
      Song(
        title: 'Unavailable',
        artist: 'Demo',
        filename: 'missing.opus',
        fileAvailable: false,
      ),
    ];
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(storagePath: temp.path),
    );
    final api = FakeApiService()..songs = songs;
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(state.isSongAvailable(songs[0]), isTrue);
    expect(state.isSongDownloaded(songs[0]), isFalse);
    expect(state.isSongAvailable(songs[1]), isTrue);
    expect(state.isSongDownloaded(songs[1]), isTrue);
    expect(state.isSongAvailable(songs[2]), isFalse);
    expect(state.isSongDownloaded(songs[2]), isFalse);
  });

  test('unsafe song filenames never count as downloaded', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_unsafe_status');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final absolute = File(p.join(temp.path, 'absolute.opus'));
    await absolute.writeAsString('audio');

    final songs = [
      const Song(
        title: 'Parent segment',
        artist: 'Demo',
        filename: '../escape.opus',
        fileAvailable: true,
      ),
      Song(
        title: 'Absolute path',
        artist: 'Demo',
        filename: absolute.path,
        fileAvailable: true,
      ),
      const Song(
        title: 'Empty filename',
        artist: 'Demo',
        filename: '',
        fileAvailable: true,
      ),
    ];
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(storagePath: temp.path),
    );
    final api = FakeApiService()..songs = songs;
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    for (final song in songs) {
      expect(state.isSongDownloaded(song), isFalse);
    }
  });

  test('startup sync runs after saved-session restore when enabled', () async {
    _mockConnectivity(binding, ['wifi']);
    final temp = await Directory.systemTemp.createTemp('ytnd_startup_sync');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(
        syncOnStartup: true,
        storagePath: temp.path,
      ),
    );
    final api = FakeApiService()
      ..songs = const [
        Song(
          title: 'Startup Song',
          artist: 'Demo',
          date: '2026-01-01',
          fileAvailable: false,
        ),
      ];
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(state.isAuthenticated, isTrue);
    expect(api.fetchSongsCalls, 3);
    expect(state.latestSyncSummary, isNotNull);
    expect(state.latestSyncSummary!.message, 'Sync finished');
  });

  test('startup sync does not run when disabled', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService();
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(api.fetchSongsCalls, 1);
    expect(state.latestSyncSummary, isNull);
  });

  test('startup sync does not run while signed out', () async {
    final settings = FakeSettingsService(
      settings: const AppSettings(
        serverUrl: 'http://ytnd.local:8080',
        username: 'demo',
        password: 'secret',
        syncOnStartup: true,
        storagePath: 'test-storage',
      ),
    );
    final api = FakeApiService();
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(state.connectionStatus, ConnectionStatus.signedOut);
    expect(api.fetchSongsCalls, 0);
    expect(state.latestSyncSummary, isNull);
  });

  test('startup sync does not run for manual sign-in', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_manual_sign_in');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final settings = FakeSettingsService(
      settings: AppSettings(
        serverUrl: 'http://ytnd.local:8080',
        username: 'demo',
        password: 'secret',
        syncOnStartup: true,
        storagePath: temp.path,
      ),
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
    expect(api.fetchSongsCalls, 1);
    expect(state.latestSyncSummary, isNull);
  });

  test('startup sync does not run after unauthorized restore', () async {
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(syncOnStartup: true),
    );
    final api = FakeApiService()..authorized = false;
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(state.isAuthenticated, isFalse);
    expect(state.connectionStatus, ConnectionStatus.unauthorized);
    expect(api.fetchSongsCalls, 0);
    expect(state.latestSyncSummary, isNull);
  });

  test('startup sync respects WiFi-only on mobile networks', () async {
    _mockConnectivity(binding, ['mobile']);
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(
        syncOnStartup: true,
        syncWifiOnly: true,
      ),
    );
    final api = FakeApiService();
    final state = _buildState(settingsService: settings, apiService: api);

    await state.initialize();

    expect(api.fetchSongsCalls, 1);
    expect(state.latestSyncSummary, isNotNull);
    expect(state.latestSyncSummary!.success, isFalse);
    expect(state.latestSyncSummary!.message, 'Startup sync skipped: WiFi required.');
  });

  test('sync preferences persist immediately and survive initialize', () async {
    _mockConnectivity(binding, ['wifi']);
    final temp = await Directory.systemTemp.createTemp('ytnd_sync_prefs');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(storagePath: temp.path),
    );
    final background = FakeBackgroundSyncService();
    final state = _buildState(
      settingsService: settings,
      backgroundSyncService: background,
    );
    await state.initialize();

    final saved = await state.updateSyncPreferences(
      syncIntervalHours: 2,
      syncWifiOnly: true,
      syncOnStartup: true,
    );

    expect(saved, isTrue);
    expect(settings.settings.syncIntervalHours, 2);
    expect(settings.settings.syncWifiOnly, isTrue);
    expect(settings.settings.syncOnStartup, isTrue);
    expect(settings.settings.userId, 'u1');
    expect(settings.settings.storagePath, temp.path);
    expect(background.configured, isTrue);

    final restored = _buildState(settingsService: settings);
    await restored.initialize();

    expect(restored.settings.syncIntervalHours, 2);
    expect(restored.settings.syncWifiOnly, isTrue);
    expect(restored.settings.syncOnStartup, isTrue);
    expect(restored.isAuthenticated, isTrue);
  });

  test('logout clears session but preserves sync and storage settings', () async {
    _mockConnectivity(binding, ['wifi']);
    final temp = await Directory.systemTemp.createTemp('ytnd_logout_settings');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(
        storagePath: temp.path,
        syncIntervalHours: 6,
        syncWifiOnly: true,
        syncOnStartup: true,
      ),
    );
    final state = _buildState(settingsService: settings);
    await state.initialize();

    await state.logout();

    expect(settings.settings.userId, isEmpty);
    expect(settings.settings.sessionCookie, isEmpty);
    expect(settings.settings.storagePath, temp.path);
    expect(settings.settings.syncIntervalHours, 6);
    expect(settings.settings.syncWifiOnly, isTrue);
    expect(settings.settings.syncOnStartup, isTrue);
    expect(state.connectionStatus, ConnectionStatus.signedOut);
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

  test('download errors create a fresh dismissible notice', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService()..queue = ['https://youtu.be/abc123'];
    final websocket = FakeWebsocketService();
    final state = _buildState(
      settingsService: settings,
      apiService: api,
      websocketService: websocket,
    );
    await state.initialize();
    await state.dismissConnectionNotice();

    expect(state.shouldShowConnectionNotice, isFalse);

    websocket.controller.add(
      const WsEvent({
        'type': 'download_error',
        'error': 'network timeout',
      }),
    );
    await pumpEventQueue();

    expect(state.shouldShowConnectionNotice, isTrue);
    expect(
      state.lastErrorMessage,
      'Download failed. Check your connection and try again.',
    );
  });

  test('websocket progress merges normalized queue URLs', () async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService()
      ..queue = [
        'https://www.youtube.com/watch?v=abc123&list=context-playlist',
      ];
    final websocket = FakeWebsocketService();
    final state = _buildState(
      settingsService: settings,
      apiService: api,
      websocketService: websocket,
    );
    await state.initialize();

    expect(state.downloadQueue, hasLength(1));
    expect(state.queuedQueue, hasLength(1));

    websocket.controller.add(
      const WsEvent({
        'type': 'download_progress',
        'url': 'https://youtu.be/abc123?si=share',
        'status': 'downloading',
        'percentage': 42,
      }),
    );
    await pumpEventQueue();

    expect(state.downloadQueue, hasLength(1));
    expect(state.inProgressQueue, hasLength(1));
    expect(state.queuedQueue, isEmpty);
    expect(state.inProgressQueue.single.percentage, 42);
  });

  test('failed websocket progress appears in failed queue section', () async {
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
        'error': 'video unavailable',
      }),
    );
    await pumpEventQueue();

    expect(state.failedQueue, hasLength(1));
    expect(state.queuedQueue, isEmpty);
    expect(
      state.failedQueue.single.error,
      'Download failed. This video is unavailable.',
    );
  });

  test('retrying failed queue item refreshes it as queued', () async {
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
        'url': 'https://www.youtube.com/watch?v=abc123&list=context',
        'status': 'error',
        'error': 'video unavailable',
      }),
    );
    await pumpEventQueue();

    expect(state.failedQueue, hasLength(1));

    final retried = await state.retryFailedDownload(state.failedQueue.single);
    await state.refreshQueue();

    expect(retried, isTrue);
    expect(state.failedQueue, isEmpty);
    expect(state.queuedQueue, hasLength(1));
    expect(state.queuedQueue.single.status, DownloadStatus.pending);
    expect(state.queuedQueue.single.error, isNull);
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
    expect(state.lastErrorMessage, 'Sync skipped: no network access.');
    expect(state.connectionMessage, 'Sync skipped: no network access.');
  });

  test('syncNow stores a summary without bloating connection copy', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _connectivityChannel,
      (call) async {
        expect(call.method, 'check');
        return ['wifi'];
      },
    );
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _connectivityChannel,
        null,
      );
    });

    final temp = await Directory.systemTemp.createTemp('ytnd_app_state_sync');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(storagePath: temp.path),
    );
    final api = FakeApiService()
      ..songs = const [
        Song(
          title: 'Dreamscape',
          artist: 'Aural Drift',
          date: '2025-05-10',
          fileAvailable: false,
        ),
      ];
    final state = _buildState(settingsService: settings, apiService: api);
    await state.initialize();

    final synced = await state.syncNow();

    expect(synced, isTrue);
    expect(state.latestSyncSummary, isNotNull);
    expect(state.latestSyncSummary!.remoteCount, 1);
    expect(state.latestSyncSummary!.downloaded, 0);
    expect(state.statusMessage, 'Sync finished');
    expect(state.statusMessage, isNot(contains('server songs')));
    expect(state.connectionMessage, 'http://ytnd.local:8080');
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

  test('account saves preserve sync and storage settings', () async {
    _mockConnectivity(binding, ['wifi']);
    final temp = await Directory.systemTemp.createTemp('ytnd_account_save');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(
        storagePath: temp.path,
        syncIntervalHours: 12,
        syncWifiOnly: true,
        syncOnStartup: true,
      ),
    );
    final state = _buildState(settingsService: settings);
    await state.initialize();

    await state.saveSettings(
      state.settings.copyWith(
        serverUrl: 'http://new.local',
        username: 'new-user',
        password: 'new-secret',
      ),
    );

    expect(settings.settings.serverUrl, 'http://new.local');
    expect(settings.settings.username, 'new-user');
    expect(settings.settings.userId, isEmpty);
    expect(settings.settings.sessionCookie, isEmpty);
    expect(settings.settings.storagePath, temp.path);
    expect(settings.settings.syncIntervalHours, 12);
    expect(settings.settings.syncWifiOnly, isTrue);
    expect(settings.settings.syncOnStartup, isTrue);
  });
}
