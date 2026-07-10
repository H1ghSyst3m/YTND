import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ytnd/main.dart';
import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/models/song.dart';
import 'package:ytnd/screens/app_shell.dart';
import 'package:ytnd/screens/library_screen.dart';
import 'package:ytnd/screens/queue_screen.dart';
import 'package:ytnd/screens/settings_screen.dart';
import 'package:ytnd/services/sync_service.dart';
import 'package:ytnd/state/app_state.dart';

import 'fakes.dart';

const _signedInSettings = AppSettings(
  serverUrl: 'http://ytnd.local:8080',
  username: 'demo',
  password: 'secret',
  userId: 'u1',
  sessionCookie: 'cookie',
  storagePath: 'test-storage',
);

const _connectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

void _mockConnectivity(List<String> results) {
  TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
        expect(call.method, 'check');
        return results;
      });
  addTearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
  });
}

IconButton _iconButtonByTooltip(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find
        .ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton))
        .first,
  );
}

class CountingAppState extends AppState {
  CountingAppState({
    required FakeSettingsService settingsService,
    required FakeApiService apiService,
  }) : super(
         settingsService: settingsService,
         apiService: apiService,
         syncService: SyncService(apiService),
         backgroundSyncService: FakeBackgroundSyncService(),
         websocketService: FakeWebsocketService(),
         shareIntentService: FakeShareIntentService(),
       );

  int coverUrlRequests = 0;

  @override
  String? coverUrlFor(Song song) {
    coverUrlRequests++;
    return super.coverUrlFor(song);
  }
}

