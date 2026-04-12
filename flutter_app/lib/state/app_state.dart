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

class AppState extends ChangeNotifier {
  AppState({
    required SettingsService settingsService,
    required ApiService apiService,
    required SyncService syncService,
    required BackgroundSyncService backgroundSyncService,
    required WebsocketService websocketService,
  })  : _settingsService = settingsService,
        _apiService = apiService,
        _syncService = syncService,
        _backgroundSyncService = backgroundSyncService,
        _websocketService = websocketService;

  final SettingsService _settingsService;
  final ApiService _apiService;
  final SyncService _syncService;
  final BackgroundSyncService _backgroundSyncService;
  final WebsocketService _websocketService;

  AppSettings _settings = const AppSettings();
  List<Song> _songs = const [];
  List<DownloadQueueItem> _downloadQueue = const [];
  StreamSubscription<WsEvent>? _wsSubscription;
  String? _pendingShareUrl;

  bool _initialized = false;
  bool _isAuthenticated = false;
  bool _isSyncing = false;
  bool _isQueueProcessing = false;
  String _statusMessage = '';

  AppSettings get settings => _settings;
  List<Song> get songs => _songs;
  List<DownloadQueueItem> get downloadQueue => _downloadQueue;
  bool get initialized => _initialized;
  bool get isAuthenticated => _isAuthenticated;
  bool get isSyncing => _isSyncing;
  bool get isQueueProcessing => _isQueueProcessing;
  String get statusMessage => _statusMessage;
  String? get pendingShareUrl => _pendingShareUrl;

  String? consumePendingShareUrl() {
    final value = _pendingShareUrl;
    _pendingShareUrl = null;
    return value;
  }

