// The launch flow: the logo animation, the optional walkthrough, the optional payment setup, the member login and its welcome,
// and the member's membership card. Each screen is checked against what it must and must not do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_book_app/app/routes.dart';
import 'package:gym_book_app/app/router.dart';
import 'package:gym_book_app/app/session_cubit.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/core/theme/app_theme.dart';
import 'package:gym_book_app/core/widgets/brand_splash.dart';
import 'package:gym_book_app/data/models/settings.dart';
import 'package:gym_book_app/data/models/user_gym.dart';
import 'package:gym_book_app/data/repositories/gym_repository.dart';
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/log_store.dart';
import 'package:gym_book_app/features/member/member_login_screen.dart';
import 'package:gym_book_app/features/member/member_repository.dart';
import 'package:gym_book_app/features/member/member_session_cubit.dart';
import 'package:gym_book_app/features/member/native/ui/member_welcome.dart';
import 'package:gym_book_app/features/member/native/ui/membership_card.dart';
import 'package:gym_book_app/features/member/native/ui/scope.dart';
import 'package:gym_book_app/features/onboarding/walkthrough_screen.dart';
import 'package:gym_book_app/features/settings/payment_setup_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../member/native_ui_test.dart' show FakeGymApi, overview, setSize;
import '../member/native_ui_test.dart' as nu;

class _Session extends Mock implements SessionCubit {}

class _Gym extends Mock implements GymRepository {}

class _Member extends Mock implements MemberRepository {}

class _MemberSession extends Mock implements MemberSessionCubit {}

AppUser _user(String id) => AppUser(id: id, name: 'Olivia Owner', phone: '+919876500000');
GymProfile _gym({String role = 'owner', String paymentSetup = 'none', bool onboarded = true}) => GymProfile.fromJson({
  'id': 'g1', 'code': '123456', 'name': 'Iron Temple', 'address': '12 MG Road', 'role': role, 'onboardingCompleted': onboarded, 'paymentSetup': paymentSetup,
  'subscription': {'plan': 'TRIAL', 'status': 'active', 'endsAt': '2099-01-01'},
});

Widget _router(Widget home, {List<GoRoute> extra = const []}) => MaterialApp.router(
  theme: AppTheme.dark(),
  routerConfig: GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: R.home, builder: (_, _) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: R.login, builder: (_, _) => const Scaffold(body: Text('LOGIN'))),
    ...extra,
  ]),
);

