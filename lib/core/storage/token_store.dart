import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the auth tokens (in the platform keystore) and the selected gym id.
/// Tokens are cached in memory so the HTTP layer never awaits storage on the hot path.
class TokenStore {
  TokenStore(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kGym = 'current_gym_id';

  String? access;
  String? refresh;
  String? gymId;

  bool get hasSession => refresh != null && refresh!.isNotEmpty;

  Future<void> load() async {
    try {
      access = await _secure.read(key: _kAccess);
      refresh = await _secure.read(key: _kRefresh);
    } catch (_) {
      // A corrupt keystore must never brick the app: treat it as signed out.
      access = null;
      refresh = null;
      try {
        await _secure.deleteAll();
      } catch (_) {}
    }
    gymId = _prefs.getString(_kGym);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
    await _secure.write(key: _kAccess, value: accessToken);
    await _secure.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> setGym(String? id) async {
    gymId = id;
    if (id == null) {
      await _prefs.remove(_kGym);
    } else {
      await _prefs.setString(_kGym, id);
    }
  }

  Future<void> clear() async {
    access = null;
    refresh = null;
    gymId = null;
    try {
      await _secure.delete(key: _kAccess);
      await _secure.delete(key: _kRefresh);
    } catch (_) {}
    await _prefs.remove(_kGym);
  }
}
