// The single login: one phone form for owners, staff and members, an email way in for staff, and the "continue as"
// choice when a number has more than one account. The server decides who a number is; the app only follows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gym_book_app/app/session_cubit.dart';
import 'package:gym_book_app/core/config/app_config.dart';
import 'package:gym_book_app/data/models/user_gym.dart';
import 'package:gym_book_app/data/repositories/auth_repository.dart';
import 'package:gym_book_app/features/auth/login_screen.dart';
import 'package:gym_book_app/features/auth/signin_flow.dart';
import 'package:gym_book_app/features/member/member_repository.dart';
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/member_session_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _Auth extends Mock implements AuthRepository {}

class _Member extends Mock implements MemberRepository {}

class _Session extends Mock implements SessionCubit {}

class _MemberSession extends Mock implements MemberSessionCubit {}

class _Config extends Mock implements AppConfig {}

void main() {
  setUpAll(() => registerFallbackValue(AuthResult(user: AppUser.fromJson(const {'id': 'u'}), gyms: const [])));
  late _Auth auth;
  late _Member member;
  late _Session session;
  late _MemberSession memberSession;

  setUp(() async {
    auth = _Auth();
    member = _Member();
    session = _Session();
    memberSession = _MemberSession();
    final cfg = _Config();
    when(() => cfg.devToolsEnabled).thenReturn(false);
    when(() => cfg.isConfigured).thenReturn(true);
    when(() => cfg.baseUrl).thenReturn('http://x');
    final g = GetIt.instance;
    await g.reset();
    g
      ..registerSingleton<AuthRepository>(auth)
      ..registerSingleton<MemberRepository>(member)
      ..registerSingleton<SessionCubit>(session)
      ..registerSingleton<MemberSessionCubit>(memberSession)
      ..registerSingleton<AppConfig>(cfg);
  });
  tearDown(() async => GetIt.instance.reset());

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: LoginScreen()));
    await t.pump();
  }

  group('the login page', () {
    testWidgets('has one sign-in form: no separate member section', (t) async {
      await pump(t);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('FOR GYM MEMBERS'), findsNothing);
      expect(find.text('Send member OTP'), findsNothing);
      expect(find.text('Send OTP'), findsNothing);
    });

    testWidgets('says who it is for, and how a new gym owner or a member starts', (t) async {
      await pump(t);
      expect(find.textContaining('Gym owners, staff and members'), findsOneWidget);
      await t.scrollUntilVisible(find.text('I run a gym'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('I run a gym'), findsOneWidget);
      expect(find.text('I am a gym member'), findsOneWidget);
    });

    testWidgets('an empty or short number is stopped before any request', (t) async {
      await pump(t);
      await t.tap(find.text('Continue'));
      await t.pump();
      verifyNever(() => auth.requestSignin(phone: any(named: 'phone'), channel: any(named: 'channel')));
      verifyNever(() => auth.requestLoginOtp(phone: any(named: 'phone'), email: any(named: 'email'), channel: any(named: 'channel')));
    });

    testWidgets('email is a staff way in and has its own validation', (t) async {
      await pump(t);
      await t.tap(find.text('Owner or staff? Use email instead'));
      await t.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Send code by'), findsNothing, reason: 'email codes go by email only');
      await t.enterText(find.byType(TextFormField).first, 'nope');
      await t.tap(find.text('Continue'));
      await t.pump();
      verifyNever(() => auth.requestLoginOtp(phone: any(named: 'phone'), email: any(named: 'email'), channel: any(named: 'channel')));
      await t.tap(find.text('Use my phone number instead'));
      await t.pumpAndSettle();
      expect(find.text('Send code by'), findsOneWidget);
    });
  });

  group('after the code', () {
    testWidgets('one account: no question is asked, and a member session starts', (t) async {
      when(() => member.acceptBundle(any())).thenAnswer((_) async => const MemberAuthResult());
      when(() => memberSession.signedIn()).thenAnswer((_) async {});
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })));
      await finishSignin(ctx, {'status': 'signed_in', 'kind': 'member', 'accessToken': 'a', 'refreshToken': 'r'});
      verify(() => member.acceptBundle(any())).called(1);
      verify(() => memberSession.signedIn()).called(1);
      verifyNever(() => auth.acceptStaff(any()));
    });

    testWidgets('a staff result signs in the staff session and never touches the member one', (t) async {
      final r = AuthResult(user: AppUser.fromJson(const {'id': 'u'}), gyms: const []);
      when(() => auth.acceptStaff(any())).thenAnswer((_) async => r);
      when(() => session.signedIn(any())).thenAnswer((_) async {});
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) { ctx = c; return const SizedBox(); })));
      await finishSignin(ctx, {'status': 'signed_in', 'kind': 'staff', 'accessToken': 'a', 'refreshToken': 'r'});
      verify(() => session.signedIn(r)).called(1);
      verifyNever(() => member.acceptBundle(any()));
    });

    testWidgets('two accounts: the person chooses, and only the chosen one starts', (t) async {
      when(() => auth.chooseSignin('tok', 'member:g1')).thenAnswer((_) async => {'status': 'signed_in', 'kind': 'member', 'accessToken': 'a', 'refreshToken': 'r'});
      when(() => member.acceptBundle(any())).thenAnswer((_) async => const MemberAuthResult());
      when(() => memberSession.signedIn()).thenAnswer((_) async {});
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) { ctx = c; return const SizedBox(); }))));
      final done = finishSignin(ctx, {
        'status': 'choose', 'selectionToken': 'tok',
        'options': [
          {'id': 'staff', 'kind': 'staff', 'title': 'Manage a gym', 'subtitle': 'Owner or staff account'},
          {'id': 'member:g1', 'kind': 'member', 'title': 'Iron Temple', 'subtitle': 'Member · Bengaluru'},
        ],
      });
      await t.pumpAndSettle();
      expect(find.text('Continue as'), findsOneWidget);
      expect(find.text('Manage a gym'), findsOneWidget);
      expect(find.text('Iron Temple'), findsOneWidget);
      await t.tap(find.text('Iron Temple'));
      await t.pumpAndSettle();
      await done;
      verify(() => auth.chooseSignin('tok', 'member:g1')).called(1);
      verify(() => memberSession.signedIn()).called(1);
      verifyNever(() => auth.acceptStaff(any()));
    });

    testWidgets('dismissing the choice signs nobody in', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) { ctx = c; return const SizedBox(); }))));
      final done = finishSignin(ctx, {
        'status': 'choose', 'selectionToken': 'tok',
        'options': [{'id': 'staff', 'kind': 'staff', 'title': 'Manage a gym'}, {'id': 'member:g1', 'kind': 'member', 'title': 'Iron Temple'}],
      });
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      await done;
      verifyNever(() => auth.chooseSignin(any(), any()));
      verifyNever(() => auth.acceptStaff(any()));
      verifyNever(() => member.acceptBundle(any()));
    });
  });
}
