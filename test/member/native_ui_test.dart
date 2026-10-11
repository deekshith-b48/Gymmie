import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/data/models/user_gym.dart' show OtpChallenge;
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/gym_api.dart';
import 'package:gym_book_app/features/member/native/domain/rows.dart';
import 'package:gym_book_app/features/member/native/domain/session.dart';
import 'package:gym_book_app/features/member/native/log_store.dart';
import 'package:gym_book_app/features/member/native/ui/body_map.dart';
import 'package:gym_book_app/features/member/native/ui/focus_screen.dart';
import 'package:gym_book_app/features/member/native/ui/home_screen.dart';
import 'package:gym_book_app/features/member/native/ui/plan_view.dart';
import 'package:gym_book_app/features/member/native/ui/profile_screen.dart';
import 'package:gym_book_app/features/member/native/ui/stats_screen.dart';
import 'package:gym_book_app/features/member/native/ui/sync_banner.dart';
import 'package:gym_book_app/features/member/native/ui/library_screen.dart';
import 'package:gym_book_app/features/member/native/ui/native_app.dart';
import 'package:gym_book_app/features/member/native/ui/scope.dart';
import 'package:gym_book_app/features/member/native/ui/theme.dart';
import 'package:gym_book_app/features/member/native/ui/workout_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final overview = MemberOverview.fromJson({
  'member': {'id': 'm1', 'name': 'Asha Rao', 'admissionNo': 7},
  'gym': {'id': 'g1', 'code': '123456', 'name': 'Iron Temple', 'city': 'Bengaluru', 'currencySymbol': '₹'},
  'membership': {'planName': 'Gold Monthly', 'startDate': '2026-10-01', 'endDate': '2026-10-30', 'status': 'active', 'daysLeft': 20, 'balance': 300},
  'trainer': {'name': 'Tarun'}, 'visitsLast30': 9, 'qrPayload': 'dgymbook://member/123456/m1',
});

