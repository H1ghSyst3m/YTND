import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_settings.dart';
import '../models/download_queue_item.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/background_sync_service.dart';
import '../services/settings_service.dart';
import '../services/share_intent_service.dart';
import '../services/sync_service.dart';
import '../services/websocket_service.dart';

enum ConnectionStatus {
  setupRequired,
  signedOut,
  checking,
  connected,
  unreachable,
  unauthorized,
}

class AppState extends ChangeNotifier {
  AppState({
    required SettingsService settingsService,
    required ApiService apiService,
    required SyncService syncService,
    required BackgroundSyncService backgroundSyncService,
    required WebsocketService websocketService,
    required ShareIntentService shareIntentService,
  })  : _settingsService = settingsService,
        _apiService = apiService,
        _syncService = syncService,
        _backgroundSyncService = backgroundSyncService,
        _websocketService = websocketService,
        _shareIntentService = shareIntentService;

  final SettingsService _settingsService;
  final ApiService _apiService;
  final SyncService _syncService;
  final BackgroundSyncService _backgroundSyncService;
  final WebsocketService _websocketService;
  final ShareIntentService _shareIntentService;

  AppSettings _settings = const AppSettings();
  List<Song> _songs = const [];
  List<DownloadQueueItem> _downloadQueue = const [];
  List<String> _pendingShareUrls = const [];
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<List<String>>? _shareSubscription;

  bool _initialized = false;
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _isSavingSettings = false;
  bool _isSyncing = false;
  bool _isQueueProcessing = false;
  bool _isLibraryLoading = false;
  bool _isQueueLoading = false;
  bool _isAddingToQueue = false;
  bool _disposed = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.setupRequired;
  String _statusMessage = '';
  String? _lastErrorMessage;
  int _queueFocusVersion = 0;

  AppSettings get settings => _settings;
  List<Song> get songs => _songs;
  List<DownloadQueueItem> get downloadQueue => _downloadQueue;
  List<String> get pendingShareUrls => _pendingShareUrls;
  bool get initialized => _initialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get isAuthenticating => _isAuthenticating;
  bool get isSavingSettings => _isSavingSettings;
  bool get isSyncing => _isSyncing;
  bool get isQueueProcessing => _isQueueProcessing;
  bool get isLibraryLoading => _isLibraryLoading;
  bool get isQueueLoading => _isQueueLoading;
  bool get isAddingToQueue => _isAddingToQueue;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String get statusMessage => _statusMessage;
  String? get lastErrorMessage => _lastErrorMessage;
  int get pendingShareCount => _pendingShareUrls.length;
  int get queueFocusVersion => _queueFocusVersion;
  bool get hasServerProfile => _settings.serverUrl.trim().isNotEmpty;
  bool get hasSavedSession =>
      _settings.userId.isNotEmpty && _settings.sessionCookie.isNotEmpty;

  String? get pendingShareUrl =>
      _pendingShareUrls.isEmpty ? null : _pendingShareUrls.first;

  String get connectionTitle {
    switch (_connectionStatus) {
      case ConnectionStatus.setupRequired:
        return 'Server setup required';
      case ConnectionStatus.signedOut:
        return 'Signed out';
      case ConnectionStatus.checking:
        return 'Connecting';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.unreachable:
        return 'Server unreachable';
      case ConnectionStatus.unauthorized:
        return 'Session expired';
    }
  }

  String get connectionMessage {
    switch (_connectionStatus) {
      case ConnectionStatus.setupRequired:
        return 'Add your YTND server and sign in from Settings.';
      case ConnectionStatus.signedOut:
        return 'Sign in to sync your library and queue.';
      case ConnectionStatus.checking:
        return 'Checking your YTND server...';
      case ConnectionStatus.connected:
        return _settings.serverUrl.isEmpty ? 'Ready' : _settings.serverUrl;
      case ConnectionStatus.unreachable:
        return _lastErrorMessage ??
            'The server could not be reached. You can edit it in Settings.';
      case ConnectionStatus.unauthorized:
        return 'Sign in again or update the server details in Settings.';
    }
  }

