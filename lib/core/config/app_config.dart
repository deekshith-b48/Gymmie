import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build-time + user-selectable configuration.
///
/// Nothing secret is compiled in. Values come from `--dart-define` (see docs/BUILD.md) or, for the
/// backend URL, from the in-app "Developer tools" screen (the original app has the same feature:
/// "Backend URL", "Dev URL", "Change URL").
class AppConfig {
  AppConfig(this._prefs);

  final SharedPreferences _prefs;

  static const _kBackendUrl = 'backend_url';
  static const _kShowDevTools = 'dev_tools_enabled';

  /// `--dart-define=API_BASE_URL=https://...`
  static const definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Sentry crash reporting is only initialised when a DSN is provided.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Firebase (push notifications / analytics) is only initialised when all of these are provided.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  /// Android emulator -> host loopback, where `backend/` listens by default.
  static const emulatorLocalUrl = 'http://10.0.2.2:8787';

  /// Hosts found in the original app's string table. Shown as presets in Developer tools only;
  /// the reconstructed app never selects one of them by itself.
  static const presets = <String, String>{
    'Local development (Android emulator)': emulatorLocalUrl,
    'Original production host': 'https://api.dgymbook.com',
    'Original staging host': 'https://api.staging.dgymbook.com',
    'Original dev host 1': 'https://api1.dev.dgymbook.com',
    'Original dev host 2': 'https://api2.dev.dgymbook.com',
  };

  /// Public pages linked from the app's support menu (URLs recovered from the original app).
  static const supportUrls = <String, String>{
    'about': 'https://dgymbook.com/about',
    'faq': 'https://dgymbook.com/faq',
    'privacy': 'https://dgymbook.com/privacy',
    'terms': 'https://dgymbook.com/terms',
    'refund': 'https://dgymbook.com/refund-and-cancellation',
    'changelogs': 'https://dgymbook.com/changelogs',
  };

  static const pincodeLookupUrl = 'https://api.postalpincode.in/pincode/';

  /// Resolution order: user override -> --dart-define -> debug default -> unconfigured ('').
  String get baseUrl {
    final override = _prefs.getString(_kBackendUrl);
    if (override != null && override.isNotEmpty) return override;
    if (definedBaseUrl.isNotEmpty) return _trim(definedBaseUrl);
    return kDebugMode ? emulatorLocalUrl : '';
  }

  bool get isConfigured => baseUrl.isNotEmpty;
  bool get hasOverride => (_prefs.getString(_kBackendUrl) ?? '').isNotEmpty;

  Future<void> setBaseUrl(String url) async {
    final v = validateBaseUrl(url);
    if (v != null) throw ArgumentError(v);
    await _prefs.setString(_kBackendUrl, _trim(url));
  }

  Future<void> resetBaseUrl() => _prefs.remove(_kBackendUrl);

  bool get devToolsEnabled =>
      kDebugMode || (_prefs.getBool(_kShowDevTools) ?? false);
  Future<void> setDevToolsEnabled(bool v) => _prefs.setBool(_kShowDevTools, v);

  static String _trim(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');

  /// Returns an error message, or null when [url] is acceptable.
  static String? validateBaseUrl(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return 'Please enter a valid URL';
    }
    if (u.scheme != 'http' && u.scheme != 'https') {
      return 'URL must start with http:// or https://';
    }
    if (u.scheme == 'http' && !kDebugMode) {
      return 'Plain HTTP is blocked in release builds. Use an https:// URL.';
    }
    if (u.hasQuery || u.hasFragment) {
      return 'URL must not contain a query or fragment';
    }
    return null;
  }

  String absolute(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    return '$baseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }
}
