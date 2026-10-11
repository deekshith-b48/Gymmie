import 'dart:convert';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_store.dart';
import '../../core/util/json.dart';
import '../../data/models/user_gym.dart';
import '../../core/network/api_exception.dart';
import 'member_models.dart';
import 'native/domain/rows.dart' show asMap;
import 'native/gym_api.dart';
import 'native/log_store.dart';

/// The gym-member API (`/v5/member/*`). It owns its own [ApiClient] and [TokenStore] (key prefix
/// `member_`), so a member and a staff sign-in are two separate sessions that never share a token.
class MemberRepository implements LogApi, MemberGymApi {
  MemberRepository(this._api, this._tokens, this._prefs);

  final ApiClient _api;
  final TokenStore _tokens;
  final SharedPreferences _prefs;
  static const _kMe = 'member_me_cache';
  static const _kProfile = 'member_profile_cache';
  static const _kAttendance = 'member_attendance_cache';
  static const _kPlans = 'member_plans_cache';
  static const _kAccount = 'member_account_cache';
  static const _kSessions = 'member_sessions_cache';
  static const _kRequests = 'member_requests_cache';
  static const _kPrivacy = 'member_privacy_cache';
  static const _kNotif = 'member_notifications_cache';
  static const _kPhoto = 'member_photo_cache';

  static const _cacheKeys = [_kMe, _kProfile, _kAttendance, _kPlans, _kAccount, _kSessions, _kRequests, _kPrivacy, _kNotif, _kPhoto];

  TokenStore get tokens => _tokens;
  Stream<void> get onSessionExpired => _api.onSessionExpired;

  Future<String> _deviceName() async {
    try {
      final i = await DeviceInfoPlugin().androidInfo;
      return '${i.manufacturer} ${i.model}'.trim();
    } catch (_) {
      return 'Mobile device';
    }
  }

  /// Always succeeds for a well-formed number (the server does not reveal who is a member).
  Future<OtpChallenge> requestOtp({
    required String phone,
    String? gymCode,
  }) async {
    final r = await _api.post(
      '/v5/member/auth/otp',
      body: compact({'phone': phone, 'gymCode': gymCode}),
      auth: false,
      gym: false,
    );
    return OtpChallenge.fromJson(r.map);
  }

  Future<MemberAuthResult> verifyOtp(String requestId, String otp) async {
    final r = await _api.post(
      '/v5/member/auth/otp/verify',
      body: {'requestId': requestId, 'otp': otp, 'device': await _deviceName()},
      auth: false,
      gym: false,
    );
    return _accept(r.map);
  }

  /// Signs in with the access code the gym gave the member. One answer for every failure, so it cannot be used to find out which codes exist.
  Future<MemberAuthResult> loginWithCode(String code) async {
    final r = await _api.post(
      '/v5/member/auth/code',
      body: {'code': code.trim(), 'device': await _deviceName()},
      auth: false,
      gym: false,
    );
    return _accept(r.map);
  }

  Future<MemberAuthResult> selectGym(String selectionToken, String gymId) async {
    final r = await _api.post(
      '/v5/member/auth/select-gym',
      body: {
        'selectionToken': selectionToken,
        'gymId': gymId,
        'device': await _deviceName(),
      },
      auth: false,
      gym: false,
    );
    return _accept(r.map);
  }

  /// Stores the member tokens of a unified sign-in bundle.
  Future<MemberAuthResult> acceptBundle(Json d) => _accept(d);

  Future<MemberAuthResult> _accept(Json d) async {
    if (d.s('status') == 'select_gym') {
      return MemberAuthResult(
        gyms: [for (final g in d.list('gyms')) MemberGym.fromJson(g)],
        selectionToken: d.s('selectionToken'),
      );
    }
    await _tokens.saveTokens(
      accessToken: d.s('accessToken'),
      refreshToken: d.s('refreshToken'),
    );
    return MemberAuthResult(
      memberName: d.obj('member')?.str('name'),
      gym: d.obj('gym') == null ? null : MemberGym.fromJson(d.obj('gym')!),
    );
  }

  Future<MemberOverview> me() async {
    final raw = (await _api.get('/v5/member/me', gym: false)).map;
    await _prefs.setString(_kMe, jsonEncode(raw)); // so the app can open offline
    return MemberOverview.fromJson(raw);
  }

  /// The last overview the server gave this phone (null on first launch or after sign-out).
  MemberOverview? cachedOverview() {
    final s = _prefs.getString(_kMe);
    if (s == null) return null;
    try {
      return MemberOverview.fromJson(asMap(jsonDecode(s)));
    } catch (_) {
      return null;
    }
  }

