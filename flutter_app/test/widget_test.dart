import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(YtndApp.withDefaults());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
