import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production uses the bundled endpoint exclusively. Saved development settings
/// are ignored outside debug builds, including after an upgrade from a test APK.
class AppConfig {
  AppConfig(this._prefs)
    : _debugMode = kDebugMode,
      _apiBaseUrl = definedBaseUrl;

  @visibleForTesting
  factory AppConfig.forTesting(
    SharedPreferences prefs, {
    required bool debugMode,
    String apiBaseUrl = '',
  }) => AppConfig._(prefs, debugMode, apiBaseUrl);

  AppConfig._(this._prefs, this._debugMode, this._apiBaseUrl);

  final SharedPreferences _prefs;
  final bool _debugMode;
  final String _apiBaseUrl;

  static const _kBackendUrl = 'backend_url';

  /// `--dart-define=API_BASE_URL=https://...`
  static const definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Sentry crash reporting is only initialised when a DSN is provided.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Android emulator -> host loopback, where `backend/` listens by default.
  static const emulatorLocalUrl = 'http://10.0.2.2:8787';

  /// Server addresses offered in Developer tools (debug use). Production builds get theirs from --dart-define=API_BASE_URL.
  static const presets = <String, String>{
    'Local development (Android emulator)': emulatorLocalUrl,
  };

  /// The version of the terms and privacy policy a person accepts when they sign up; change it when those documents change.
  static const consentVersion = String.fromEnvironment(
    'CONSENT_VERSION',
    defaultValue: '2026-10',
  );

  /// Your website: privacy policy, terms, help and the page where people delete their account. Set it at build time with
  /// --dart-define=SITE_URL=https://example.com (no trailing slash). Without it the links say they are not set up yet.
  static const siteUrl = String.fromEnvironment('SITE_URL');

  static String _page(String path) =>
      siteUrl.isEmpty ? '' : '${siteUrl.replaceAll(RegExp(r'/+$'), '')}$path';

  /// Public pages linked from the support menu.
  static Map<String, String> get supportUrls => {
    'about': _page('/about'),
    'faq': _page('/faq'),
    'privacy': _page('/privacy'),
    'terms': _page('/terms'),
    'refund': _page('/refund-and-cancellation'),
    'changelogs': _page('/changelog'),
    'delete': _page('/delete-account'),
  };

  static const pincodeLookupUrl = 'https://api.postalpincode.in/pincode/';

  /// Release/profile: a valid bundled HTTPS endpoint only.
  /// Debug: saved override -> bundled endpoint -> emulator.
  String get baseUrl {
    if (!_debugMode) {
      return validateBaseUrl(_apiBaseUrl, allowHttp: false) == null
          ? _trim(_apiBaseUrl)
          : '';
    }
    final override = _prefs.getString(_kBackendUrl);
    if (override != null && validateBaseUrl(override) == null) {
      return _trim(override);
    }
    if (validateBaseUrl(_apiBaseUrl) == null) return _trim(_apiBaseUrl);
    return emulatorLocalUrl;
  }

  bool get isConfigured => baseUrl.isNotEmpty;
  bool get hasOverride =>
      _debugMode && (_prefs.getString(_kBackendUrl) ?? '').isNotEmpty;

  Future<void> setBaseUrl(String url) async {
    if (!_debugMode) {
      throw StateError('The service address is managed by Gymmie.');
    }
    final v = validateBaseUrl(url);
    if (v != null) throw ArgumentError(v);
    await _prefs.setString(_kBackendUrl, _trim(url));
  }

  Future<void> resetBaseUrl() async {
    if (!_debugMode) {
      throw StateError('The service address is managed by Gymmie.');
    }
    await _prefs.remove(_kBackendUrl);
  }

  bool get devToolsEnabled => _debugMode;

  static String _trim(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');

  /// Returns an error message, or null when [url] is acceptable.
  static String? validateBaseUrl(String url, {bool allowHttp = kDebugMode}) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return 'Please enter a valid URL';
    }
    if (u.scheme != 'http' && u.scheme != 'https') {
      return 'URL must start with http:// or https://';
    }
    if (u.scheme == 'http' && !allowHttp) {
      return 'Plain HTTP is blocked in release builds. Use an https:// URL.';
    }
    if (u.hasQuery || u.hasFragment) {
      return 'URL must not contain a query or fragment';
    }
    if (u.userInfo.isNotEmpty) return 'URL must not contain credentials';
    return null;
  }

  String absolute(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    return '$baseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }
}
