import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/models/app_settings.dart';

void main() {
  test('sync on startup defaults to false and copies explicitly', () {
    const defaults = AppSettings();

    expect(defaults.syncOnStartup, isFalse);

    final enabled = defaults.copyWith(syncOnStartup: true);

    expect(enabled.syncOnStartup, isTrue);
    expect(enabled.copyWith(username: 'demo').syncOnStartup, isTrue);
    expect(enabled.copyWith(syncOnStartup: false).syncOnStartup, isFalse);
  });
}