  Future<void> initialize() async {
    _settings = await _settingsService.load();

    if (_settings.storagePath == AppSettings.defaultStoragePath) {
      await _ensureDefaultStoragePathExists();
    }

    if (_settings.serverUrl.isNotEmpty &&
        _settings.sessionCookie.isNotEmpty &&
        _settings.userId.isNotEmpty) {
      try {
        final authorized = await _apiService.ping(
          serverUrl: _settings.serverUrl,
          cookieHeader: _settings.sessionCookie,
        );
        _isAuthenticated = authorized;
      } catch (_) {
        _isAuthenticated = false;
      }
    }

    if (_isAuthenticated) {
      _pendingShareUrl = await ShareIntentService().getInitialSharedText();
      try {
        await refreshSongs();
        await refreshQueue();
      } catch (e) {
        _statusMessage = 'Failed to load songs: $e';
      }
      await _configureBackgroundSync();
      await _connectWebsocket();
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final (userId, cookieHeader) = await _apiService.login(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );

    _settings = _settings.copyWith(
      serverUrl: serverUrl,
      username: username,
      password: password,
      userId: userId,
      sessionCookie: cookieHeader,
    );
    await _settingsService.save(_settings);

    _isAuthenticated = true;
    _statusMessage = 'Login successful';
    try {
      await refreshSongs();
      await refreshQueue();
      await _configureBackgroundSync();
      await _connectWebsocket();
    } catch (e, st) {
      debugPrint('Post-login refresh failed: $e\n$st');
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _songs = const [];
    _downloadQueue = const [];
    _statusMessage = 'Logged out';
    _isQueueProcessing = false;
    _settings = _settings.copyWith(userId: '', sessionCookie: '');
    await _settingsService.save(_settings);
    await _settingsService.clearSession();
    await _backgroundSyncService.cancel();
    await _disconnectWebsocket();
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _settingsService.save(_settings);
    await _configureBackgroundSync();
    if (_isAuthenticated) {
      await _connectWebsocket();
      await refreshQueue();
    }
    notifyListeners();
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

  Future<void> refreshSongs() async {
    if (!_isAuthenticated) {
      return;
    }

    _songs = await _apiService.fetchSongs(
      serverUrl: _settings.serverUrl,
      userId: _settings.userId,
      cookieHeader: _settings.sessionCookie,
    );
    notifyListeners();
  }

  Future<void> refreshQueue() async {
    if (!_isAuthenticated) {
      return;
    }
    final urls = await _apiService.fetchQueue(
      serverUrl: _settings.serverUrl,
      userId: _settings.userId,
      cookieHeader: _settings.sessionCookie,
    );
    final serverUrlSet = urls.toSet();
    final inFlight = _downloadQueue
        .where((item) =>
            (item.status == DownloadStatus.downloading || item.status == DownloadStatus.processing) &&
            !serverUrlSet.contains(item.url))
        .toList();
    final currentByUrl = {for (final item in _downloadQueue) item.url: item};
    _downloadQueue = [
      ...inFlight,
      ...urls.map((url) => currentByUrl[url] ?? DownloadQueueItem(url: url)),
    ];
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (_isSyncing || !_isAuthenticated) {
      return;
    }

    final connected = await _hasNetwork();
    if (!connected) {
      _statusMessage = 'Skipped sync: no network access';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _statusMessage = 'Sync in progress...';
    notifyListeners();

    try {
      final permissionGranted = await _requestStoragePermissions();
      if (!permissionGranted) {
        _statusMessage = 'Sync skipped: storage permission denied';
        return;
      }
      final result = await _syncService.sync(
        serverUrl: _settings.serverUrl,
        userId: _settings.userId,
        cookieHeader: _settings.sessionCookie,
        storagePath: _settings.storagePath,
      );
      await refreshSongs();
      _statusMessage =
          'Sync finished: ${result.remoteCount} server songs, ${result.downloaded} downloaded, ${result.deleted} removed locally';
    } catch (e) {
      _statusMessage = 'Sync failed: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> deleteSong(Song song) async {
    if (!_isAuthenticated) {
      return;
    }

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
  }

  Future<void> addUrlsToQueue(List<String> urls) async {
    final normalized = urls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (!_isAuthenticated || normalized.isEmpty) {
      return;
    }

    await _apiService.addToQueue(
      serverUrl: _settings.serverUrl,
      userId: _settings.userId,
      cookieHeader: _settings.sessionCookie,
      urls: normalized,
    );
    _statusMessage = 'Added ${normalized.length} URL(s) to queue';
    await refreshQueue();
  }

  Future<void> removeUrlFromQueue(String url) async {
    if (!_isAuthenticated) {
      return;
    }
    await _apiService.removeFromQueue(
      serverUrl: _settings.serverUrl,
      userId: _settings.userId,
      cookieHeader: _settings.sessionCookie,
      urls: [url],
    );
    await refreshQueue();
  }

  Future<void> clearQueue() async {
    if (!_isAuthenticated) {
      return;
    }
    await _apiService.removeFromQueue(
      serverUrl: _settings.serverUrl,
      userId: _settings.userId,
      cookieHeader: _settings.sessionCookie,
    );
    await refreshQueue();
  }

  Future<void> processQueue() async {
    if (!_isAuthenticated || _isQueueProcessing || _downloadQueue.isEmpty) {
      return;
    }
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
    if (event.userId != null && event.userId != _settings.userId) {
      return;
    }
    switch (event.type) {
      case 'download_progress':
        final url = event.url;
        if (url == null || url.isEmpty) {
          return;
        }
        final existingIndex = _downloadQueue.indexWhere((item) => item.url == url);
        final index = existingIndex >= 0 ? existingIndex : _downloadQueue.length;
        if (existingIndex < 0) {
          _downloadQueue = [..._downloadQueue, DownloadQueueItem(url: url)];
        }
        final data = event.data;
        final status = _parseDownloadStatus(data['status']?.toString());
        final updated = _downloadQueue[index].copyWith(
          status: status,
          title: data['title']?.toString(),
          artist: data['artist']?.toString(),
          id: data['id']?.toString(),
          percentage: num.tryParse(data['percentage']?.toString() ?? '')?.toDouble(),
          downloadedBytes: num.tryParse(data['downloaded_bytes']?.toString() ?? '')?.toInt(),
          totalBytes: num.tryParse(data['total_bytes']?.toString() ?? '')?.toInt(),
          error: data['error']?.toString(),
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
        unawaited(refreshSongs());
        unawaited(refreshQueue());
        notifyListeners();
        break;
      case 'download_error':
        _isQueueProcessing = false;
        _statusMessage = 'Download failed: ${event.data['error']?.toString() ?? 'Unknown error'}';
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
    unawaited(_disconnectWebsocket());
    super.dispose();
  }
}
