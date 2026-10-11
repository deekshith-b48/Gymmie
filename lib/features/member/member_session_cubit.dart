import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_exception.dart';
import 'member_models.dart';
import 'member_repository.dart';

enum MemberStatus { signedOut, signedIn }

class MemberSessionState extends Equatable {
  const MemberSessionState({
    this.status = MemberStatus.signedOut,
    this.overview,
    this.error,
    this.loading = false,
    this.welcome = false,
  });

  final MemberStatus status;
  final MemberOverview? overview;
  final ApiException? error;
  final bool loading;

  /// True from a fresh sign-in until the welcome screen has been shown; a session restored at start-up never sets it.
  final bool welcome;

  bool get signedIn => status == MemberStatus.signedIn;

  @override
  List<Object?> get props => [
    status,
    overview?.name,
    overview?.membership?.status,
    overview?.membership?.endDate,
    overview?.visitsLast30,
    error?.code,
    loading,
    welcome,
  ];
}

/// Who the signed-in gym member is. `AppRoot` shows the member app while [MemberSessionState.signedIn]
/// and the staff app otherwise. A saved session is trusted at start-up (tokens are loaded before the
/// first frame) and then confirmed with the server.
class MemberSessionCubit extends Cubit<MemberSessionState> {
  MemberSessionCubit(this._repo)
    : super(
        MemberSessionState(
          status: _repo.tokens.hasSession
              ? MemberStatus.signedIn
              : MemberStatus.signedOut,
          overview: _repo.tokens.hasSession ? _repo.cachedOverview() : null,
        ),
      ) {
    _sub = _repo.onSessionExpired.listen((_) => _clear());
  }

  final MemberRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> boot() async {
    if (!state.signedIn) return;
    await refresh();
  }

  Future<void> refresh() async {
    emit(MemberSessionState(status: state.status, overview: state.overview, loading: true, welcome: state.welcome));
    try {
      final o = await _repo.me();
      emit(MemberSessionState(status: MemberStatus.signedIn, overview: o, welcome: state.welcome));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        // Blocked, removed, feature switched off or session revoked: back to the login page.
        await _repo.tokens.clear();
        emit(const MemberSessionState());
      } else {
        emit(MemberSessionState(status: state.status, overview: state.overview, error: e, welcome: state.welcome));
      }
    }
  }

  /// Called after a verified code (or a picked gym).
  Future<void> signedIn() async {
    emit(const MemberSessionState(status: MemberStatus.signedIn, loading: true, welcome: true));
    await refresh();
  }

  /// The welcome screen has had its moment: on to the dashboard.
  void dismissWelcome() {
    if (!state.welcome) return;
    emit(MemberSessionState(status: state.status, overview: state.overview, error: state.error, loading: state.loading));
  }

  Future<void> signOut() async {
    await _repo.logout();
    emit(const MemberSessionState());
  }

  /// Ends this member's sessions on every phone (the server holds them). Throws, and changes nothing, when the
  /// server cannot be reached. The caller then clears its own data and calls [signOut] to leave the app.
  Future<void> revokeEverywhere() => _repo.logoutAll();

  Future<void> _clear() async {
    await _repo.tokens.clear();
    emit(const MemberSessionState());
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
