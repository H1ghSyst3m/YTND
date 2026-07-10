import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/app_settings.dart';
import '../models/download_queue_item.dart';
import '../models/song.dart';
import '../models/sync_summary.dart';
import '../services/api_service.dart';
import '../services/background_sync_service.dart';
import '../services/cover_cache_service.dart';
import '../services/settings_service.dart';
import '../services/share_intent_service.dart';
import '../services/shared_url_parser.dart';
import '../services/sync_service.dart';
import '../services/websocket_service.dart';

enum ConnectionStatus {
  setupRequired,
  signedOut,
  checking,
  connected,
  unreachable,
  unauthorized,
  invalidCredentials,
}

enum QueueAddResult { added, deferred, failed }

class AppState extends ChangeNotifier {
  AppState({
    required SettingsService settingsService,
    required ApiService apiService,
    required SyncService syncService,
    required BackgroundSyncService backgroundSyncService,
    required WebsocketService websocketService,
    required ShareIntentService shareIntentService,
    CoverCacheService? coverCacheService,
  }) : this._(
         settingsService: settingsService,
         apiService: apiService,
         syncService: syncService,
         backgroundSyncService: backgroundSyncService,
         websocketService: websocketService,
         shareIntentService: shareIntentService,
         coverCacheService: coverCacheService ?? CoverCacheService.instance,
       );

  AppState._({
    required this._settingsService,
    required this._apiService,
    required this._syncService,
    required this._backgroundSyncService,
    required this._websocketService,
    required this._shareIntentService,
    required this._coverCacheService,
  });

  final SettingsService _settingsService;
  final ApiService _apiService;
  final SyncService _syncService;
  final BackgroundSyncService _backgroundSyncService;
  final WebsocketService _websocketService;
  final ShareIntentService _shareIntentService;
  final CoverCacheService _coverCacheService;

  AppSettings _settings = const AppSettings();
  List<Song> _songs = const [];
  Map<String, bool> _downloadedSongKeys = const {};
  List<DownloadQueueItem> _downloadQueue = const [];
  List<String> _pendingShareUrls = const [];
  SyncSummary? _latestSyncSummary;
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
  String? _dismissedConnectionNoticeKey;
  int _connectionNoticeVersion = 0;
  int _queueFocusVersion = 0;

  AppSettings get settings => _settings;
  List<Song> get songs => _songs;
  List<DownloadQueueItem> get downloadQueue => _downloadQueue;
  List<DownloadQueueItem> get inProgressQueue => _downloadQueue
      .where(
        (item) =>
            item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.processing,
      )
      .toList(growable: false);
  List<DownloadQueueItem> get queuedQueue => _downloadQueue
      .where((item) => item.status == DownloadStatus.pending)
      .toList(growable: false);
  List<DownloadQueueItem> get failedQueue => _downloadQueue
      .where((item) => item.status == DownloadStatus.error)
      .toList(growable: false);
  List<String> get pendingShareUrls => _pendingShareUrls;
  SyncSummary? get latestSyncSummary => _latestSyncSummary;
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

  bool isSongAvailable(Song song) => song.fileAvailable;

  bool isSongDownloaded(Song song) =>
      isSongAvailable(song) &&
      (_downloadedSongKeys[_songStatusKey(song)] ?? false);

  String? get pendingShareUrl =>
      _pendingShareUrls.isEmpty ? null : _pendingShareUrls.first;

  String get connectionNoticeKey {
    final error = _lastErrorMessage;
    final errorPart = error == null || error.isEmpty
        ? ''
        : ':error:$_connectionNoticeVersion:$error';
    return 'connection:${_connectionStatus.name}$errorPart';
  }

