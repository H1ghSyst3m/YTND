import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytnd/services/settings_service.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads and saves sync on startup', () async {
    final secureValues = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          final key = args['key']?.toString() ?? '';
          switch (call.method) {
            case 'read':
              return secureValues[key];
            case 'write':
              secureValues[key] = args['value']?.toString() ?? '';
              return null;
            case 'delete':
              secureValues.remove(key);
              return null;
            default:
              return null;
          }
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
    });

    SharedPreferences.setMockInitialValues({
      'server_url': 'http://ytnd.local:8080',
      'username': 'demo',
      'sync_on_startup': true,
    });

    final service = SettingsService();
    final loaded = await service.load();

    expect(loaded.syncOnStartup, isTrue);

    await service.save(loaded.copyWith(syncOnStartup: false));
    final reloaded = await service.load();

    expect(reloaded.syncOnStartup, isFalse);
  });
}