  /// Ends the session on the server (best effort) and forgets the tokens.
  Future<void> logout() async {
    try {
      await _api.post('/v5/member/auth/logout', gym: false);
    } catch (_) {
      // Offline: the tokens still go, the server session expires on its own.
    }
    await _tokens.clear();
    for (final k in _cacheKeys) {
      await _prefs.remove(k);
    }
  }

  /// Ends every session this member has, on every phone. Needs the network (the sessions live on the server).
  Future<void> logoutAll() async {
    await _api.post('/v5/member/auth/logout-all', gym: false);
    await _tokens.clear();
    for (final k in _cacheKeys) {
      await _prefs.remove(k);
    }
  }

  // ---- gym side (MemberGymApi): cached so the screens open offline ------------------------------------------------

  Future<T> _cached<T>(String key, Future<Json> Function() fetch, T Function(Json) parse) async {
    try {
      final raw = (await fetch());
      await _prefs.setString(key, jsonEncode(raw));
      return parse(raw);
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final c = _prefs.getString(key);
      if (c == null) rethrow;
      return parse(asMap(jsonDecode(c)));
    }
  }

  @override
  Future<MemberProfile> profile() => _cached(_kProfile, () async => (await _api.get('/v5/member/me/profile', gym: false)).map, MemberProfile.fromJson);

  @override
  Future<AttendanceSummary> attendance({int days = 90}) => _cached(
    _kAttendance, () async => (await _api.get('/v5/member/me/attendance', query: {'days': days}, gym: false)).map, AttendanceSummary.fromJson,
  );

  @override
  Future<AssignedPlans> plans() => _cached(_kPlans, () async => (await _api.get('/v5/member/me/plans', gym: false)).map, AssignedPlans.fromJson);

  @override
  Future<bool> paymentsOnline() async {
    try {
      return (await _api.get('/v5/member/me/payment-options', gym: false)).map.b('online');
    } on ApiException {
      return false;
    }
  }

  @override
  Future<String> paymentLink({double? amount}) async =>
      (await _api.post('/v5/member/me/payment-link', body: {'amount': ?amount}, gym: false)).map.s('url');

  // ---- account ------------------------------------------------------------------------------------------------------

  /// A list answer, cached under [key] like [_cached] does for objects.
  Future<List<T>> _cachedList<T>(String key, String path, T Function(Json) parse) async {
    try {
      final r = (await _api.get(path, gym: false)).list;
      await _prefs.setString(key, jsonEncode(r));
      return [for (final x in r) parse(x)];
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final c = _prefs.getString(key);
      if (c == null) rethrow;
      return [for (final x in jsonDecode(c) as List) parse(asMap(x))];
    }
  }

  Future<MemberAccount> _saved(String key, Json raw) async {
    await _prefs.setString(key, jsonEncode(raw));
    return MemberAccount.fromJson(raw);
  }

  @override
  Future<MemberAccount> account() => _cached(_kAccount, () async => (await _api.get('/v5/member/me/account', gym: false)).map, MemberAccount.fromJson);

  @override
  Future<MemberAccount> updateAccount(Map<String, dynamic> changes) async =>
      _saved(_kAccount, (await _api.patch('/v5/member/me/account', body: changes, gym: false)).map);

  @override
  Future<Uint8List?> photo() async {
    try {
      final b = await _api.bytes('/v5/member/me/photo', gym: false);
      await _prefs.setString(_kPhoto, base64Encode(b));
      return b;
    } on ApiException catch (e) {
      if (e.status == 404) {
        await _prefs.remove(_kPhoto);
        return null;
      }
      if (!e.isNetwork) rethrow;
      final c = _prefs.getString(_kPhoto);
      return c == null ? null : base64Decode(c);
    }
  }

  @override
  Future<MemberAccount> setPhoto(Uint8List bytes, String contentType) async {
    final raw = (await _api.put('/v5/member/me/photo', body: {'data': base64Encode(bytes), 'contentType': contentType}, gym: false)).map;
    await _prefs.setString(_kPhoto, base64Encode(bytes));
    return _saved(_kAccount, raw);
  }

  @override
  Future<MemberAccount> removePhoto() async {
    await _api.delete('/v5/member/me/photo', gym: false);
    await _prefs.remove(_kPhoto);
    return account();
  }

  @override
  Future<OtpChallenge> requestPhoneChange(String phone) async =>
      OtpChallenge.fromJson((await _api.post('/v5/member/me/phone/otp', body: {'phone': phone}, gym: false)).map);

