import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ytnd/main.dart';
import 'package:ytnd/models/app_settings.dart';
import 'package:ytnd/models/song.dart';
import 'package:ytnd/screens/library_screen.dart';
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

    expect(find.text('Your synced library'), findsOneWidget);
    expect(find.text('Search library'), findsOneWidget);
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 79'), findsNothing);
    expect(state.coverUrlRequests, greaterThan(0));
    expect(state.coverUrlRequests, lessThan(api.songs.length));
  });
}
