import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_store.dart';
import '../../core/util/json.dart';
import '../models/user_gym.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<String> _deviceName() async {
    try {
      final i = await DeviceInfoPlugin().androidInfo;
      return '${i.manufacturer} ${i.model}'.trim();
    } catch (_) {
      return 'Mobile device';
    }
  }

  Future<AppSettings> appSettings() async => AppSettings.fromJson(
    (await _api.get('/v5/apps/configs/settings', auth: false, gym: false)).map,
  );

  Future<OtpChallenge> requestLoginOtp({
    String? phone,
    String? email,
    String? channel,
  }) async {
    final r = await _api.post(
      '/v5/auth/login/otp',
      body: compact({'phone': phone, 'email': email, 'channel': channel}),
      auth: false,
      gym: false,
    );
    return OtpChallenge.fromJson(r.map);
  }

  Future<AuthResult> verifyLoginOtp(String requestId, String otp) async {
    final r = await _api.post(
      '/v5/auth/login/otp/verify',
      body: {'requestId': requestId, 'otp': otp, 'device': await _deviceName()},
      auth: false,
      gym: false,
    );
    return _accept(r.map);
  }

  Future<OtpChallenge> registerPartner({
    required String name,
    required String phone,
    String? email,
    String? referralCode,
    String channel = 'sms',
  }) async {
    final r = await _api.post(
      '/v5/register/partner',
      body: compact({
        'name': name,
        'phone': phone,
        'email': email,
        'referralCode': referralCode,
        'channel': channel,
        'consentVersion': AppConfig.consentVersion,
      }),
      auth: false,
      gym: false,
    );
    return OtpChallenge.fromJson(r.map);
  }

  Future<AuthResult> verifyRegistration(String requestId, String otp) async {
    final r = await _api.post(
      '/v5/register/partner/verify',
      body: {'requestId': requestId, 'otp': otp},
      auth: false,
      gym: false,
    );
    return _accept(r.map);
  }

  Future<GymBrief> createFirstGym(Json body) async {
    final r = await _api.post(
      '/v5/register/partner/gym',
      body: body,
      gym: false,
    );
    return GymBrief.fromJson(r.map.obj('gym') ?? {});
  }

  Future<GymBrief> addGym(Json body) async => GymBrief.fromJson(
    (await _api.post('/v5/gyms', body: body, gym: false)).map,
  );

  Future<void> completeOnboarding() async =>
      _api.post('/v5/register/partner/complete');

  Future<({AppUser user, List<GymBrief> gyms})> me() async {
    final r = (await _api.get('/v5/users/self', gym: false)).map;
    return (
      user: AppUser.fromJson(r.obj('user') ?? {}),
      gyms: r.list('gyms').map(GymBrief.fromJson).toList(),
    );
  }

  Future<GymProfile> gymProfile(String id) async =>
      GymProfile.fromJson((await _api.get('/v5/gyms/$id')).map);

  Future<AppUser> updateProfile(Json patch) async => AppUser.fromJson(
    (await _api.patch(
          '/v5/users/self',
          body: patch,
          gym: false,
        )).map.obj('user') ??
        {},
  );

  Future<AppUser> uploadProfilePhoto(
    List<int> bytes,
    String contentType,
  ) async {
    final r = await _api.post(
      '/v5/users/self/photo',
      body: {'data': base64Encode(bytes), 'contentType': contentType},
      gym: false,
    );
    return AppUser.fromJson(r.map.obj('user') ?? {});
  }

  /// Contact verification: add or change the phone / email on the account.
  Future<OtpChallenge> requestContactOtp({
    required String channel,
    required String target,
  }) async => OtpChallenge.fromJson(
    (await _api.post(
      '/v3/users/self/otp',
      body: {'channel': channel, 'target': target},
      gym: false,
    )).map,
  );

  Future<AppUser> verifyContactOtp(String requestId, String otp) async =>
      AppUser.fromJson(
        (await _api.post(
              '/v3/users/self/otp/verify',
              body: {'requestId': requestId, 'otp': otp},
              gym: false,
            )).map.obj('user') ??
            {},
      );

  Future<void> logout() async {
    try {
      await _api.post('/v3/auth/logout', gym: false);
    } catch (_) {
      // Even if the server is unreachable the local session must end.
    }
    await _tokens.clear();
  }

  Future<void> logoutEverywhere() async {
    try {
      await _api.post('/v5/users/self/revoke-sessions', gym: false);
    } finally {
      await _tokens.clear();
    }
  }

  // ---- closing the account ----------------------------------------------------------------------------------------

  /// Sends a code to the account's own phone (or email) to confirm closing it. The server refuses owners of a gym.
  Future<OtpChallenge> requestAccountDeletion() async =>
      OtpChallenge.fromJson((await _api.post('/v5/users/self/delete-otp', gym: false)).map);

  Future<void> deleteAccount({required String requestId, required String otp}) async {
    await _api.delete('/v5/users/self', body: {'requestId': requestId, 'otp': otp, 'confirm': 'DELETE'}, gym: false);
    await _tokens.clear();
  }

  // ---- one sign-in for owners, staff and members --------------------------------------------------------------

  /// Sends one code to the phone. The answer is the same whether or not the number belongs to anyone.
  Future<OtpChallenge> requestSignin({required String phone, String channel = 'sms'}) async =>
      OtpChallenge.fromJson(
        (await _api.post('/v5/auth/signin/otp', body: {'phone': phone, 'channel': channel}, auth: false, gym: false)).map,
      );

  /// What the proven number is: `{status:'signed_in', kind:'staff'|'member', ...tokens}` or `{status:'choose', options, selectionToken}`.
  Future<Json> verifySignin(String requestId, String otp) async => (await _api.post(
    '/v5/auth/signin/verify',
    body: {'requestId': requestId, 'otp': otp, 'device': await _deviceName()},
    auth: false,
    gym: false,
  )).map;

  Future<Json> chooseSignin(String selectionToken, String option) async => (await _api.post(
    '/v5/auth/signin/choose',
    body: {'selectionToken': selectionToken, 'option': option, 'device': await _deviceName()},
    auth: false,
    gym: false,
  )).map;

  /// Stores the staff tokens of a sign-in bundle and returns who signed in.
  Future<AuthResult> acceptStaff(Json d) => _accept(d);

  Future<AuthResult> _accept(Json d) async {
    await _tokens.saveTokens(
      accessToken: d.s('accessToken'),
      refreshToken: d.s('refreshToken'),
    );
    return AuthResult(
      user: AppUser.fromJson(d.obj('user') ?? {}),
      gyms: d.list('gyms').map(GymBrief.fromJson).toList(),
      isNewUser: d.b('isNewUser'),
      nextStep: d.str('nextStep'),
    );
  }
}