  @override
  Future<String> verifyPhoneChange(String requestId, String otp) async {
    final r = (await _api.post('/v5/member/me/phone/verify', body: {'requestId': requestId, 'otp': otp}, gym: false)).map;
    await _prefs.remove(_kAccount);
    await _prefs.remove(_kMe);
    return r.s('phone');
  }

  @override
  Future<List<DeviceSession>> sessions() => _cachedList(_kSessions, '/v5/member/me/sessions', DeviceSession.fromJson);

  @override
  Future<void> endSession(String id) async {
    await _api.delete('/v5/member/me/sessions/$id', gym: false);
  }

  @override
  Future<void> endOtherSessions() async {
    await _api.post('/v5/member/me/sessions/revoke-others', gym: false);
  }

  @override
  Future<OtpChallenge> requestDeleteCode() async =>
      OtpChallenge.fromJson((await _api.post('/v5/member/me/account/delete-otp', gym: false)).map);

  @override
  Future<void> deleteAccount({required String requestId, required String otp}) async {
    await _api.delete('/v5/member/me/account', body: {'requestId': requestId, 'otp': otp, 'confirm': 'DELETE'}, gym: false);
    await _tokens.clear();
    for (final k in _cacheKeys) {
      await _prefs.remove(k);
    }
  }

  @override
  Future<List<MembershipRequest>> requests() => _cachedList(_kRequests, '/v5/member/me/requests', MembershipRequest.fromJson);

  @override
  Future<MembershipRequest> createRequest({required String type, String? planId, String? note}) async =>
      MembershipRequest.fromJson((await _api.post('/v5/member/me/requests', body: compact({'type': type, 'planId': planId, 'note': note}), gym: false)).map);

  @override
  Future<void> withdrawRequest(String id) async {
    await _api.delete('/v5/member/me/requests/$id', gym: false);
  }

  @override
  Future<PrivacySettings> privacy() => _cached(_kPrivacy, () async => (await _api.get('/v5/member/me/privacy', gym: false)).map, PrivacySettings.fromJson);

  @override
  Future<PrivacySettings> setPrivacy({Map<String, bool>? trainerCanSee, String? shareTraining}) async {
    final raw = (await _api.put('/v5/member/me/privacy', body: compact({'trainerCanSee': trainerCanSee, 'shareTraining': shareTraining}), gym: false)).map;
    await _prefs.setString(_kPrivacy, jsonEncode(raw));
    return PrivacySettings.fromJson(raw);
  }

  @override
  Future<NotificationSettings> notifications() => _cached(_kNotif, () async => (await _api.get('/v5/member/me/notifications', gym: false)).map, NotificationSettings.fromJson);

  @override
  Future<NotificationSettings> setNotifications({bool? announcements, bool? expiryOn, int? expiryDaysBefore}) async {
    final body = <String, dynamic>{
      if (announcements != null) 'announcements': {'on': announcements},
      if (expiryOn != null || expiryDaysBefore != null) 'membershipExpiry': compact({'on': expiryOn, 'daysBefore': expiryDaysBefore}),
    };
    final raw = (await _api.put('/v5/member/me/notifications', body: body, gym: false)).map;
    await _prefs.setString(_kNotif, jsonEncode(raw));
    return NotificationSettings.fromJson(raw);
  }

  // ---- training log (LogApi) ------------------------------------------------------------------------------------

  LogDoc _doc(Json d) => LogDoc(d.i('rev'), d.str('wid'), d.obj('state'));

  @override
  Future<LogDoc> fetchLog() async {
    try {
      return _doc((await _api.get('/v5/member/data', gym: false)).map);
    } on ApiException catch (e) {
      if (e.isNetwork) throw const LogOffline();
      rethrow;
    }
  }

  @override
  Future<LogDoc> pushLog(Json state, int baseRev) async {
    try {
      return _doc((await _api.put('/v5/member/data', body: {'state': state, 'baseRev': baseRev}, gym: false)).map);
    } on ApiException catch (e) {
      if (e.status == 409) {
        final d = e.details ?? const <String, dynamic>{};
        throw LogConflict(LogDoc((d['rev'] as num?)?.toInt() ?? 0, d['wid'] as String?, d['state'] == null ? null : asMap(d['state'])));
      }
      if (e.isNetwork) throw const LogOffline();
      rethrow;
    }
  }

  @override
  Future<void> eraseLog() async {
    await _api.delete('/v5/member/data', gym: false);
  }
}
