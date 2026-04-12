import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/download_screen.dart';
import 'screens/library_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/background_sync_service.dart';
import 'services/settings_service.dart';
import 'services/sync_service.dart';
import 'services/websocket_service.dart';
import 'state/app_state.dart';

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
    super.key,
    required ApiService apiService,
    required BackgroundSyncService backgroundSyncService,
    required WebsocketService websocketService,
  })  : _apiService = apiService,
        _backgroundSyncService = backgroundSyncService,
        _websocketService = websocketService;

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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        settingsService: SettingsService(),
        apiService: _apiService,
        syncService: SyncService(_apiService),
        backgroundSyncService: _backgroundSyncService,
        websocketService: _websocketService,
      )..initialize(),
      child: MaterialApp(
        title: 'YTND',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF12C6D3),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF12C6D3),
            brightness: Brightness.dark,
            surface: const Color(0xFF1A2230),
          ),
          scaffoldBackgroundColor: const Color(0xFF1A2230),
          useMaterial3: true,
        ),
        home: const AppRoot(),
      ),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _checkedShareIntent = false;

  void _handlePendingShareIntent(AppState appState) {
    if (appState.pendingShareUrl != null) {
      appState.consumePendingShareUrl();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DownloadScreen()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        if (!appState.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!appState.isAuthenticated) {
          _checkedShareIntent = false;
          return const LoginScreen();
        }
        if (!_checkedShareIntent) {
          _checkedShareIntent = true;
          _handlePendingShareIntent(appState);
        }
        return const LibraryScreen();
      },
    );
  }
}
