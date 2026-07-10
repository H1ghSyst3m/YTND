import 'dart:async';
import 'dart:io';

import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/models/song.dart';
import 'package:ytnd/services/api_service.dart';
import 'package:ytnd/services/background_sync_service.dart';
import 'package:ytnd/services/settings_service.dart';
import 'package:ytnd/services/share_intent_service.dart';
import 'package:ytnd/services/websocket_service.dart';

class FakeSettingsService extends SettingsService {
  FakeSettingsService({
    this.settings = const AppSettings(storagePath: 'test-storage'),
    List<String> pendingShareUrls = const [],
  }) : pendingShareUrls = List<String>.of(pendingShareUrls);

  AppSettings settings;
  List<String> pendingShareUrls;
  String? dismissedConnectionNoticeKey;
  Object? saveError;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    this.settings = settings;
  }

  @override
  Future<List<String>> loadPendingShareUrls() async =>
      List<String>.of(pendingShareUrls);

  @override
  Future<void> savePendingShareUrls(List<String> urls) async {
    pendingShareUrls = List<String>.of(urls);
  }

  @override
  Future<String?> loadDismissedConnectionNoticeKey() async =>
      dismissedConnectionNoticeKey;

  @override
  Future<void> saveDismissedConnectionNoticeKey(String? key) async {
    dismissedConnectionNoticeKey = key;
  }

  @override
  Future<void> clearSession() async {
    settings = settings.copyWith(userId: '', sessionCookie: '');
  }
}

class FakeApiService extends ApiService {
  bool authorized = true;
  Object? loginError;
  Object? pingError;
  Object? addError;
  Object? deleteError;
  Object? redownloadError;
  int fetchSongsCalls = 0;
  List<Song> songs = const [];
  List<String> queue = [];
  List<Song> redownloadedSongs = [];

  @override
  Future<(String userId, String cookieHeader)> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final error = loginError;
    if (error != null) {
      throw error;
    }
    return ('u1', 'ytnd_uid=u1; ytnd_sig=sig');
  }

  @override
  Future<bool> ping({
    required String serverUrl,
    required String cookieHeader,
  }) async {
    final error = pingError;
    if (error != null) {
      throw error;
    }
    return authorized;
  }

  @override
  Future<List<Song>> fetchSongs({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    fetchSongsCalls++;
    return songs;
  }

  @override
  Future<List<String>> fetchQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    return List<String>.of(queue);
  }

  @override
  Future<void> addToQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    required List<String> urls,
  }) async {
    final error = addError;
    if (error != null) {
      throw error;
    }
    queue = {...queue, ...urls}.toList();
  }

  @override
  Future<void> removeFromQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    List<String>? urls,
  }) async {
    if (urls == null || urls.isEmpty) {
      queue = [];
    } else {
      queue = queue.where((url) => !urls.contains(url)).toList();
    }
  }

  @override
  Future<int> processQueue({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    return queue.length;
  }

  @override
  Future<void> deleteSong({
    required String serverUrl,
    required String userId,
    required Song song,
    required String cookieHeader,
  }) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    songs = songs.where((item) => !_isSameSong(item, song)).toList();
  }

  @override
  Future<void> redownloadSong({
    required String serverUrl,
    required String userId,
    required Song song,
    required String cookieHeader,
    bool force = false,
  }) async {
    final error = redownloadError;
    if (error != null) {
      throw error;
    }
    redownloadedSongs = [...redownloadedSongs, song];
  }

  @override
  Future<void> downloadSong({
    required String serverUrl,
    required String userId,
    required String filename,
    required String cookieHeader,
    required File targetFile,
  }) async {}

  bool _isSameSong(Song a, Song b) {
    if (b.id != null && b.id!.isNotEmpty) {
      return a.id == b.id;
    }
    return a.title == b.title && a.artist == b.artist;
  }
}

class FakeBackgroundSyncService extends BackgroundSyncService {
  bool configured = false;
  bool cancelled = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> configure(AppSettings settings) async {
    configured = true;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

class FakeWebsocketService extends WebsocketService {
  final StreamController<WsEvent> controller =
      StreamController<WsEvent>.broadcast();
  bool connected = false;

  @override
  Stream<WsEvent> get events => controller.stream;

  @override
  Future<void> connect({
    required String serverUrl,
    required String cookieHeader,
  }) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}

class FakeShareIntentService extends ShareIntentService {
  FakeShareIntentService({this.initialUrls = const []});

  final List<String> initialUrls;
  final StreamController<List<String>> controller =
      StreamController<List<String>>.broadcast();

  @override
  Future<List<String>> getInitialSharedUrls() async => initialUrls;

  @override
  Stream<List<String>> get sharedUrlStream => controller.stream;
}