class FakeGymApi implements MemberGymApi {
  FakeGymApi({this.workout});
  final Json? workout;
  @override
  Future<MemberProfile> profile() async => MemberProfile.fromJson({
    'member': {'name': 'Asha Rao', 'phone': '+919900000101', 'bloodGroup': 'O+', 'admissionNo': 7, 'joinedAt': '2026-01-05', 'emergencyContact': {'name': 'Ravi', 'phone': '+919800000000'}},
    'gym': {'name': 'Iron Temple', 'code': '123456', 'address': '12 MG Road', 'city': 'Bengaluru', 'phone': '+918000000000', 'currencySymbol': '₹'},
    'trainer': {'name': 'Tarun'},
    'memberships': [
      {'planName': 'Gold Monthly', 'startDate': '2026-10-01', 'endDate': '2026-10-30', 'status': 'active', 'daysLeft': 20, 'total': 1500, 'amountReceived': 1200, 'balance': 300, 'invoiceNo': 'INV-00007', 'benefits': ['Free towel', 'Steam room']},
      {'planName': 'Silver Monthly', 'startDate': '2026-09-01', 'endDate': '2026-09-30', 'status': 'expired', 'total': 1000, 'amountReceived': 1000, 'balance': 0},
    ],
    'gymPlans': [{'name': 'Gold Monthly', 'price': 1500, 'durationDays': 30, 'description': 'All access', 'benefits': ['Free towel']}, {'name': 'Annual', 'price': 12000, 'durationDays': 365}],
  });
  @override
  Future<AttendanceSummary> attendance({int days = 90}) async => AttendanceSummary.fromJson({
    'visits': [{'date': '2026-10-09', 'checkIn': '2026-10-09T11:30:00Z', 'source': 'qr'}, {'date': '2026-10-08', 'checkIn': '2026-10-08T11:00:00Z', 'checkOut': '2026-10-08T12:10:00Z', 'source': 'manual'}],
    'total': 14, 'last30': 9, 'lastAttendedAt': '2026-10-09', 'streakDays': 2,
  });
  @override
  Future<AssignedPlans> plans() async => AssignedPlans.fromJson({'workout': workout, 'diet': null});
  bool offline = false;
  int writes = 0;
  MemberAccount acct = const MemberAccount(name: 'Asha Rao', phone: '+919900000101');
  PrivacySettings priv = const PrivacySettings();
  NotificationSettings notif = const NotificationSettings(mandatory: ['Receipts and payment confirmations']);
  List<DeviceSession> devices = const [
    DeviceSession(id: 'f1', device: 'Pixel 8', signedInAt: '2026-10-01T10:00:00Z', lastActiveAt: '2026-10-10T10:00:00Z', current: true),
    DeviceSession(id: 'f2', device: 'Old phone', signedInAt: '2026-09-01T10:00:00Z', lastActiveAt: '2026-09-02T10:00:00Z', current: false),
  ];
  final List<MembershipRequest> reqs = [];
  final List<String> calls = [];
  T _on<T>(T v) => offline ? throw ApiException.network() : v;
  bool online = false;
  final List<double?> links = [];
  @override
  Future<bool> paymentsOnline() async => online;
  @override
  Future<String> paymentLink({double? amount}) async { _on(0); links.add(amount); return 'https://rzp.io/i/abc'; }
  @override
  Future<MemberAccount> account() async => _on(acct);
  @override
  Future<MemberAccount> updateAccount(Map<String, dynamic> changes) async {
    _on(0); writes++; calls.add('update:${changes['name']}');
    return acct = MemberAccount(name: changes['name'] as String? ?? acct.name, phone: acct.phone, email: changes['email'] as String?, goal: (changes['fitness'] as Map?)?['goal'] as String?);
  }
  @override
  Future<Uint8List?> photo() async => null;
  @override
  Future<MemberAccount> setPhoto(Uint8List bytes, String contentType) async => acct;
  @override
  Future<MemberAccount> removePhoto() async => acct;
  @override
  Future<OtpChallenge> requestPhoneChange(String phone) async { _on(0); calls.add('phone:$phone'); return const OtpChallenge(requestId: 'r1', expiresIn: 600, resendIn: 30, maskedTarget: '+91•••••9999'); }
  @override
  Future<String> verifyPhoneChange(String requestId, String otp) async { _on(0); calls.add('verify:$otp'); return '+919999999999'; }
  @override
  Future<List<DeviceSession>> sessions() async => _on(devices);
  @override
  Future<void> endSession(String id) async { _on(0); calls.add('end:$id'); devices = [for (final d in devices) if (d.id != id) d]; }
  @override
  Future<void> endOtherSessions() async { _on(0); calls.add('others'); devices = [for (final d in devices) if (d.current) d]; }
  @override
  Future<OtpChallenge> requestDeleteCode() async { _on(0); return const OtpChallenge(requestId: 'd1', expiresIn: 600, resendIn: 30, maskedTarget: '+91•••••0101'); }
  @override
  Future<void> deleteAccount({required String requestId, required String otp}) async { _on(0); calls.add('delete:$otp'); }
  @override
  Future<List<MembershipRequest>> requests() async => _on(List.of(reqs));
  @override
  Future<MembershipRequest> createRequest({required String type, String? planId, String? note}) async {
    _on(0);
    calls.add('request:$type:$planId');
    final q = MembershipRequest(id: 'q${reqs.length}', type: type, status: 'pending', createdAt: '2026-10-10T10:00:00Z', note: note);
    reqs.add(q);
    return q;
  }
  @override
  Future<void> withdrawRequest(String id) async { _on(0); calls.add('withdraw:$id'); reqs.removeWhere((q) => q.id == id); }
  @override
  Future<PrivacySettings> privacy() async => _on(priv);
  @override
  Future<PrivacySettings> setPrivacy({Map<String, bool>? trainerCanSee, String? shareTraining}) async {
    _on(0); writes++;
    return priv = PrivacySettings(trainerCanSee: {...priv.trainerCanSee, ...?trainerCanSee}, shareTraining: shareTraining ?? priv.shareTraining);
  }
  @override
  Future<NotificationSettings> notifications() async => _on(notif);
  @override
  Future<NotificationSettings> setNotifications({bool? announcements, bool? expiryOn, int? expiryDaysBefore}) async {
    _on(0); writes++;
    return notif = NotificationSettings(announcements: announcements ?? notif.announcements, expiryOn: expiryOn ?? notif.expiryOn, expiryDaysBefore: expiryDaysBefore ?? notif.expiryDaysBefore, mandatory: notif.mandatory);
  }
}

late Catalogue cat;
late MemberLogStore store;
bool signedOut = false;

Widget app(Widget child) => NativeScope(
  store: store, catalogue: cat, memberName: 'Asha Rao', mediaBase: null,
  overview: overview, gymApi: FakeGymApi(), signOut: () async => signedOut = true, signOutEverywhere: () async => signedOut = true,
  child: MaterialApp(theme: ogTheme(), home: child),
);