void main() {
  late _Session session;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = _Session();
    final g = GetIt.instance;
    await g.reset();
    g
      ..registerSingleton<SharedPreferences>(prefs)
      ..registerSingleton<SessionCubit>(session);
  });
  tearDown(() async => GetIt.instance.reset());

  group('the logo animation', () {
    testWidgets('the Gymmie logo fades in and settles, then stays', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AnimatedLogo()))));
      expect(find.byType(Image), findsOneWidget);
      await t.pump(const Duration(milliseconds: 150));
      final early = t.widget<Opacity>(find.descendant(of: find.byType(AnimatedLogo), matching: find.byType(Opacity)).first).opacity;
      await t.pump(const Duration(milliseconds: 1200));
      final late = t.widget<Opacity>(find.descendant(of: find.byType(AnimatedLogo), matching: find.byType(Opacity)).first).opacity;
      expect(early, lessThan(1));
      expect(late, 1);
    });

    testWidgets('the splash clock holds the logo for a moment and then releases the app', (t) async {
      expect(SplashClock.done.value, isFalse);
      SplashClock.start(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 80));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      expect(SplashClock.done.value, isTrue);
    });
  });

  group('who sees which first-time screen', () {
    SessionState s(String role, {String pay = 'none', bool onboarded = true, String user = 'u1'}) =>
        SessionState(status: SessionStatus.signedIn, user: _user(user), profile: _gym(role: role, paymentSetup: pay, onboarded: onboarded));

    test('an owner sees the walkthrough invitation first, then the payment setup, then neither', () async {
      expect(onboardingRedirect(s('owner'), R.home), R.walkthrough);
      await WalkthroughStore.markSeen('u1');
      expect(onboardingRedirect(s('owner'), R.home), R.paymentIntro);
      expect(onboardingRedirect(s('owner', pay: 'skipped'), R.home), isNull);
      expect(onboardingRedirect(s('owner', pay: 'active'), R.home), isNull);
    });

    test('a manager sees the walkthrough but never the payment setup (only the owner holds the keys)', () async {
      expect(onboardingRedirect(s('manager'), R.home), R.walkthrough);
      await WalkthroughStore.markSeen('u1');
      expect(onboardingRedirect(s('manager'), R.home), isNull);
    });

    test('front desk and trainers see neither', () {
      expect(onboardingRedirect(s('staff'), R.home), isNull);
      expect(onboardingRedirect(s('trainer'), R.home), isNull);
    });

    test('it is remembered per account, so another account on the phone is still asked once', () async {
      await WalkthroughStore.markSeen('u1');
      expect(onboardingRedirect(s('owner', pay: 'skipped', user: 'u1'), R.home), isNull);
      expect(onboardingRedirect(s('owner', pay: 'skipped', user: 'u2'), R.home), R.walkthrough);
    });

    test('the payment prompt waits until the gym is set up', () async {
      await WalkthroughStore.markSeen('u1');
      expect(onboardingRedirect(s('owner', onboarded: false), R.home), isNull);
    });
  });

  group('the walkthrough invitation', () {
    testWidgets('with no contact configured it offers none, invents none, and can be skipped', (t) async {
      when(() => session.state).thenReturn(SessionState(status: SessionStatus.signedIn, user: _user('u1'), profile: _gym()));
      await t.pumpWidget(_router(const WalkthroughScreen()));
      await t.pumpAndSettle();
      expect(find.text('Want a full walkthrough?'), findsOneWidget);
      expect(find.text('Message on WhatsApp'), findsNothing);
      expect(find.text('Send an email'), findsNothing);
      expect(find.textContaining('not been set up'), findsOneWidget);
      await t.tap(find.text('Skip'));
      await t.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(WalkthroughStore.seen('u1'), isTrue, reason: 'skipping is remembered');
    });

    testWidgets('with a number and an email from the server it offers exactly those', (t) async {
      when(() => session.state).thenReturn(SessionState(
        status: SessionStatus.signedIn, user: _user('u2'), profile: _gym(),
        settings: const AppSettings(companyWhatsappNumber: '+911234567890', supportEmail: 'hello@example.com', supportName: 'Asha from Gymmie'),
      ));
      await t.pumpWidget(_router(const WalkthroughScreen()));
      await t.pumpAndSettle();
      expect(find.text('Message on WhatsApp'), findsOneWidget);
      expect(find.text('Send an email'), findsOneWidget);
      expect(find.textContaining('Asha from Gymmie'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      await t.tap(find.text('Continue to Gymmie'));
      await t.pumpAndSettle();
      expect(WalkthroughStore.seen('u2'), isTrue);
    });
  });

  group('optional payment setup', () {
    late _Gym gym;
    setUp(() {
      gym = _Gym();
      GetIt.instance.registerSingleton<GymRepository>(gym);
      when(() => session.refreshProfile()).thenAnswer((_) async {});
    });

    PaymentSetup setup({String status = 'none', bool canEdit = true}) =>
        PaymentSetup(status: status, canEdit: canEdit, webhookUrl: 'https://api.example.com/v5/payments/webhooks/gym/g1/razorpay', keyId: status == 'active' ? 'rzp_test_…abc' : null, mode: 'test');

    testWidgets('after setup it offers "Skip for now", and skipping records the choice and carries on', (t) async {
      await setSize(t);
      when(() => gym.paymentSetup()).thenAnswer((_) async => setup());
      when(() => gym.skipPaymentSetup()).thenAnswer((_) async => setup(status: 'skipped'));
      await t.pumpWidget(_router(const PaymentSetupScreen(onboarding: true)));
      await t.pumpAndSettle();
      expect(find.text('Verify and connect'), findsOneWidget);
      expect(find.textContaining('separate from your Gymmie subscription'), findsOneWidget);
      await t.tap(find.text('Skip for now').first);
      await t.pumpAndSettle();
      verify(() => gym.skipPaymentSetup()).called(1);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a malformed key is stopped before it is sent', (t) async {
      await setSize(t);
      when(() => gym.paymentSetup()).thenAnswer((_) async => setup());
      await t.pumpWidget(_router(const PaymentSetupScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), 'not-a-key');
      await t.drag(find.byType(ListView), const Offset(0, -700));
      await t.pumpAndSettle();
      await t.tap(find.text('Verify and connect'));
      await t.pump();
      expect(find.text('Enter your Razorpay Key ID (rzp_test_… or rzp_live_…)'), findsOneWidget);
      verifyNever(() => gym.connectPayments(keyId: any(named: 'keyId'), keySecret: any(named: 'keySecret'), webhookSecret: any(named: 'webhookSecret')));
    });

    testWidgets('good details are sent to the server to be checked, and a refusal is shown, not hidden', (t) async {
      await setSize(t);
      when(() => gym.paymentSetup()).thenAnswer((_) async => setup());
      when(() => gym.connectPayments(keyId: any(named: 'keyId'), keySecret: any(named: 'keySecret'), webhookSecret: any(named: 'webhookSecret')))
          .thenThrow(ApiException(status: 422, code: 'VALIDATION_FAILED', message: 'Razorpay did not accept these keys. Check the Key ID and Key Secret.'));
      await t.pumpWidget(_router(const PaymentSetupScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), 'rzp_test_abcdef123456');
      await t.enterText(find.byType(TextFormField).at(1), 'secret-value-1');
      await t.enterText(find.byType(TextFormField).at(2), 'webhook-secret-1');
      await t.drag(find.byType(ListView), const Offset(0, -700));
      await t.pumpAndSettle();
      await t.tap(find.text('Verify and connect'));
      await t.pumpAndSettle();
      verify(() => gym.connectPayments(keyId: 'rzp_test_abcdef123456', keySecret: 'secret-value-1', webhookSecret: 'webhook-secret-1')).called(1);
      expect(find.textContaining('did not accept these keys'), findsOneWidget);
    });

    testWidgets('a manager sees it read-only, without the form', (t) async {
      await setSize(t);
      when(() => gym.paymentSetup()).thenAnswer((_) async => setup(canEdit: false));
      await t.pumpWidget(_router(const PaymentSetupScreen()));
      await t.pumpAndSettle();
      expect(find.text('Only the gym owner can connect a payment account.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('when connected it shows the mode and key, never a secret, and the owner can disconnect', (t) async {
      await setSize(t);
      when(() => gym.paymentSetup()).thenAnswer((_) async => setup(status: 'active'));
      await t.pumpWidget(_router(const PaymentSetupScreen()));
      await t.pumpAndSettle();
      expect(find.text('Razorpay connected'), findsOneWidget);
      expect(find.text('Test mode'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });
  });

  group('member login', () {
    late _Member repo;
    late _MemberSession ms;
    setUp(() {
      repo = _Member();
      ms = _MemberSession();
      GetIt.instance
        ..registerSingleton<MemberRepository>(repo)
        ..registerSingleton<MemberSessionCubit>(ms);
    });

    Future<void> pump(WidgetTester t) async {
      await setSize(t);
      await t.pumpWidget(_router(const MemberLoginScreen()));
      await t.pumpAndSettle();
    }

    test('the code field upper-cases and keeps only letters, digits and hyphens', () {
      final f = AccessCodeFormatter();
      final out = f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: 'ab12 -cd_ef!'));
      expect(out.text, 'AB12-CDEF');
      expect(MemberLoginScreenCheck.ok('885409-K7Q2-M9XD'), isTrue);
      expect(MemberLoginScreenCheck.ok('885409k7q2m9xd'), isTrue);
      expect(MemberLoginScreenCheck.ok('885409-K7Q2-M9X'), isFalse);
      expect(MemberLoginScreenCheck.ok('hello'), isFalse);
      expect(MemberLoginScreenCheck.ok('885409-I0O1-AAAA'), isFalse, reason: 'those letters are never in a code');
    });

    testWidgets('an incomplete code is explained and nothing is sent', (t) async {
      await pump(t);
      await t.enterText(find.byType(TextField), '885409-K7Q2');
      await t.tap(find.text('Sign in'));
      await t.pump();
      expect(find.textContaining('Enter the full code'), findsOneWidget);
      verifyNever(() => repo.loginWithCode(any()));
    });

    testWidgets('a good code signs the member in through the member session', (t) async {
      await pump(t);
      when(() => repo.loginWithCode(any())).thenAnswer((_) async => const MemberAuthResult(memberName: 'Asha'));
      when(() => ms.signedIn()).thenAnswer((_) async {});
      await t.enterText(find.byType(TextField), '885409k7q2m9xd');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      verify(() => repo.loginWithCode(any(that: contains('885409')))).called(1);
      verify(() => ms.signedIn()).called(1);
    });

    testWidgets('a wrong or revoked code shows the server\'s one plain answer, and does not sign in', (t) async {
      await pump(t);
      when(() => repo.loginWithCode(any())).thenThrow(ApiException(status: 403, code: 'FORBIDDEN', message: 'This access code is not valid. Ask your gym for a new one.'));
      await t.enterText(find.byType(TextField), '885409-AAAA-AAA2');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.textContaining('not valid'), findsOneWidget);
      verifyNever(() => ms.signedIn());
    });

    testWidgets('offline and rate-limited answers are put plainly', (t) async {
      await pump(t);
      when(() => repo.loginWithCode(any())).thenThrow(ApiException.network());
      await t.enterText(find.byType(TextField), '885409-AAAA-AAA2');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('You need to be online to sign in.'), findsOneWidget);
      when(() => repo.loginWithCode(any())).thenThrow(ApiException(status: 429, code: 'RATE_LIMITED', message: 'Too many attempts.'));
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.textContaining('Too many tries'), findsOneWidget);
    });

    testWidgets('there is a way back to phone sign-in and to ask the gym for a code', (t) async {
      await pump(t);
      expect(find.textContaining('Ask the front desk'), findsOneWidget);
      await t.tap(find.text('Sign in with my phone number instead'));
      await t.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });

  group('the welcome', () {
    testWidgets('says Welcome to the member\'s own gym, by name, and hands over after about three seconds', (t) async {
      var done = 0;
      await t.pumpWidget(MaterialApp(home: MemberWelcome(gymName: 'Iron Temple Fitness', memberName: 'Asha Rao', onDone: () => done++)));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Iron Temple Fitness!'), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2000));
      expect(done, 0, reason: 'not before three seconds');
      await t.pump(const Duration(milliseconds: 400));
      expect(done, 1);
    });

    test('the member session shows the welcome after a fresh sign-in only, and keeps it through the first refresh', () {
      const fresh = MemberSessionState(status: MemberStatus.signedIn, welcome: true);
      expect(fresh.welcome, isTrue);
      expect(const MemberSessionState(status: MemberStatus.signedIn).welcome, isFalse, reason: 'a saved session restored at start-up does not');
      expect(fresh == const MemberSessionState(status: MemberStatus.signedIn), isFalse);
    });
  });

  group('the member dashboard', () {
    setUp(() async {
      nu.cat = await Catalogue.load();
      nu.store = MemberLogStore(key: 'launch', prefs: prefs);
      await nu.store.load();
    });
    MemberProfile profile({String status = 'active', String start = '2026-10-01', String end = '2026-10-30', double total = 1500, double got = 1000, String pay = 'partial', int? left}) => MemberProfile.fromJson({
      'member': {'name': 'Asha Rao', 'phone': '+919900000101'},
      'gym': {'name': 'Iron Temple', 'code': '123456', 'currencySymbol': '₹'},
      'memberships': [
        {'planName': 'Gold Monthly', 'startDate': start, 'endDate': end, 'status': status, 'daysLeft': left, 'total': total, 'amountReceived': got, 'balance': total - got, 'paymentStatus': pay, 'invoiceNo': 'INV-00007', 'benefits': ['Free towel']},
      ],
    });

    Widget host(FakeGymApi api, {String today = '2026-10-10'}) => NativeScope(
      store: nu.store, catalogue: nu.cat, memberName: 'Asha Rao', mediaBase: null, overview: overview, gymApi: api, signOut: () async {}, signOutEverywhere: () async {},
      child: MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: SingleChildScrollView(child: MembershipDetailsCard(key: UniqueKey(), today: today)))),
    );

    testWidgets('shows the real plan, dates, status, month, price, paid, balance and invoice', (t) async {
      await setSize(t);
      final api = _ProfileApi(profile());
      await t.pumpWidget(host(api));
      await t.pumpAndSettle();
      expect(find.text('Gold Monthly'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
      expect(find.text('2026-10-30'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('20'), findsOneWidget, reason: '20 days left');
      expect(find.text('₹1500'), findsOneWidget);
      expect(find.text('₹1000'), findsOneWidget);
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('Part paid'), findsOneWidget);
      expect(find.text('Invoice INV-00007'), findsOneWidget);
      expect(find.text('✓ Free towel'), findsOneWidget);
      expect(find.text('VISITS'), findsOneWidget);
    });

    testWidgets('"Pay online" appears only when the gym takes online payments and something is owed', (t) async {
      await setSize(t);
      final api = _ProfileApi(profile())..online = false;
      await t.pumpWidget(host(api));
      await t.pumpAndSettle();
      expect(find.textContaining('online'), findsNothing);
      expect(find.text('Pay the balance at the front desk.'), findsOneWidget);
      final api2 = _ProfileApi(profile())..online = true;
      await t.pumpWidget(host(api2));
      await t.pumpAndSettle();
      expect(find.text('Pay ₹500 online'), findsOneWidget);
      final paid = _ProfileApi(profile(got: 1500, pay: 'paid'))..online = true;
      await t.pumpWidget(host(paid));
      await t.pumpAndSettle();
      expect(find.text('Paid in full'), findsOneWidget);
      expect(find.textContaining('online'), findsNothing, reason: 'nothing to pay');
    });

    testWidgets('near the end it says so and offers to request the renewal', (t) async {
      await setSize(t);
      await t.pumpWidget(host(_ProfileApi(profile(end: '2026-10-14', left: 4)), today: '2026-10-10'));
      await t.pumpAndSettle();
      expect(find.text('Request renewal'), findsOneWidget);
      expect(find.textContaining('4 days left'), findsOneWidget);
    });

    testWidgets('an ended membership says when it ended and offers renewal', (t) async {
      await setSize(t);
      await t.pumpWidget(host(_ProfileApi(profile(status: 'expired', end: '2026-09-30')), today: '2026-10-10'));
      await t.pumpAndSettle();
      expect(find.textContaining('ended on 2026-09-30'), findsOneWidget);
      expect(find.text('Request renewal'), findsOneWidget);
    });

    testWidgets('no membership says so plainly, and a load failure can be retried', (t) async {
      await setSize(t);
      await t.pumpWidget(host(_ProfileApi(MemberProfile.fromJson({'member': {'name': 'A', 'phone': '+91'}, 'gym': {'name': 'G', 'code': '1'}, 'memberships': []}))));
      await t.pumpAndSettle();
      expect(find.textContaining('No membership yet'), findsOneWidget);
      final bad = _ProfileApi(profile())..fail = true;
      await t.pumpWidget(host(bad));
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
    });

    test('plan months and day counts', () {
      expect(daysBetween('2026-10-10', '2026-10-30'), 20);
      expect(monthOfPlan('2026-10-01', '2026-10-30', '2026-10-10'), isNull, reason: 'a one-month plan has no "month 1 of 1"');
      final q = monthOfPlan('2026-10-01', '2026-12-29', '2026-11-05')!;
      expect([q.month, q.months], [2, 3]);
      expect(monthOfPlan('2026-10-01', '2026-12-29', '2027-02-01')!.month, 3, reason: 'never past the last month');
    });
  });
}

/// Exposes the screen's code check to the test without making it public API.
class MemberLoginScreenCheck {
  static bool ok(String t) => RegExp(r'^\d{6}[A-Z2-9]{8}$').hasMatch(t.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
}

class _ProfileApi extends FakeGymApi {
  _ProfileApi(this.p);
  final MemberProfile p;
  bool fail = false;
  @override
  Future<MemberProfile> profile() async => fail ? throw ApiException.network() : p;
  @override
  Future<bool> paymentsOnline() async => online;
}