  String? consumePendingShareUrl() {
    if (_pendingShareUrls.isEmpty) {
      return null;
    }
    final value = _pendingShareUrls.first;
    _pendingShareUrls = _pendingShareUrls.skip(1).toList(growable: false);
    unawaited(_settingsService.savePendingShareUrls(_pendingShareUrls));
    notifyListeners();
    return value;
  }

  Future<void> initialize() async {
    try {
      _settings = await _settingsService.load();
      _pendingShareUrls = await _settingsService.loadPendingShareUrls();

      if (_settings.storagePath == AppSettings.defaultStoragePath) {
        await _ensureDefaultStoragePathExists();
      }

      _listenForSharedUrls();
      final initialUrls = await _shareIntentService.getInitialSharedUrls();
      if (initialUrls.isNotEmpty) {
        await _receiveSharedUrls(initialUrls);
      }

      await _restoreSession();
    } catch (e, st) {
      debugPrint('App initialization failed: $e\n$st');
      _lastErrorMessage = _messageFor(e, 'YTND could not finish startup.');
      _statusMessage = _lastErrorMessage!;
      _connectionStatus = hasServerProfile
          ? ConnectionStatus.unreachable
          : ConnectionStatus.setupRequired;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (_isAuthenticating) {
      return false;
    }

    _isAuthenticating = true;
    _connectionStatus = ConnectionStatus.checking;
    _lastErrorMessage = null;
    _statusMessage = 'Signing in...';
    notifyListeners();

    try {
      final normalizedServerUrl = normalizeServerUrl(serverUrl);
      final normalizedUsername = username.trim();
      final accountChanged = normalizedServerUrl != _settings.serverUrl ||
          normalizedUsername != _settings.username ||
          password != _settings.password;

      if (accountChanged) {
        _isAuthenticated = false;
        _songs = const [];
        _downloadQueue = const [];
        _isQueueProcessing = false;
        await _disconnectWebsocket();
        await _backgroundSyncService.cancel();
        await _settingsService.clearSession();
      }

      _settings = _settings.copyWith(
        serverUrl: normalizedServerUrl,
        username: normalizedUsername,
        password: password,
        userId: accountChanged ? '' : _settings.userId,
        sessionCookie: accountChanged ? '' : _settings.sessionCookie,
      );
      await _settingsService.save(_settings);

      final (userId, cookieHeader) = await _apiService.login(
        serverUrl: normalizedServerUrl,
        username: normalizedUsername,
        password: password,
      );

      _settings = _settings.copyWith(
        serverUrl: normalizedServerUrl,
        username: normalizedUsername,
        password: password,
        userId: userId,
        sessionCookie: cookieHeader,
      );
      await _settingsService.save(_settings);

      _isAuthenticated = true;
      _connectionStatus = ConnectionStatus.connected;
      _statusMessage = 'Connected to YTND';
      await _loadInitialData();
      await _configureBackgroundSync();
      await _connectWebsocket();
      await retryPendingShareUrls();
      return true;
    } catch (e, st) {
      debugPrint('Login failed: $e\n$st');
      _isAuthenticated = false;
      _connectionStatus = _statusForError(e);
      _lastErrorMessage = _messageFor(e, 'Could not sign in.');
      _statusMessage = _lastErrorMessage!;
      notifyListeners();
      rethrow;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _songs = const [];
    _downloadQueue = const [];
    _statusMessage = 'Signed out';
    _lastErrorMessage = null;
    _isQueueProcessing = false;
    _connectionStatus = hasServerProfile
        ? ConnectionStatus.signedOut
        : ConnectionStatus.setupRequired;
    _settings = _settings.copyWith(userId: '', sessionCookie: '');
    await _settingsService.save(_settings);
    await _settingsService.clearSession();
    await _backgroundSyncService.cancel();
    await _disconnectWebsocket();
    notifyListeners();
  }

  Future<bool> saveSettings(AppSettings newSettings) async {
    if (_isSavingSettings) {
      return false;
    }

    _isSavingSettings = true;
    _lastErrorMessage = null;
    notifyListeners();

    try {
      final normalizedServerUrl = newSettings.serverUrl.trim().isEmpty
          ? ''
          : normalizeServerUrl(newSettings.serverUrl);
      var next = newSettings.copyWith(serverUrl: normalizedServerUrl);
      final accountChanged = normalizedServerUrl != _settings.serverUrl ||
          next.username != _settings.username ||
          next.password != _settings.password;

      if (accountChanged) {
        next = next.copyWith(userId: '', sessionCookie: '');
        _isAuthenticated = false;
        _songs = const [];
        _downloadQueue = const [];
        _isQueueProcessing = false;
        await _disconnectWebsocket();
        await _backgroundSyncService.cancel();
        await _settingsService.clearSession();
      }

      _settings = next;
      await _settingsService.save(_settings);
      if (_isAuthenticated) {
        await _configureBackgroundSync();
        await _connectWebsocket();
      }
      _connectionStatus = _statusAfterLocalSave(accountChanged);
      _statusMessage = accountChanged
          ? 'Server settings saved. Sign in to connect.'
          : 'Settings saved';
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Saving settings failed: $e\n$st');
      _lastErrorMessage = _messageFor(e, 'Could not save settings.');
      _statusMessage = _lastErrorMessage!;
      notifyListeners();
      rethrow;
    } finally {
      _isSavingSettings = false;
      notifyListeners();
    }
  }

  Future<bool> retryConnection() async {
    if (!hasServerProfile) {
      _connectionStatus = ConnectionStatus.setupRequired;
      _statusMessage = 'Add your server details in Settings.';
      notifyListeners();
      return false;
    }
    if (!hasSavedSession) {
      _connectionStatus = ConnectionStatus.signedOut;
      _statusMessage = 'Sign in to connect.';
      notifyListeners();
      return false;
    }
    await _restoreSession();
    notifyListeners();
    return _connectionStatus == ConnectionStatus.connected;
  }

  String? coverUrlFor(Song song) {
    if (!song.coverAvailable || song.coverFilename == null) {
      return null;
    }
    return _apiService
        .coverUrl(
          serverUrl: _settings.serverUrl,
          userId: _settings.userId,
          filename: song.coverFilename!,
        )
        .toString();
  }

  Future<bool> refreshSongs() async {
    if (!_isAuthenticated) {
      _statusMessage = 'Sign in to load your library.';
      notifyListeners();
      return false;
    }

    _isLibraryLoading = true;
    _lastErrorMessage = null;
    notifyListeners();

    try {
      _songs = await _apiService.fetchSongs(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
      );
      _connectionStatus = ConnectionStatus.connected;
      _statusMessage = 'Library updated';
      return true;
    } catch (e, st) {
      debugPrint('Refresh songs failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not refresh the library.');
      return false;
    } finally {
      _isLibraryLoading = false;
      notifyListeners();
    }
  }

  Future<bool> refreshQueue() async {
    if (!_isAuthenticated) {
      _statusMessage = 'Sign in to load the queue.';
      notifyListeners();
      return false;
    }

    _isQueueLoading = true;
    _lastErrorMessage = null;
    notifyListeners();

    try {
      final urls = await _apiService.fetchQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
      );
      final serverUrlSet = urls.toSet();
      final inFlight = _downloadQueue
          .where(
            (item) =>
                (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.processing) &&
                !serverUrlSet.contains(item.url),
          )
          .toList();
      final currentByUrl = {for (final item in _downloadQueue) item.url: item};
      _downloadQueue = [
        ...inFlight,
        ...urls.map((url) => currentByUrl[url] ?? DownloadQueueItem(url: url)),
      ];
      _connectionStatus = ConnectionStatus.connected;
      return true;
    } catch (e, st) {
      debugPrint('Refresh queue failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not refresh the queue.');
      return false;
    } finally {
      _isQueueLoading = false;
      notifyListeners();
    }
  }

  Future<bool> syncNow() async {
    if (_isSyncing || !_isAuthenticated) {
      return false;
    }

    _isSyncing = true;
    _statusMessage = 'Sync in progress...';
    _lastErrorMessage = null;
    notifyListeners();

    try {
      final connected = await _hasNetwork();
      if (!connected) {
        _statusMessage = 'Sync skipped: no network access.';
        _connectionStatus = ConnectionStatus.unreachable;
        notifyListeners();
        return false;
      }

      final permissionGranted = await _requestStoragePermissions();
      if (!permissionGranted) {
        _statusMessage = 'Sync skipped: storage permission denied.';
        return false;
      }
      final result = await _syncService.sync(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        storagePath: _settings.storagePath,
      );
      await refreshSongs();
      _connectionStatus = ConnectionStatus.connected;
      _statusMessage =
          'Sync finished: ${result.remoteCount} server songs, ${result.downloaded} downloaded, ${result.deleted} removed locally.';
      return true;
    } catch (e, st) {
      debugPrint('Sync failed: $e\n$st');
      await _handleOperationFailure(e, 'Sync failed.');
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> deleteSong(Song song) async {
    if (!_isAuthenticated) {
      return false;
    }

    try {
      await _syncService.deleteSongOnServerAndLocal(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        storagePath: _settings.storagePath,
        song: song,
      );

      await refreshSongs();
      _statusMessage = 'Deleted "${song.title}"';
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Delete failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not delete this song.');
      return false;
    }
  }

  Future<bool> redownloadSong(Song song, {bool force = false}) async {
    if (!_isAuthenticated) {
      return false;
    }

    try {
      await _apiService.redownloadSong(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        song: song,
        cookieHeader: _settings.sessionCookie,
        force: force,
      );
      _statusMessage = 'Queued "${song.title}" for redownload';
      _queueFocusVersion++;
      await refreshQueue();
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Redownload failed: $e\n$st');
      await _handleOperationFailure(
          e, 'Could not queue this song for redownload.');
      return false;
    }
  }

  Future<bool> addUrlsToQueue(List<String> urls,
      {bool fromShare = false}) async {
    final normalized = _uniqueUrls(urls);
    if (normalized.isEmpty) {
      _statusMessage = 'No valid YouTube links found.';
      notifyListeners();
      return false;
    }

    if (!_isAuthenticated) {
      await _storePendingShareUrls(normalized);
      _statusMessage = 'Saved ${normalized.length} link(s) until you sign in.';
      _queueFocusVersion++;
      notifyListeners();
      return false;
    }

    _isAddingToQueue = true;
    _lastErrorMessage = null;
    notifyListeners();

    try {
      await _apiService.addToQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        urls: normalized,
      );
      _statusMessage = 'Added ${normalized.length} link(s) to the queue';
      _queueFocusVersion++;
      await refreshQueue();
      return true;
    } catch (e, st) {
      debugPrint('Add queue failed: $e\n$st');
      if (fromShare) {
        await _storePendingShareUrls(normalized);
      }
      await _handleOperationFailure(e, 'Could not add the link to the queue.');
      return false;
    } finally {
      _isAddingToQueue = false;
      notifyListeners();
    }
  }

  Future<bool> retryPendingShareUrls() async {
    if (_pendingShareUrls.isEmpty) {
      return true;
    }
    if (!_isAuthenticated) {
      _statusMessage =
          'Sign in to add ${_pendingShareUrls.length} pending link(s).';
      notifyListeners();
      return false;
    }

    final urls = List<String>.of(_pendingShareUrls);
    _isAddingToQueue = true;
    notifyListeners();

    try {
      await _apiService.addToQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        urls: urls,
      );
      _pendingShareUrls = const [];
      await _settingsService.savePendingShareUrls(_pendingShareUrls);
      _statusMessage = 'Added ${urls.length} pending link(s) to the queue';
      _queueFocusVersion++;
      await refreshQueue();
      return true;
    } catch (e, st) {
      debugPrint('Retry pending shares failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not add pending links yet.');
      return false;
    } finally {
      _isAddingToQueue = false;
      notifyListeners();
    }
  }

  Future<bool> removeUrlFromQueue(String url) async {
    if (!_isAuthenticated) {
      return false;
    }
    try {
      await _apiService.removeFromQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        urls: [url],
      );
      _statusMessage = 'Removed link from the queue';
      await refreshQueue();
      return true;
    } catch (e, st) {
      debugPrint('Remove queue item failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not remove that link.');
      return false;
    }
  }