Future<void> setSize(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cat = await Catalogue.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = MemberLogStore(key: 'test', prefs: await SharedPreferences.getInstance());
    await store.load();
    signedOut = false;
  });

  group('the real catalogue', () {
    test('has every exercise, muscle weights and a body-map shortcut for each muscle', () {
      expect(cat.exercises.length, 5632);
      expect(cat.muscles.length, greaterThanOrEqualTo(18));
      final chest = exercisesForFocus(cat.exercises, {'chest'});
      expect(chest.length, greaterThan(50));
      // primary hits come before helper-only ones
      final firstHelper = chest.indexWhere((e) => !e.primaryFor('chest'));
      expect(chest.take(firstHelper < 0 ? chest.length : firstHelper).every((e) => e.primaryFor('chest')), isTrue);
      expect(searchExercises(cat.exercises, 'bench press').isNotEmpty, isTrue);
    });
  });

  group('body map', () {
    test('every muscle can be hit at a point inside it', () async {
      final geo = BodyGeometry.parse(await rootBundleString());
      var found = 0;
      for (final m in cat.muscles) {
        if (m.id == 'cardiovascular system') continue;
        final p = geo.pointInside('front', m.id) ?? geo.pointInside('back', m.id);
        if (p != null) found++;
      }
      expect(found, greaterThanOrEqualTo(16));
    });
  });

  testWidgets('choose a focus: tap the chest on the body map, pick exercises, start', (t) async {
    await setSize(t);
    await t.runAsync(BodyGeometry.load);
    List<Exercise>? started;
    String? name;
    await t.pumpWidget(app(Builder(builder: (context) => FocusScreen(onStart: (p, n) { started = p; name = n; }))));
    await t.pumpAndSettle();
    expect(find.text('Choose a focus'), findsOneWidget);
    final cont = find.widgetWithText(FilledButton, 'Continue');
    expect(t.widget<FilledButton>(cont).onPressed, isNull, reason: 'nothing selected yet');

    final geo = await BodyGeometry.load();
    final p = geo.pointInside('front', 'chest')!;
    final box = geo.boxOf('front');
    final canvas = find.descendant(of: find.byType(BodyMap), matching: find.byType(CustomPaint)).first;
    final topLeft = t.getTopLeft(canvas);
    final scale = t.getSize(canvas).width / box.width;
    await t.tapAt(topLeft + Offset((p.dx - box.left) * scale, (p.dy - box.top) * scale));
    await t.pump();
    expect(find.widgetWithText(InputChip, 'Chest'), findsOneWidget);
    expect(t.widget<FilledButton>(cont).onPressed, isNotNull);

    await t.tap(cont);
    await t.pumpAndSettle();
    expect(find.text('STEP 2 OF 2'), findsOneWidget);
    expect(find.text('Pick an exercise'), findsOneWidget);
    await t.tap(find.byIcon(Icons.add_circle_outline).first);
    await t.pump();
    expect(find.text('Start · 1 exercise'), findsOneWidget);
    await t.tap(find.text('Start · 1 exercise'));
    await t.pump();
    expect(started, hasLength(1));
    expect(started!.first.trains('chest'), isTrue);
    expect(name, 'Chest');
  });

  testWidgets('a workout: tick a set, rest timer starts, finish saves it to history', (t) async {
    await setSize(t);
    final bench = cat.exercises.firstWhere((e) => e.name.toLowerCase().contains('bench press') && !e.cardio);
    store.updateLocalOnly((s) {
      final e = buildEntry(bench, s);
      (e['sets'] as List).cast<Json>().forEach((r) { r['w'] = 60; r['r'] = 5; });
      s['active'] = newSession(id: 'w1', day: '2026-10-10', now: DateTime.now().millisecondsSinceEpoch - 600000, name: 'Freestyle', entries: [e]);
    });
    await t.pumpWidget(app(const WorkoutScreen()));
    await t.pump();
    expect(find.text('Freestyle'), findsOneWidget);
    expect(find.textContaining('0/3 sets'), findsOneWidget);

    await t.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await t.pump();
    expect(find.textContaining('1/3 sets'), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget, reason: 'the rest bar appears after a set');
    expect(store.active!['entries'][0]['sets'][0]['done'], isTrue);

    await t.tap(find.text('Add set'));
    await t.pump();
    expect(find.textContaining('/4 sets'), findsOneWidget);

    await t.tap(find.text('Finish'));
    await t.pumpAndSettle();
    expect(find.text('Finish early?'), findsOneWidget);
    await t.tap(find.text('Finish and save'));
    await t.pumpAndSettle();
    expect(find.text('Workout saved'), findsOneWidget);
    expect(find.textContaining('Volume  300'), findsOneWidget);
    expect(find.text('New records'), findsOneWidget);
    expect(store.active, isNull);
    expect((store.state['workouts'] as List).length, 1);
    expect(store.dirty, isTrue, reason: 'finished workouts are queued to sync');
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
  });

  testWidgets('discarding a workout saves nothing', (t) async {
    await setSize(t);
    final ex = cat.exercises.firstWhere((e) => !e.cardio);
    store.updateLocalOnly((s) => s['active'] = newSession(id: 'w2', day: '2026-10-10', now: 1, name: 'Freestyle', entries: [buildEntry(ex, s)]));
    await t.pumpWidget(app(Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => const WorkoutScreen())), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Finish'));
    await t.pumpAndSettle();
    await t.tap(find.text('Discard workout'));
    await t.pumpAndSettle();
    await t.tap(find.text('Discard'));
    await t.pumpAndSettle();
    expect(store.active, isNull);
    expect(store.state['workouts'], isEmpty);
  });

  testWidgets('home: greets the member, shows the week, today\'s routine and the check-in card', (t) async {
    await setSize(t);
    final bench = cat.exercises.firstWhere((e) => e.name.toLowerCase().contains('bench press') && !e.cardio);
    store.updateLocalOnly((s) {
      s['routines'] = [{'id': 'r1', 'name': 'Push day', 'ex': [{'id': bench.id, 'sets': 3, 'reps': 8, 'weight': 40}]}];
      s['week'] = {'${DateTime.now().weekday % 7}': ['r1']};
    });
    await t.pumpWidget(app(HomeScreen(onTab: (_) {})));
    await t.pump();
    expect(find.text('Hi Asha'), findsOneWidget);
    expect(find.text('Push day'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Choose a focus'), findsOneWidget);
    // the gym section lives on Home itself
    expect(find.text('MY GYM'), findsOneWidget);
    expect(find.text('Iron Temple'), findsOneWidget);
    // the membership card below it carries the plan, dates and payment (loaded from the gym's records)
    await t.pumpAndSettle();
    expect(find.text('Gold Monthly'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('2026-10-30'), findsOneWidget);
    expect(find.text('₹300'), findsOneWidget);
    expect(find.text('Trainer: Tarun'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('My profile'), findsOneWidget);
    await t.scrollUntilVisible(find.text('0 week streak'), 300);
    expect(find.text('0 week streak'), findsOneWidget);
  });

  testWidgets('library: search narrows the list and picking returns the exercise', (t) async {
    await setSize(t);
    Exercise? picked;
    await t.pumpWidget(app(Builder(builder: (c) => Scaffold(body: TextButton(
      onPressed: () async => picked = await Navigator.push<Exercise>(c, MaterialPageRoute(builder: (_) => const LibraryScreen(picking: true))),
      child: const Text('open'),
    )))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.textContaining('5632 exercises'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'bench press');
    await t.pumpAndSettle();
    expect(find.textContaining('5632 exercises'), findsNothing);
    await t.tap(find.byIcon(Icons.add_circle_outline).first);
    await t.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name.toLowerCase(), contains('bench press'));
  });

  testWidgets('shell: five tabs fit a small phone with no overflow, and switch screens', (t) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(const NativeShell()));
    await t.pump();
    expect(tester(t), isNull);
    for (final label in ['Plan', 'Stats', 'Exercises', 'Home']) {
      await t.tap(find.text(label).last);
      await t.pump();
      expect(tester(t), isNull, reason: 'after opening $label');
    }
    expect(find.text('Start'), findsWidgets);
  });

  testWidgets('home: Check in opens the QR for the front desk', (t) async {
    await setSize(t);
    await t.pumpWidget(app(HomeScreen(onTab: (_) {})));
    await t.pump();
    await t.ensureVisible(find.text('Check in'));
    await t.tap(find.text('Check in'));
    await t.pumpAndSettle();
    expect(find.text('Check-in code'), findsOneWidget);
    expect(find.textContaining('Iron Temple'), findsWidgets);
    expect(find.text('Asha Rao · #7'), findsOneWidget);
  });

  testWidgets('profile: membership, history, the gym\'s plans, gym and personal details', (t) async {
    await setSize(t);
    await t.pumpWidget(app(const ProfileScreen()));
    await t.pumpAndSettle();
    expect(find.text('Asha Rao'), findsWidgets);
    expect(find.text('Member #7 · since 2026-01-05'), findsOneWidget);
    expect(find.text('Gold Monthly'), findsWidgets);
    expect(find.text('Silver Monthly'), findsOneWidget, reason: 'past memberships are listed');
    expect(find.textContaining('₹300 due'), findsOneWidget);
    expect(find.text('INCLUDED'), findsOneWidget, reason: 'the current plan\'s benefits');
    expect(find.text('Free towel'), findsOneWidget);
    expect(find.text('Steam room'), findsOneWidget);
    await t.scrollUntilVisible(find.text('PLANS AT YOUR GYM'), 300);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('₹12000'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Blood group'), 300);
    expect(find.text('O+'), findsOneWidget);
    expect(find.text('12 MG Road, Bengaluru'), findsOneWidget);
  });

  testWidgets('stats: the gym membership and visits come first, training below', (t) async {
    await setSize(t);
    await t.pumpWidget(app(const StatsScreen()));
    await t.pumpAndSettle();
    expect(find.text('YOUR GYM'), findsOneWidget);
    expect(find.text('Gold Monthly'), findsOneWidget);
    expect(find.text('Visits (30 days)'), findsOneWidget);
    expect(find.text('9'), findsWidgets);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.text('Gym visits per week'), findsOneWidget);
    expect(find.text('Last visit 2026-10-09'), findsOneWidget);
    final page = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.text('TRAINING'), 300, scrollable: page);
    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Week streak'), findsOneWidget);
    expect(find.text('Weight 30d'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Activity (last 12 months)'), 300, scrollable: page);
    await t.scrollUntilVisible(find.text('Weekly volume'), 300, scrollable: page);
    expect(find.text('Weekly volume'), findsOneWidget);
  });

  testWidgets('the trainer\'s workout plan can be read and a day started as a session', (t) async {
    await setSize(t);
    final plans = AssignedPlans.fromJson({'workout': {'name': 'Push/Pull', 'goal': 'Build Muscle', 'days': [
      {'name': 'Day 1', 'exercises': [{'name': 'Barbell Bench Press', 'sets': 4, 'reps': '8-10'}, {'name': 'Zzzz Unknown', 'sets': 3, 'reps': '10'}]},
    ]}});
    await t.pumpWidget(app(AssignedPlanScreen(plans: plans)));
    await t.pumpAndSettle();
    expect(find.text('Push/Pull'), findsOneWidget);
    expect(find.text('4 × 8-10'), findsOneWidget);
    await t.tap(find.text('Start this day'));
    await t.pumpAndSettle();
    expect(find.text('Weigh in'), findsOneWidget, reason: 'Start asks for the body weight first (Settings → Weigh in before workouts)');
    await t.tap(find.text('Start without weighing in'));
    await t.pumpAndSettle();
    expect(store.active, isNotNull);
    expect(store.active!['bw'], isNull);
    expect(store.active!['name'], 'Push/Pull · Day 1');
    expect((store.active!['entries'] as List), hasLength(1), reason: 'the unknown exercise is left out, not guessed');
    expect(store.active!['entries'][0]['sets'][0]['r'], 8);
  });

  testWidgets('the sync banner says what happened in plain words and offers Try again', (t) async {
    await setSize(t);
    final bad = MemberLogStore(key: 'b', prefs: await SharedPreferences.getInstance(), api: _Refuse(), syncDelay: const Duration(days: 1));
    await bad.load();
    bad.update((s) => s['unit'] = 'lb');
    await t.runAsync(bad.sync);
    store = bad;
    await t.pumpWidget(app(const Scaffold(body: SyncBanner())));
    await t.pump();
    expect(find.textContaining('HTTP 403'), findsOneWidget);
    expect(find.textContaining('changes are kept here'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

}

class _Refuse implements LogApi {
  @override
  Future<LogDoc> fetchLog() async => throw ApiException(status: 403, code: 'FORBIDDEN', message: 'no');
  @override
  Future<LogDoc> pushLog(Json state, int baseRev) async => throw ApiException(status: 403, code: 'FORBIDDEN', message: 'no');
  @override
  Future<void> eraseLog() async {}
}

Object? tester(WidgetTester t) => t.takeException();

Future<String> rootBundleString() => rootBundle.loadString('assets/member/body.json');
