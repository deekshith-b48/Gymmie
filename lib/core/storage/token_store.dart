import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the auth tokens (in the platform keystore) and the selected gym id.
/// Tokens are cached in memory so the HTTP layer never awaits storage on the hot path.
///
/// A second instance with a different [prefix] (the gym-member session) keeps its own keys, so a member
/// and a staff sign-in can never read or clear each other's tokens.
class TokenStore {
  TokenStore(this._secure, this._prefs, {String prefix = ''})
    : _kAccess = '${prefix}access_token',
      _kRefresh = '${prefix}refresh_token',
      _kGym = '${prefix}current_gym_id';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  final String _kAccess;
  final String _kRefresh;
  final String _kGym;

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