  bool get shouldShowConnectionNotice =>
      _dismissedConnectionNoticeKey != connectionNoticeKey;

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
      case ConnectionStatus.invalidCredentials:
        return 'Invalid credentials';
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
      case ConnectionStatus.invalidCredentials:
        return 'Check your username and password, then try again.';
    }
  }

  Future<void> dismissConnectionNotice() async {
    _dismissedConnectionNoticeKey = connectionNoticeKey;
    await _settingsService.saveDismissedConnectionNoticeKey(
      _dismissedConnectionNoticeKey,
    );
    notifyListeners();
  }

  void clearLatestSyncSummary() {
    _latestSyncSummary = null;
    notifyListeners();
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
      _dismissedConnectionNoticeKey =
          await _settingsService.loadDismissedConnectionNoticeKey();

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
      _markFreshConnectionNotice();
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
      final accountChanged =
          normalizedServerUrl != _settings.serverUrl ||
          normalizedUsername != _settings.username ||
          password != _settings.password;

      if (accountChanged) {
        _isAuthenticated = false;
        _songs = const [];
        _downloadedSongKeys = const {};
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
      _connectionStatus = _statusForError(
        e,
        authFailureIsInvalidCredentials: true,
      );
      _lastErrorMessage = _messageFor(e, 'Could not sign in.');
      _statusMessage = _lastErrorMessage!;
      _markFreshConnectionNotice();
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
    _downloadedSongKeys = const {};
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
      final accountChanged =
          normalizedServerUrl != _settings.serverUrl ||
          next.username != _settings.username ||
          next.password != _settings.password;

      if (accountChanged) {
        next = next.copyWith(userId: '', sessionCookie: '');
        _isAuthenticated = false;
        _songs = const [];
        _downloadedSongKeys = const {};
        _downloadQueue = const [];
        _isQueueProcessing = false;
        await _disconnectWebsocket();
        await _backgroundSyncService.cancel();
        await _settingsService.clearSession();
      }

      _settings = next;
      await _settingsService.save(_settings);
      if (_songs.isNotEmpty) {
        _downloadedSongKeys = await _resolveDownloadedSongs(_songs);
      }
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
      _markFreshConnectionNotice();
      notifyListeners();
      rethrow;
    } finally {
      _isSavingSettings = false;
      notifyListeners();
    }
  }

  Future<bool> updateSyncPreferences({
    int? syncIntervalHours,
    bool? syncWifiOnly,
    bool? syncOnStartup,
  }) async {
    if (_isSavingSettings) {
      return false;
    }

    _isSavingSettings = true;
    _lastErrorMessage = null;
    notifyListeners();

    final previousSettings = _settings;
    try {
      _settings = _settings.copyWith(
        syncIntervalHours: syncIntervalHours,
        syncWifiOnly: syncWifiOnly,
        syncOnStartup: syncOnStartup,
      );
      await _settingsService.save(_settings);
      if (_isAuthenticated) {
        await _configureBackgroundSync();
      }
      _statusMessage = 'Settings saved';
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Saving sync preferences failed: $e\n$st');
      _settings = previousSettings;
      _lastErrorMessage = _messageFor(e, 'Could not save sync settings.');
      _statusMessage = _lastErrorMessage!;
      _markFreshConnectionNotice();
      notifyListeners();
      return false;
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
      _downloadedSongKeys = await _resolveDownloadedSongs(_songs);
      _prefetchSongCovers(_songs);
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
      _downloadQueue = _mergeServerQueue(urls);
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
        _lastErrorMessage = _statusMessage;
        _connectionStatus = ConnectionStatus.unreachable;
        _latestSyncSummary = SyncSummary(
          remoteCount: 0,
          downloaded: 0,
          deleted: 0,
          completedAt: DateTime.now(),
          message: _statusMessage,
          success: false,
        );
        _markFreshConnectionNotice();
        notifyListeners();
        return false;
      }

      final permissionGranted = await _requestStoragePermissions();
      if (!permissionGranted) {
        _statusMessage = 'Sync skipped: storage permission denied.';
        _latestSyncSummary = SyncSummary(
          remoteCount: 0,
          downloaded: 0,
          deleted: 0,
          completedAt: DateTime.now(),
          message: _statusMessage,
          success: false,
        );
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
      _latestSyncSummary = SyncSummary(
        remoteCount: result.remoteCount,
        downloaded: result.downloaded,
        deleted: result.deleted,
        completedAt: DateTime.now(),
        message: 'Sync finished',
      );
      _statusMessage = 'Sync finished';
      return true;
    } catch (e, st) {
      debugPrint('Sync failed: $e\n$st');
      _latestSyncSummary = SyncSummary(
        remoteCount: 0,
        downloaded: 0,
        deleted: 0,
        completedAt: DateTime.now(),
        message: _messageFor(e, 'Sync failed.'),
        success: false,
      );
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
        e,
        'Could not queue this song for redownload.',
      );
      return false;
    }
  }

  Future<QueueAddResult> addUrlsToQueue(
    List<String> urls, {
    bool fromShare = false,
  }) async {
    final normalized = _uniqueUrls(urls);
    if (normalized.isEmpty) {
      _statusMessage = 'No valid YouTube links found.';
      notifyListeners();
      return QueueAddResult.failed;
    }

    if (!_isAuthenticated) {
      await _storePendingShareUrls(normalized);
      _statusMessage = 'Saved ${normalized.length} link(s) until you sign in.';
      _queueFocusVersion++;
      notifyListeners();
      return QueueAddResult.deferred;
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
      return QueueAddResult.added;
    } catch (e, st) {
      debugPrint('Add queue failed: $e\n$st');
      if (fromShare) {
        await _storePendingShareUrls(normalized);
      }
      await _handleOperationFailure(e, 'Could not add the link to the queue.');
      return QueueAddResult.failed;
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
    if (!_isAuthenticated || _isQueueProcessing || queuedQueue.isEmpty) {
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

  Future<bool> retryFailedDownload(DownloadQueueItem item) async {
    final result = await addUrlsToQueue([item.url]);
    if (result == QueueAddResult.failed) {
      return false;
    }
    dismissLocalQueueItem(item.url);
    return true;
  }

  void dismissLocalQueueItem(String url) {
    final key = _queueKeyFor(url);
    _downloadQueue = _downloadQueue
        .where((item) => _queueKeyFor(item.url) != key)
        .toList(growable: false);
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
      await _syncOnStartupIfNeeded();
    } catch (e, st) {
      debugPrint('Session restore failed: $e\n$st');
      if (e is ApiException && e.isAuthFailure) {
        await _expireSession(
          _messageFor(e, 'Your session expired. Sign in again.'),
        );
        return;
      }
      _isAuthenticated = hasSavedSession;
      _connectionStatus = _statusForError(e);
      _lastErrorMessage = _messageFor(e, 'Could not reach your YTND server.');
      _statusMessage = _lastErrorMessage!;
      _markFreshConnectionNotice();
      await _backgroundSyncService.cancel();
    }
  }

  Future<void> _loadInitialData() async {
    await refreshSongs();
    await refreshQueue();
  }

  Future<Map<String, bool>> _resolveDownloadedSongs(List<Song> songs) async {
    final results = await Future.wait(
      songs.map((song) async {
        final downloaded =
            song.fileAvailable && await _isDownloadedOnDevice(song);
        return MapEntry(_songStatusKey(song), downloaded);
      }),
    );
    return Map.fromEntries(results);
  }

  Future<bool> _isDownloadedOnDevice(Song song) async {
    final localFile = _safeLocalSongFile(song);
    return localFile != null && await localFile.exists();
  }

  File? _safeLocalSongFile(Song song) {
    final filename = song.filename;
    if (filename == null || filename.trim().isEmpty) {
      return null;
    }
    final segments = filename.split(RegExp(r'[\\/]'));
    if (p.isAbsolute(filename) || segments.contains('..')) {
      return null;
    }

    final storageRoot = p.normalize(
      Directory(_settings.storagePath).absolute.path,
    );
    final resolved = p.normalize(p.join(storageRoot, filename));
    if (!p.isWithin(storageRoot, resolved)) {
      return null;
    }
    return File(resolved);
  }

  String _songStatusKey(Song song) {
    final id = song.id;
    if (id != null && id.isNotEmpty) {
      return 'id:$id';
    }
    final filename = song.filename;
    if (filename != null && filename.isNotEmpty) {
      return 'file:$filename';
    }
    return 'meta:${song.title}|${song.artist}';
  }

  void _prefetchSongCovers(List<Song> songs) {
    if (_settings.sessionCookie.isEmpty) {
      return;
    }
    final urls = songs
        .map(coverUrlFor)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (urls.isEmpty) {
      return;
    }
    unawaited(
      _coverCacheService.prefetchAll(
        coverUrls: urls,
        cookieHeader: _settings.sessionCookie,
      ),
    );
  }

  Future<void> _syncOnStartupIfNeeded() async {
    if (!_settings.syncOnStartup || !_isAuthenticated || _isSyncing) {
      return;
    }

    if (_settings.syncWifiOnly && !await _hasNetwork(wifiOnly: true)) {
      _statusMessage = 'Startup sync skipped: WiFi required.';
      _latestSyncSummary = SyncSummary(
        remoteCount: 0,
        downloaded: 0,
        deleted: 0,
        completedAt: DateTime.now(),
        message: _statusMessage,
        success: false,
      );
      notifyListeners();
      return;
    }

    await syncNow();
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
    Object error,
    String fallbackMessage,
  ) async {
    final message = _messageFor(error, fallbackMessage);
    _lastErrorMessage = message;
    _statusMessage = message;
    _markFreshConnectionNotice();
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
    _markFreshConnectionNotice();
    _settings = _settings.copyWith(userId: '', sessionCookie: '');
    await _settingsService.save(_settings);
    await _settingsService.clearSession();
    await _backgroundSyncService.cancel();
    await _disconnectWebsocket();
    notifyListeners();
  }

  ConnectionStatus _statusForError(
    Object error, {
    bool authFailureIsInvalidCredentials = false,
  }) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.unauthorized:
        case ApiErrorKind.forbidden:
          return authFailureIsInvalidCredentials
              ? ConnectionStatus.invalidCredentials
              : ConnectionStatus.unauthorized;
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
        final key = _queueKeyFor(url);
        final existingIndex = _downloadQueue.indexWhere(
          (item) => _queueKeyFor(item.url) == key,
        );
        final index = existingIndex >= 0
            ? existingIndex
            : _downloadQueue.length;
        if (existingIndex < 0) {
          _downloadQueue = [..._downloadQueue, DownloadQueueItem(url: url)];
        }
        final data = event.data;
        final status = _parseDownloadStatus(data['status']?.toString());
        final error = status == DownloadStatus.error
            ? _friendlyDownloadError(data['error'])
            : null;
        if (error != null) {
          _lastErrorMessage = error;
          _statusMessage = error;
          _markFreshConnectionNotice();
        }
        final updated = _downloadQueue[index].copyWith(
          status: status,
          title: data['title']?.toString(),
          artist: data['artist']?.toString(),
          id: data['id']?.toString(),
          percentage: num.tryParse(
            data['percentage']?.toString() ?? '',
          )?.toDouble(),
          downloadedBytes: num.tryParse(
            data['downloaded_bytes']?.toString() ?? '',
          )?.toInt(),
          totalBytes: num.tryParse(
            data['total_bytes']?.toString() ?? '',
          )?.toInt(),
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
        _markFreshConnectionNotice();
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

  List<DownloadQueueItem> _mergeServerQueue(List<String> urls) {
    final currentByKey = {
      for (final item in _downloadQueue) _queueKeyFor(item.url): item,
    };
    final seenKeys = <String>{};
    final merged = <DownloadQueueItem>[];

    for (final url in urls) {
      final key = _queueKeyFor(url);
      if (!seenKeys.add(key)) {
        continue;
      }
      final current = currentByKey[key];
      merged.add(
        current == null
            ? DownloadQueueItem(url: url)
            : current.copyWith(
                status: DownloadStatus.pending,
                percentage: null,
                downloadedBytes: null,
                totalBytes: null,
                error: null,
              ),
      );
    }

    for (final item in _downloadQueue) {
      final key = _queueKeyFor(item.url);
      if (seenKeys.contains(key) || item.status == DownloadStatus.pending) {
        continue;
      }
      seenKeys.add(key);
      merged.add(item);
    }

    return merged;
  }

  String _queueKeyFor(String url) => SharedUrlParser.queueKeyFor(url);

  void _markFreshConnectionNotice() {
    _connectionNoticeVersion++;
  }

  Future<bool> _hasNetwork({bool wifiOnly = false}) async {
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return false;
    }
    if (!wifiOnly) {
      return true;
    }
    return results.contains(ConnectivityResult.wifi);
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
