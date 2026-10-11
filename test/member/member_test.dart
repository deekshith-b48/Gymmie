import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/data/models/members.dart';
import 'package:gym_book_app/data/models/messaging.dart';
import 'package:gym_book_app/core/auth/permissions.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/core/storage/token_store.dart';
import 'package:gym_book_app/data/models/user_gym.dart';
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/member_repository.dart';
import 'package:gym_book_app/features/member/member_session_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements MemberRepository {}

class _Tokens extends Mock implements TokenStore {}

MemberOverview _overview() => MemberOverview.fromJson({
  'member': {'id': 'm1', 'name': 'Asha Rao', 'admissionNo': 7},
  'gym': {'id': 'g1', 'code': '123456', 'name': 'Iron Temple', 'currencySymbol': '₹'},
  'membership': {
    'planName': 'Monthly',
    'startDate': '2026-10-01',
    'endDate': '2026-10-30',
    'status': 'active',
    'daysLeft': 20,
    'balance': 300,
  },
  'trainer': {'name': 'Tarun'},
  'visitsLast30': 9,
  'qrPayload': 'dgymbook://member/123456/m1',
  'mediaBase': 'https://log.example.com',
});

({_Repo repo, _Tokens tokens}) _fakes({required bool hasSession}) {
  final repo = _Repo();
  final tokens = _Tokens();
  when(() => tokens.hasSession).thenReturn(hasSession);
  when(() => tokens.clear()).thenAnswer((_) async {});
  when(() => repo.tokens).thenReturn(tokens);
  when(() => repo.onSessionExpired).thenAnswer((_) => const Stream.empty());
  return (repo: repo, tokens: tokens);
}

void main() {
  test('MemberOverview parses the whitelisted /me payload', () {
    final o = _overview();
    expect(o.name, 'Asha Rao');
    expect(o.gym.code, '123456');
    expect(o.membership!.daysLeft, 20);
    expect(o.membership!.balance, 300);
    expect(o.trainerName, 'Tarun');
    expect(o.qrPayload, 'dgymbook://member/123456/m1');
    expect(o.mediaBase, 'https://log.example.com');
    expect(o.id, 'm1');
  });

  test('a payload with no membership or trainer still parses', () {
    final o = MemberOverview.fromJson({'member': {'name': 'X'}, 'gym': {'id': 'g'}, 'qrPayload': 'q'});
    expect(o.membership, isNull);
    expect(o.trainerName, isNull);
  });

  test('the owner\'s view of a member carries the app status and the member\'s own promotions choice', () {
    final base = {'id': 'm1', 'name': 'Asha', 'phone': '+919900000101', 'admissionNo': 7};
    final quiet = MemberDetail.fromJson({...base, 'memberApp': {'enabled': true, 'lastSeenAt': '2026-10-09T10:00:00Z', 'signIns': 3, 'broadcasts': false}});
    expect(quiet.appEnabled, isTrue);
    expect(quiet.appSignIns, 3);
    expect(quiet.appBroadcasts, isFalse);
    // an older server says nothing about it: promotions are on until the member says otherwise
    final old = MemberDetail.fromJson({...base, 'memberApp': {'enabled': true, 'signIns': 0}});
    expect(old.appBroadcasts, isTrue);
    expect(MemberDetail.fromJson(base).appEnabled, isFalse);
    final preview = RecipientPreview.fromJson({'count': 12, 'creditsRequired': 12, 'balance': 100, 'tooMany': false, 'optedOut': 3});
    expect(preview.optedOut, 3);
    expect(RecipientPreview.fromJson({'count': 1, 'creditsRequired': 1, 'balance': 1, 'tooMany': false}).optedOut, 0);
  });

  test('a member\'s preferences parse, defaulting to on', () {
    expect(MemberPrefs.fromJson({'broadcasts': false, 'updatedAt': '2026-10-10T00:00:00Z'}).broadcasts, isFalse);
    expect(MemberPrefs.fromJson(const {}).broadcasts, isTrue);
  });

  test('the staff permission matrix gives a member nothing', () {
    expect(roleCan('member', Perm.membersRead), isFalse);
    expect(roleCan('member', Perm.plansetsRead), isFalse);
  });

  group('MemberSessionCubit', () {
    test('trusts a saved session on start and nothing when there is none', () {
      final a = _fakes(hasSession: true);
      final b = _fakes(hasSession: false);
      expect(MemberSessionCubit(a.repo).state.signedIn, isTrue);
      expect(MemberSessionCubit(b.repo).state.signedIn, isFalse);
    });

    blocTest<MemberSessionCubit, MemberSessionState>(
      'boot confirms the session and loads the overview',
      build: () {
        final f = _fakes(hasSession: true);
        when(() => f.repo.me()).thenAnswer((_) async => _overview());
        return MemberSessionCubit(f.repo);
      },
      act: (c) => c.boot(),
      verify: (c) {
        expect(c.state.signedIn, isTrue);
        expect(c.state.overview!.name, 'Asha Rao');
      },
    );

    blocTest<MemberSessionCubit, MemberSessionState>(
      'a 403 (blocked, removed, feature off) signs the member out',
      build: () {
        final f = _fakes(hasSession: true);
        when(() => f.repo.me()).thenThrow(
          ApiException(status: 403, code: 'FORBIDDEN', message: 'no'),
        );
        return MemberSessionCubit(f.repo);
      },
      act: (c) => c.boot(),
      verify: (c) => expect(c.state.signedIn, isFalse),
    );

    blocTest<MemberSessionCubit, MemberSessionState>(
      'a network failure keeps the member signed in and shows the error',
      build: () {
        final f = _fakes(hasSession: true);
        when(() => f.repo.me()).thenThrow(ApiException.network());
        return MemberSessionCubit(f.repo);
      },
      act: (c) => c.boot(),
      verify: (c) {
        expect(c.state.signedIn, isTrue);
        expect(c.state.error, isNotNull);
      },
    );

    blocTest<MemberSessionCubit, MemberSessionState>(
      'sign-out ends the server session and returns to signed out',
      build: () {
        final f = _fakes(hasSession: true);
        when(() => f.repo.logout()).thenAnswer((_) async {});
        return MemberSessionCubit(f.repo);
      },
      act: (c) => c.signOut(),
      verify: (c) => expect(c.state.signedIn, isFalse),
    );
  });

  test('OtpChallenge from a member request has the usual shape', () {
    final c = OtpChallenge.fromJson({'requestId': 'r', 'expiresIn': 600, 'resendIn': 30, 'maskedTarget': '+91***'});
    expect(c.requestId, 'r');
    expect(c.devOtp, isNull);
  });
}