void main() {
  testWidgets('app shell starts with settings reachable', (tester) async {
    await tester.pumpWidget(
      YtndApp(
        apiService: FakeApiService(),
        backgroundSyncService: FakeBackgroundSyncService(),
        websocketService: FakeWebsocketService(),
        settingsService: FakeSettingsService(),
        shareIntentService: FakeShareIntentService(),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Server setup required'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Queue'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('app bar actions are disabled while signed out', (tester) async {
    final state = AppState(
      settingsService: FakeSettingsService(
        settings: const AppSettings(
          serverUrl: 'http://ytnd.local:8080',
          username: 'demo',
          password: 'secret',
          storagePath: 'test-storage',
        ),
      ),
      apiService: FakeApiService(),
      syncService: SyncService(FakeApiService()),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: AppShell()),
      ),
    );

    expect(_iconButtonByTooltip(tester, 'Refresh songs').onPressed, isNull);
    expect(_iconButtonByTooltip(tester, 'Sync now').onPressed, isNull);

    await tester.tap(find.text('Queue').last);
    await tester.pumpAndSettle();

    expect(_iconButtonByTooltip(tester, 'Refresh queue').onPressed, isNull);
  });

  testWidgets('closing older sync details keeps a newer summary', (
    tester,
  ) async {
    _mockConnectivity(['none']);
    final api = FakeApiService();
    final state = AppState(
      settingsService: FakeSettingsService(settings: _signedInSettings),
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await state.syncNow();
    final firstSummary = state.latestSyncSummary;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.tap(find.byTooltip('Sync details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await state.syncNow();
    final secondSummary = state.latestSyncSummary;
    expect(firstSummary, isNotNull);
    expect(secondSummary, isNotNull);
    expect(identical(firstSummary, secondSummary), isFalse);

    await tester.tap(find.byTooltip('Close').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(state.latestSyncSummary, same(secondSummary));
  });

  testWidgets('library renders populated songs lazily', (tester) async {
    final api = FakeApiService()
      ..songs = List.generate(
        80,
        (index) => Song(title: 'Song $index', artist: 'Artist $index'),
      );
    final state = CountingAppState(
      settingsService: FakeSettingsService(settings: _signedInSettings),
      apiService: api,
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
      ),
    );

    expect(find.text('Songs'), findsNothing);
    expect(find.text('80 songs'), findsOneWidget);
    expect(find.text('Search songs'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 79'), findsNothing);
    expect(state.coverUrlRequests, greaterThan(0));
  });

  testWidgets('library newest uses server download time instead of video date', (
    tester,
  ) async {
    final api = FakeApiService()
      ..songs = const [
        Song(
          title: 'New video old server',
          artist: 'Artist A',
          date: '2026-12-01',
          downloadedAt: '2024-01-01T12:00:00Z',
          fileAvailable: true,
        ),
        Song(
          title: 'Old video new server',
          artist: 'Artist B',
          date: '2020-01-01',
          downloadedAt: '2026-02-01T23:30:00Z',
          fileAvailable: true,
        ),
        Song(
          title: 'Unknown server time',
          artist: 'Artist C',
          date: '2027-01-01',
          fileAvailable: true,
        ),
      ];
    final state = CountingAppState(
      settingsService: FakeSettingsService(settings: _signedInSettings),
      apiService: api,
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: LibraryScreen())),
      ),
    );

    final newServer = find.text('Old video new server');
    final oldServer = find.text('New video old server');
    final unknownServer = find.text('Unknown server time');

    expect(
      tester.getTopLeft(newServer).dy,
      lessThan(tester.getTopLeft(oldServer).dy),
    );
    expect(
      tester.getTopLeft(oldServer).dy,
      lessThan(tester.getTopLeft(unknownServer).dy),
    );
    expect(
      find.text(_shortDate(DateTime.utc(2026, 2, 1, 23, 30).toLocal())),
      findsOneWidget,
    );
    expect(
      find.text(_shortDate(DateTime.utc(2024, 1, 1, 12).toLocal())),
      findsOneWidget,
    );
    expect(find.text('No download date'), findsOneWidget);
  });

  testWidgets('queue saves signed-out input for later and clears the field', (
    tester,
  ) async {
    final settings = FakeSettingsService();
    final api = FakeApiService();
    final state = AppState(
      settingsService: settings,
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: QueueScreen())),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'https://youtu.be/deferred123',
    );
    await tester.tap(find.byTooltip('Save for sign-in'));
    await tester.pumpAndSettle();

    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.controller.text, isEmpty);
    expect(settings.pendingShareUrls, ['https://youtu.be/deferred123']);
    expect(state.pendingShareUrls, ['https://youtu.be/deferred123']);
    expect(find.text('Saved 1 link(s) until you sign in.'), findsOneWidget);
  });

  testWidgets('settings shows sync on startup option', (tester) async {
    final api = FakeApiService();
    final state = AppState(
      settingsService: FakeSettingsService(settings: _signedInSettings),
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    expect(find.text('Sync on startup'), findsOneWidget);
    expect(
      find.text('Run once after a saved session is restored'),
      findsOneWidget,
    );
  });

  testWidgets('settings sync controls save immediately', (tester) async {
    final settings = FakeSettingsService(settings: _signedInSettings);
    final api = FakeApiService();
    final state = AppState(
      settingsService: settings,
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    await tester.tap(find.text('Manual only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 2 hours').last);
    await tester.pumpAndSettle();

    expect(settings.settings.syncIntervalHours, 2);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();

    expect(settings.settings.syncOnStartup, isTrue);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(settings.settings.syncWifiOnly, isTrue);
  });

  testWidgets('settings sync controls disable while saving', (tester) async {
    final saveCompleter = Completer<void>();
    final settings = FakeSettingsService(settings: _signedInSettings)
      ..saveCompleter = saveCompleter;
    final api = FakeApiService();
    final state = AppState(
      settingsService: settings,
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNull);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).onChanged, isNull);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .onChanged,
      isNull,
    );
    expect(settings.settings.syncOnStartup, isFalse);

    saveCompleter.complete();
    await tester.pumpAndSettle();

    expect(settings.settings.syncOnStartup, isTrue);
    expect(
      tester.widget<Switch>(find.byType(Switch).at(0)).onChanged,
      isNotNull,
    );
  });

  testWidgets('settings sync controls revert when saving fails', (tester) async {
    final settings = FakeSettingsService(settings: _signedInSettings)
      ..saveError = Exception('save failed');
    final api = FakeApiService();
    final state = AppState(
      settingsService: settings,
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();

    expect(state.settings.syncOnStartup, isFalse);
    expect(settings.settings.syncOnStartup, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);
    expect(find.text('Could not save sync settings.'), findsOneWidget);
  });

  testWidgets('settings account and storage edits stay pending before save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 1200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final settings = FakeSettingsService(
      settings: _signedInSettings.copyWith(
        serverUrl: 'https://ytnd.local:8080',
      ),
    );
    final api = FakeApiService();
    final state = AppState(
      settingsService: settings,
      apiService: api,
      syncService: SyncService(api),
      backgroundSyncService: FakeBackgroundSyncService(),
      websocketService: FakeWebsocketService(),
      shareIntentService: FakeShareIntentService(),
    );
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Server URL'),
      'https://changed.local',
    );
    final serverText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Server URL'),
        matching: find.byType(EditableText),
      ),
    );
    expect(serverText.controller.text, 'https://changed.local');
    expect(settings.settings.serverUrl, 'https://ytnd.local:8080');

    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Storage path'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Storage path'),
      'device-music',
    );
    final storageText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Storage path'),
        matching: find.byType(EditableText),
      ),
    );
    expect(storageText.controller.text, 'device-music');
    final usernameText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Username'),
        matching: find.byType(EditableText),
      ),
    );
    final passwordText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(usernameText.controller.text, 'demo');
    expect(passwordText.controller.text, 'secret');
    expect(settings.settings.storagePath, 'test-storage');
    expect(settings.settings.serverUrl, 'https://ytnd.local:8080');
  });
}
