import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const _serverUrlKey = 'server_url';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';
  static const _userIdKey = 'user_id';
  static const _sessionCookieKey = 'session_cookie';
  static const _syncIntervalHoursKey = 'sync_interval_hours';
  static const _syncWifiOnlyKey = 'sync_wifi_only';
  static const _storagePathKey = 'storage_path';

  static const _secureStorage = FlutterSecureStorage();

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      serverUrl: prefs.getString(_serverUrlKey) ?? '',
      username: prefs.getString(_usernameKey) ?? '',
      password: await _secureStorage.read(key: _passwordKey) ?? '',
      userId: prefs.getString(_userIdKey) ?? '',
      sessionCookie: await _secureStorage.read(key: _sessionCookieKey) ?? '',
      syncIntervalHours: (prefs.getInt(_syncIntervalHoursKey) ?? 0).clamp(0, 168),
      syncWifiOnly: prefs.getBool(_syncWifiOnlyKey) ?? false,
      storagePath: prefs.getString(_storagePathKey) ?? AppSettings.defaultStoragePath,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, settings.serverUrl);
    await prefs.setString(_usernameKey, settings.username);
    await prefs.setString(_userIdKey, settings.userId);
    await prefs.setInt(_syncIntervalHoursKey, settings.syncIntervalHours.clamp(0, 168));
    await prefs.setBool(_syncWifiOnlyKey, settings.syncWifiOnly);
    await prefs.setString(_storagePathKey, settings.storagePath);
    await _secureStorage.write(key: _passwordKey, value: settings.password);
    await _secureStorage.write(key: _sessionCookieKey, value: settings.sessionCookie);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await _secureStorage.delete(key: _sessionCookieKey);
  }
}
