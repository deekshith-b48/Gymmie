import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://old-dev-server:8787',
      'dev_tools_enabled': true,
    });
    prefs = await SharedPreferences.getInstance();
  });

  test(
    'production ignores a saved endpoint and hidden developer unlock',
    () async {
      final config = AppConfig.forTesting(
        prefs,
        debugMode: false,
        apiBaseUrl: 'https://api.gymmie.test/',
      );
      expect(config.baseUrl, 'https://api.gymmie.test');
      expect(
        config.absolute('/v5/member/me'),
        'https://api.gymmie.test/v5/member/me',
      );
      expect(config.devToolsEnabled, isFalse);
      expect(config.hasOverride, isFalse);
      await expectLater(
        config.setBaseUrl('https://other.test'),
        throwsStateError,
      );
      await expectLater(config.resetBaseUrl(), throwsStateError);
      expect(config.baseUrl, 'https://api.gymmie.test');
    },
  );

  test('production never falls back to an old server or emulator', () {
    for (final endpoint in [
      '',
      'http://api.test',
      'https://user:pass@api.test',
      'https://api.test?token=x',
      'https://api.test#x',
      'not-a-url',
    ]) {
      final config = AppConfig.forTesting(
        prefs,
        debugMode: false,
        apiBaseUrl: endpoint,
      );
      expect(config.isConfigured, isFalse, reason: endpoint);
      expect(config.baseUrl, isEmpty, reason: endpoint);
    }
  });

  test('debug builds retain local development support', () async {
    final config = AppConfig.forTesting(prefs, debugMode: true);
    expect(config.baseUrl, 'http://old-dev-server:8787');
    await config.resetBaseUrl();
    expect(config.baseUrl, AppConfig.emulatorLocalUrl);
    await config.setBaseUrl('http://localhost:8787/');
    expect(config.baseUrl, 'http://localhost:8787');
  });
}
