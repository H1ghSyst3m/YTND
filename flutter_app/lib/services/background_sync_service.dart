import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../models/app_settings.dart';
import 'api_service.dart';
import 'settings_service.dart';
import 'sync_service.dart';

const String backgroundSyncTaskName = 'ytnd_background_sync';
const String backgroundSyncUniqueName = 'ytnd_background_sync_unique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    final settings = await SettingsService().load();
    if (settings.serverUrl.isEmpty ||
        settings.userId.isEmpty ||
        settings.sessionCookie.isEmpty ||
        settings.syncIntervalHours <= 0) {
      return true;
    }

    final connected = await _hasNetwork(settings.syncWifiOnly);
    if (!connected) {
      return true;
    }

    final syncService = SyncService(ApiService());
    try {
      await syncService.sync(
        serverUrl: settings.serverUrl,
        userId: settings.userId,
        cookieHeader: settings.sessionCookie,
        storagePath: settings.storagePath,
      );
      return true;
    } catch (e, st) {
      debugPrint('Background sync failed: $e\n$st');
      return false;
    }
  });
}

class BackgroundSyncService {
  Future<void> initialize() {
    if (!Platform.isAndroid) {
      return Future.value();
    }
    return Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  Future<void> configure(AppSettings settings) async {
    if (!Platform.isAndroid) {
      return;
    }
    await Workmanager().cancelByUniqueName(backgroundSyncUniqueName);
    if (settings.syncIntervalHours <= 0 ||
        settings.serverUrl.isEmpty ||
        settings.userId.isEmpty ||
        settings.sessionCookie.isEmpty) {
      return;
    }
    final requestedInterval = Duration(hours: settings.syncIntervalHours);
    // Android WorkManager enforces a minimum periodic interval of 15 minutes.
    final frequency = requestedInterval < const Duration(minutes: 15)
        ? const Duration(minutes: 15)
        : requestedInterval;

    await Workmanager().registerPeriodicTask(
      backgroundSyncUniqueName,
      backgroundSyncTaskName,
      frequency: frequency,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: settings.syncWifiOnly ? NetworkType.unmetered : NetworkType.connected,
      ),
      initialDelay: const Duration(minutes: 5),
    );
  }

  Future<void> cancel() {
    if (!Platform.isAndroid) {
      return Future.value();
    }
    return Workmanager().cancelByUniqueName(backgroundSyncUniqueName);
  }
}

Future<bool> _hasNetwork(bool wifiOnly) async {
  final results = await Connectivity().checkConnectivity();

  if (wifiOnly) {
    return results.contains(ConnectivityResult.wifi);
  }

  return !results.contains(ConnectivityResult.none);
}
