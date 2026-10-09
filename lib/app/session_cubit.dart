import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/auth/permissions.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/storage/token_store.dart';
import '../core/util/format.dart';
import '../data/models/user_gym.dart';
import '../data/repositories/auth_repository.dart';

enum SessionStatus { booting, signedOut, signedIn }

class SessionState extends Equatable {
  const SessionState({
    this.status = SessionStatus.booting,
    this.user,
    this.gyms = const [],
    this.profile,
    this.settings = const AppSettings(),
    this.catalog,
    this.bootError,
    this.profileError,
  });

  final SessionStatus status;
  final AppUser? user;
  final List<GymBrief> gyms;
  final GymProfile? profile;
  final AppSettings settings;
  final FeatureCatalog? catalog;
  final ApiException? bootError;
  final ApiException? profileError;

  bool get signedIn => status == SessionStatus.signedIn;
  bool get hasGym => profile != null;
  String get role => profile?.role ?? 'staff';
  bool can(String perm) => roleCan(profile?.role, perm);
  bool feature(String key) => profile?.feature(key, catalog) ?? false;
  bool get subscriptionExpired => profile?.subscription?.expired ?? false;

  SessionState copyWith({
    SessionStatus? status,
    AppUser? user,
    List<GymBrief>? gyms,
    GymProfile? profile,
    bool clearProfile = false,
    AppSettings? settings,
    FeatureCatalog? catalog,
    ApiException? bootError,
    bool clearBootError = false,
    ApiException? profileError,
    bool clearProfileError = false,
  }) => SessionState(
    status: status ?? this.status,
    user: user ?? this.user,
    gyms: gyms ?? this.gyms,
    profile: clearProfile ? null : (profile ?? this.profile),
    settings: settings ?? this.settings,
    catalog: catalog ?? this.catalog,
    bootError: clearBootError ? null : (bootError ?? this.bootError),
    profileError: clearProfileError
        ? null
        : (profileError ?? this.profileError),
  );

  @override
  List<Object?> get props => [
    status,
    user?.id,
    user?.name,
    user?.language,
    user?.photoUrl,
    gyms.map((g) => g.id).join(),
    profile?.id,
    profile?.hashCode,
    settings.maintenanceMode,
    bootError?.code,
    profileError?.code,
    catalog?.defs.length,
  ];
}

/// Owns who is signed in and which gym is selected. The router redirects off this state.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth, this._tokens, this._api)
    : super(const SessionState()) {
    _expiredSub = _api.onSessionExpired.listen((_) => _clear());
  }

  final AuthRepository _auth;
  final TokenStore _tokens;
  final ApiClient _api;
  StreamSubscription<void>? _expiredSub;

  Future<void> boot() async {
    await _tokens.load();
    FeatureCatalog? catalog;
    try {
      catalog = await FeatureCatalog.load();
    } catch (_) {}
    var settings = const AppSettings();
    try {
      settings = await _auth.appSettings();
    } catch (_) {
      // Offline at launch: continue with defaults; sign-in will surface connectivity problems.
    }
    if (!_tokens.hasSession) {
      emit(
        state.copyWith(
          status: SessionStatus.signedOut,
          settings: settings,
          catalog: catalog,
          clearBootError: true,
        ),
      );
      return;
    }
    emit(state.copyWith(settings: settings, catalog: catalog));
    await _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final me = await _auth.me();
      emit(
        state.copyWith(
          status: SessionStatus.signedIn,
          user: me.user,
          gyms: me.gyms,
          clearBootError: true,
        ),
      );
      await _chooseGym(me.gyms);
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _clear();
      } else {
        // Offline / server problem: stay signed in with whatever we have so the UI can retry.
        emit(state.copyWith(status: SessionStatus.signedIn, bootError: e));
      }
    }
  }

  Future<void> retryBoot() async {
    emit(state.copyWith(clearBootError: true));
    await _loadSession();
  }

  Future<void> _chooseGym(List<GymBrief> gyms) async {
    String? id = _tokens.gymId;
    if (id != null && !gyms.any((g) => g.id == id)) id = null;
    if (id == null && gyms.length == 1) id = gyms.first.id;
    if (id == null) {
      await _tokens.setGym(null);
      emit(state.copyWith(clearProfile: true));
      return;
    }
    await _tokens.setGym(id);
    await _loadProfile(id);
  }

  Future<void> _loadProfile(String id) async {
    try {
      final p = await _auth.gymProfile(id);
      Fmt.currencySymbol = p.currencySymbol;
      emit(state.copyWith(profile: p, clearProfileError: true));
    } on ApiException catch (e) {
      emit(state.copyWith(profileError: e));
    }
  }

  Future<void> refreshProfile() async {
    final id = _tokens.gymId;
    if (id != null) await _loadProfile(id);
  }

  Future<void> refreshGyms() async {
    final me = await _auth.me();
    emit(state.copyWith(user: me.user, gyms: me.gyms));
  }

  /// Called after OTP sign-in / registration.
  Future<void> signedIn(AuthResult r) async {
    emit(
      state.copyWith(
        status: SessionStatus.signedIn,
        user: r.user,
        gyms: r.gyms,
        clearProfile: true,
        clearBootError: true,
      ),
    );
    await _chooseGym(r.gyms);
  }

  Future<void> selectGym(String id) async {
    await _tokens.setGym(id);
    emit(state.copyWith(clearProfile: true));
    await _loadProfile(id);
  }

  Future<void> afterGymCreated(GymBrief gym) async {
    await refreshGyms();
    await selectGym(gym.id);
  }

  void updateUser(AppUser u) => emit(state.copyWith(user: u));

  Future<void> signOut({bool everywhere = false}) async {
    if (everywhere) {
      try {
        await _auth.logoutEverywhere();
      } catch (_) {
        await _tokens.clear();
      }
    } else {
      await _auth.logout();
    }
    await _clear();
  }

  Future<void> _clear() async {
    await _tokens.clear();
    emit(
      SessionState(
        status: SessionStatus.signedOut,
        settings: state.settings,
        catalog: state.catalog,
      ),
    );
  }

  @override
  Future<void> close() {
    _expiredSub?.cancel();
    return super.close();
  }
}
