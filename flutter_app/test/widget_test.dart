import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/main.dart';

import 'fakes.dart';

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
}