  Future<bool> clearQueue() async {
    if (!_isAuthenticated) {
      return false;
    }
    try {
      await _apiService.removeFromQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
      );
      _statusMessage = 'Queue cleared';
      await refreshQueue();
      return true;
    } catch (e, st) {
      debugPrint('Clear queue failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not clear the queue.');
      return false;
    }
  }

  Future<bool> processQueue() async {
    if (!_isAuthenticated || _isQueueProcessing || _downloadQueue.isEmpty) {
      return false;
    }
    try {
      final queued = await _apiService.processQueue(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
      );
      if (queued > 0) {
        _isQueueProcessing = true;
        _statusMessage = 'Started processing $queued item(s)';
      } else {
        _statusMessage = 'No items to process';
      }
      notifyListeners();
      return queued > 0;
    } catch (e, st) {
      debugPrint('Process queue failed: $e\n$st');
      await _handleOperationFailure(e, 'Could not start the queue.');
      return false;
    }
  }

  void dismissError() {
    _lastErrorMessage = null;
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    if (!hasServerProfile) {
      _isAuthenticated = false;
      _connectionStatus = ConnectionStatus.setupRequired;
      _statusMessage = 'Add your server details in Settings.';
      return;
    }
    if (!hasSavedSession) {
      _isAuthenticated = false;
      _connectionStatus = ConnectionStatus.signedOut;
      _statusMessage = 'Sign in to connect.';
      return;
    }

    _isAuthenticated = true;
    _connectionStatus = ConnectionStatus.checking;
    _statusMessage = 'Checking saved session...';
    notifyListeners();

    try {
      final authorized = await _apiService.ping(
        serverUrl: _settings.serverUrl,
        cookieHeader: _settings.sessionCookie,
      );
      if (!authorized) {
        await _expireSession('Your session expired. Sign in again.');
        return;
      }
      _isAuthenticated = true;
      _connectionStatus = ConnectionStatus.connected;
      _statusMessage = 'Connected to YTND';
      await _loadInitialData();
      await _configureBackgroundSync();
      await _connectWebsocket();
      await retryPendingShareUrls();
    } catch (e, st) {
      debugPrint('Session restore failed: $e\n$st');
      _isAuthenticated = hasSavedSession;
      _connectionStatus = _statusForError(e);
      _lastErrorMessage = _messageFor(e, 'Could not reach your YTND server.');
      _statusMessage = _lastErrorMessage!;
      await _backgroundSyncService.cancel();
    }
  }

  Future<void> _loadInitialData() async {
    await refreshSongs();
    await refreshQueue();
  }

  Future<void> _receiveSharedUrls(List<String> urls) async {
    if (_disposed) {
      return;
    }
    final normalized = _uniqueUrls(urls);
    if (normalized.isEmpty) {
      return;
    }
    _queueFocusVersion++;
    await addUrlsToQueue(normalized, fromShare: true);
  }

  void _listenForSharedUrls() {
    _shareSubscription ??= _shareIntentService.sharedUrlStream.listen(
      (urls) => unawaited(_receiveSharedUrls(urls)),
      onError: (Object e, StackTrace st) {
        debugPrint('Share intent stream failed: $e\n$st');
      },
    );
  }

  Future<void> _storePendingShareUrls(List<String> urls) async {
    final combined = _uniqueUrls([..._pendingShareUrls, ...urls]);
    _pendingShareUrls = combined;
    await _settingsService.savePendingShareUrls(_pendingShareUrls);
  }

  List<String> _uniqueUrls(Iterable<String> urls) {
    final result = <String>[];
    final seen = <String>{};
    for (final url in urls) {
      final value = url.trim();
      if (value.isNotEmpty && seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  Future<void> _handleOperationFailure(
      Object error, String fallbackMessage) async {
    final message = _messageFor(error, fallbackMessage);
    _lastErrorMessage = message;
    _statusMessage = message;
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.unauthorized:
        case ApiErrorKind.forbidden:
          await _expireSession(message);
          return;
        case ApiErrorKind.network:
        case ApiErrorKind.timeout:
          _connectionStatus = ConnectionStatus.unreachable;
          break;
        case ApiErrorKind.invalidRequest:
        case ApiErrorKind.server:
        case ApiErrorKind.invalidResponse:
        case ApiErrorKind.conflict:
        case ApiErrorKind.notFound:
        case ApiErrorKind.unknown:
          break;
      }
    }
    notifyListeners();
  }

  Future<void> _expireSession(String message) async {
    _isAuthenticated = false;
    _isQueueProcessing = false;
    _connectionStatus = ConnectionStatus.unauthorized;
    _lastErrorMessage = message;
    _statusMessage = message;
    _settings = _settings.copyWith(userId: '', sessionCookie: '');
    await _settingsService.save(_settings);
    await _settingsService.clearSession();
    await _backgroundSyncService.cancel();
    await _disconnectWebsocket();
    notifyListeners();
  }

  ConnectionStatus _statusForError(Object error) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.unauthorized:
        case ApiErrorKind.forbidden:
          return ConnectionStatus.unauthorized;
        case ApiErrorKind.network:
        case ApiErrorKind.timeout:
          return ConnectionStatus.unreachable;
        case ApiErrorKind.invalidRequest:
          return hasServerProfile
              ? ConnectionStatus.signedOut
              : ConnectionStatus.setupRequired;
        case ApiErrorKind.server:
        case ApiErrorKind.invalidResponse:
        case ApiErrorKind.conflict:
        case ApiErrorKind.notFound:
        case ApiErrorKind.unknown:
          return hasServerProfile
              ? ConnectionStatus.unreachable
              : ConnectionStatus.setupRequired;
      }
    }
    return hasServerProfile
        ? ConnectionStatus.unreachable
        : ConnectionStatus.setupRequired;
  }

  ConnectionStatus _statusAfterLocalSave(bool accountChanged) {
    if (!hasServerProfile) {
      return ConnectionStatus.setupRequired;
    }
    if (accountChanged) {
      return ConnectionStatus.signedOut;
    }
    return _isAuthenticated
        ? ConnectionStatus.connected
        : ConnectionStatus.signedOut;
  }

  String _messageFor(Object error, String fallbackMessage) {
    if (error is ApiException) {
      return error.message;
    }
    return fallbackMessage;
  }

  Future<void> _configureBackgroundSync() async {
    if (!_isAuthenticated) {
      await _backgroundSyncService.cancel();
      return;
    }
    await _backgroundSyncService.configure(_settings);
  }

  Future<void> _connectWebsocket() async {
    await _disconnectWebsocket();
    if (!_isAuthenticated) {
      return;
    }
    _wsSubscription = _websocketService.events.listen(_handleWsEvent);
    await _websocketService.connect(
      serverUrl: _settings.serverUrl,
      cookieHeader: _settings.sessionCookie,
    );
  }

  Future<void> _disconnectWebsocket() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _websocketService.disconnect();
  }

  void _handleWsEvent(WsEvent event) {
    if (_disposed) {
      return;
    }
    if (event.userId != null && event.userId != _settings.userId) {
      return;
    }
    switch (event.type) {
      case 'download_progress':
        final url = event.url;
        if (url == null || url.isEmpty) {
          return;
        }
        final existingIndex =
            _downloadQueue.indexWhere((item) => item.url == url);
        final index =
            existingIndex >= 0 ? existingIndex : _downloadQueue.length;
        if (existingIndex < 0) {
          _downloadQueue = [..._downloadQueue, DownloadQueueItem(url: url)];
        }
        final data = event.data;
        final status = _parseDownloadStatus(data['status']?.toString());
        final error = status == DownloadStatus.error
            ? _friendlyDownloadError(data['error'])
            : null;
        final updated = _downloadQueue[index].copyWith(
          status: status,
          title: data['title']?.toString(),
          artist: data['artist']?.toString(),
          id: data['id']?.toString(),
          percentage:
              num.tryParse(data['percentage']?.toString() ?? '')?.toDouble(),
          downloadedBytes:
              num.tryParse(data['downloaded_bytes']?.toString() ?? '')?.toInt(),
          totalBytes:
              num.tryParse(data['total_bytes']?.toString() ?? '')?.toInt(),
          error: error,
        );
        _downloadQueue = [
          ..._downloadQueue.sublist(0, index),
          updated,
          ..._downloadQueue.sublist(index + 1),
        ];
        notifyListeners();
        break;
      case 'download_complete':
        _isQueueProcessing = false;
        _statusMessage = 'Downloads complete';
        unawaited(refreshSongs());
        unawaited(refreshQueue());
        notifyListeners();
        break;
      case 'download_error':
        _isQueueProcessing = false;
        _lastErrorMessage = _friendlyDownloadError(event.data['error']);
        _statusMessage = _lastErrorMessage!;
        notifyListeners();
        break;
      case 'queue_updated':
        unawaited(refreshQueue());
        break;
      case 'songs_updated':
        unawaited(refreshSongs());
        break;
      default:
        break;
    }
  }

  String _friendlyDownloadError(Object? rawError) {
    final message = rawError?.toString().toLowerCase() ?? '';
    if (message.contains('private') ||
        message.contains('unavailable') ||
        message.contains('removed')) {
      return 'Download failed. This video is unavailable.';
    }
    if (message.contains('age')) {
      return 'Download failed. This video requires age verification.';
    }
    if (message.contains('copyright') ||
        message.contains('blocked') ||
        message.contains('region')) {
      return 'Download failed. This video is blocked for downloads.';
    }
    if (message.contains('timeout') ||
        message.contains('network') ||
        message.contains('connection')) {
      return 'Download failed. Check your connection and try again.';
    }
    return 'Download failed. Check the link and try again.';
  }

  DownloadStatus _parseDownloadStatus(String? status) {
    switch (status) {
      case 'downloading':
        return DownloadStatus.downloading;
      case 'processing':
        return DownloadStatus.processing;
      case 'completed':
        return DownloadStatus.completed;
      case 'error':
        return DownloadStatus.error;
      case 'pending':
      default:
        return DownloadStatus.pending;
    }
  }

  Future<bool> _hasNetwork() async {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  Future<bool> _requestStoragePermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) {
      return true;
    }
    if (manageStatus.isPermanentlyDenied) {
      return false;
    }

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _ensureDefaultStoragePathExists() async {
    try {
      final dir = Directory(_settings.storagePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      final fallback = await getExternalStorageDirectory();
      if (fallback != null) {
        _settings = _settings.copyWith(storagePath: fallback.path);
        await _settingsService.save(_settings);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_shareSubscription?.cancel());
    unawaited(_disconnectWebsocket());
    super.dispose();
  }
}
