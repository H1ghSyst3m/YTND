import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'services/api_service.dart';
import 'services/background_sync_service.dart';
import 'services/settings_service.dart';
import 'services/share_intent_service.dart';
import 'services/sync_service.dart';
import 'services/websocket_service.dart';
import 'state/app_state.dart';
import 'theme/ytnd_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  final backgroundSyncService = BackgroundSyncService();
  final websocketService = WebsocketService();
  await backgroundSyncService.initialize();

  runApp(
    YtndApp(
      apiService: apiService,
      backgroundSyncService: backgroundSyncService,
      websocketService: websocketService,
    ),
  );
}

class YtndApp extends StatelessWidget {
  const YtndApp({
    Key? key,
    required ApiService apiService,
    required BackgroundSyncService backgroundSyncService,
    required WebsocketService websocketService,
    SettingsService? settingsService,
    ShareIntentService? shareIntentService,
  }) : this._(
         key: key,
         apiService: apiService,
         backgroundSyncService: backgroundSyncService,
         websocketService: websocketService,
         settingsService: settingsService,
         shareIntentService: shareIntentService,
       );

  const YtndApp._({
    super.key,
    required this._apiService,
    required this._backgroundSyncService,
    required this._websocketService,
    this._settingsService,
    this._shareIntentService,
  });

  factory YtndApp.withDefaults({Key? key}) {
    return YtndApp(
      key: key,
      apiService: ApiService(),
      backgroundSyncService: BackgroundSyncService(),
      websocketService: WebsocketService(),
    );
  }

  final ApiService _apiService;
  final BackgroundSyncService _backgroundSyncService;
  final WebsocketService _websocketService;
  final SettingsService? _settingsService;
  final ShareIntentService? _shareIntentService;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        settingsService: _settingsService ?? SettingsService(),
        apiService: _apiService,
        syncService: SyncService(_apiService),
        backgroundSyncService: _backgroundSyncService,
        websocketService: _websocketService,
        shareIntentService: _shareIntentService ?? ShareIntentService(),
      )..initialize(),
      child: MaterialApp(
        title: 'YTND',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: YtndTheme.light(),
        darkTheme: YtndTheme.dark(),
        home: const AppShell(),
      ),
    );
  }
}
