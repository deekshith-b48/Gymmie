// The member's own account screens: every call goes through the gym API (a fake here), and each screen must show
// loading, the saved result, validation, and an honest message when the network or the server says no.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/log_store.dart';
import 'package:gym_book_app/features/member/native/ui/account_pages.dart';
import 'package:gym_book_app/features/member/native/ui/native_app.dart';
import 'package:gym_book_app/features/member/native/ui/reminders.dart';
import 'package:gym_book_app/features/member/native/ui/scope.dart';
import 'package:gym_book_app/features/member/native/ui/settings_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_ui_test.dart' show FakeGymApi, overview, setSize;

late Catalogue cat;
late MemberLogStore store;
late FakeGymApi api;
int signOuts = 0;

Widget host(Widget home) => NativeScope(
  store: store, catalogue: cat, memberName: 'Asha Rao', mediaBase: null, overview: overview, gymApi: api,
  signOut: () async => signOuts++, signOutEverywhere: () async {},
  child: ThemedMemberApp(store: store, home: home),
);

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).first;
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  final scroll = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical);
  for (var i = 0; i < 12 && scroll.evaluate().isNotEmpty; i++) {
    final c = f.evaluate().isEmpty ? null : t.getCenter(f);
    if (c != null && c.dy > 0 && c.dy < size.height - 60) break;
    await t.drag(scroll.first, const Offset(0, -300));
    await t.pumpAndSettle();
  }
  await t.tap(f);
  await t.pumpAndSettle();
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
    api = FakeGymApi();
    signOuts = 0;
  });

  testWidgets('the account page lists every account area', (t) async {
    await setSize(t);
    await t.pumpWidget(host(const SettingsPage('account')));
    await t.pumpAndSettle();
    for (final s in ['My profile', 'Membership requests', 'Edit profile', 'Notifications', 'Privacy', 'Devices & security', 'Delete my account']) {
      expect(find.text(s, skipOffstage: false), findsOneWidget, reason: s);
    }
  });

  group('edit profile', () {
    testWidgets('saves only what the member typed and says so', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const EditProfileScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), 'Asha R');
      await t.enterText(find.byType(TextFormField).at(1), 'asha@example.com');
      await tapText(t, 'Save');
      expect(api.calls, contains('update:Asha R'));
      expect(api.acct.email, 'asha@example.com');
    });

    testWidgets('a bad email or a name that is too short is stopped before the server', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const EditProfileScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(1), 'nope');
      await tapText(t, 'Save');
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(api.writes, 0);
    });

    testWidgets('offline, the error is shown and the form stays', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const EditProfileScreen()));
      await t.pumpAndSettle();
      api.offline = true;
      await tapText(t, 'Save');
      expect(find.text('You need to be online to do this.'), findsOneWidget);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('the plan, dates and payments are not editable here', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const EditProfileScreen()));
      await t.pumpAndSettle();
      expect(find.textContaining('cannot be changed here'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Plan'), findsNothing);
    });
  });

  group('change phone number', () {
    testWidgets('a code goes to the new number, then the number changes', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const ChangePhoneScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '9999999999');
      await tapText(t, 'Send code');
      expect(api.calls, contains('phone:+919999999999'));
      await t.enterText(find.byType(TextField).first, '123456');
      await tapText(t, 'Change number');
      expect(api.calls, contains('verify:123456'));
    });

    testWidgets('a number that is too short never reaches the server', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const ChangePhoneScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '123');
      await tapText(t, 'Send code');
      expect(api.calls.where((c) => c.startsWith('phone:')), isEmpty);
    });
  });

  group('devices & security', () {
    testWidgets('lists the phones, marks this one, and signs another out', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const DevicesScreen()));
      await t.pumpAndSettle();
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.textContaining('This phone'), findsOneWidget);
      await t.tap(find.byTooltip('Sign out this phone'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sign out').last);
      await t.pumpAndSettle();
      expect(api.calls, contains('end:f2'));
      expect(find.text('Old phone'), findsNothing);
    });

    testWidgets('this phone has no sign-out button of its own in the list', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const DevicesScreen()));
      await t.pumpAndSettle();
      expect(find.byTooltip('Sign out this phone'), findsOneWidget, reason: 'only the other phone');
    });

    testWidgets('offline, the list says so and can retry', (t) async {
      await setSize(t);
      api.offline = true;
      await t.pumpWidget(host(const DevicesScreen()));
      await t.pumpAndSettle();
      expect(find.text('You need to be online to do this.'), findsOneWidget);
      api.offline = false;
      await tapText(t, 'Retry');
      expect(find.text('Pixel 8'), findsOneWidget);
    });
  });

  group('privacy', () {
    testWidgets('each switch is saved on the server, and put back when it fails', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const PrivacyScreen()));
      await t.pumpAndSettle();
      await tapText(t, 'Email');
      expect(api.priv.trainerCanSee['email'], isFalse);
      api.offline = true;
      await tapText(t, 'Address');
      expect(api.priv.trainerCanSee['address'], isTrue, reason: 'unchanged');
      expect(find.text('You need to be online to do this.'), findsOneWidget);
    });

    testWidgets('training is shared with nobody until the member says otherwise', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const PrivacyScreen()));
      await t.pumpAndSettle();
      expect(api.priv.shareTraining, 'off');
      await tapText(t, 'Who sees my training summary');
      await tapText(t, 'My trainer');
      expect(api.priv.shareTraining, 'trainer');
    });
  });

  group('notifications', () {
    testWidgets('optional notices switch, mandatory ones are listed and cannot be switched', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const NotificationsScreen()));
      await t.pumpAndSettle();
      expect(find.text('Receipts and payment confirmations'), findsOneWidget);
      await tapText(t, 'Messages from my gym');
      expect(api.notif.announcements, isFalse);
      await tapText(t, 'Membership expiry reminder');
      expect(api.notif.expiryOn, isFalse);
      expect(api.notif.mandatory, isNotEmpty);
    });

    testWidgets('offline, the switch goes back and says why', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const NotificationsScreen()));
      await t.pumpAndSettle();
      api.offline = true;
      await tapText(t, 'Messages from my gym');
      expect(api.notif.announcements, isTrue);
      expect(find.text('You need to be online to do this.'), findsOneWidget);
    });
  });

  group('membership requests', () {
    testWidgets('empty first, then a request can be made and withdrawn', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const RequestsScreen()));
      await t.pumpAndSettle();
      expect(find.text('You have not made any requests.'), findsOneWidget);
      api.reqs.add(const MembershipRequest(id: 'q9', type: 'renew', status: 'pending', createdAt: '2026-10-09T10:00:00Z', planName: 'Gold Monthly'));
      await t.pumpWidget(host(RequestsScreen(key: UniqueKey())));
      await t.pumpAndSettle();
      expect(find.text('Renew'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      await tapText(t, 'Withdraw');
      await t.tap(find.text('Withdraw').last);
      await t.pumpAndSettle();
      expect(api.calls, contains('withdraw:q9'));
    });

    testWidgets('a decided request shows the gym\'s answer and cannot be withdrawn', (t) async {
      await setSize(t);
      api.reqs.add(const MembershipRequest(id: 'q1', type: 'cancel', status: 'rejected', createdAt: '2026-10-09T10:00:00Z', decisionNote: 'Please visit the desk'));
      await t.pumpWidget(host(const RequestsScreen()));
      await t.pumpAndSettle();
      expect(find.text('Gym: Please visit the desk'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
    });

    testWidgets('a renewal names the plan; a cancellation does not', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const NewRequestScreen(initialType: 'change_plan')));
      await t.pumpAndSettle();
      await tapText(t, 'Annual');
      await tapText(t, 'Send request');
      expect(api.calls.last, startsWith('request:change_plan:'));
      expect(api.reqs, hasLength(1));
    });
  });

  group('delete account', () {
    testWidgets('needs a code AND the word DELETE, then signs out', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const DeleteAccountScreen()));
      await t.pumpAndSettle();
      expect(find.textContaining('Your gym keeps'), findsOneWidget);
      await tapText(t, 'Send me a code to confirm');
      await t.enterText(find.byType(TextField).first, '123456');
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Delete my account'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete my account'));
      await t.pumpAndSettle();
      expect(find.text('Type DELETE to confirm.'), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('delete:')), isEmpty, reason: 'nothing is sent without the word');
      await t.enterText(find.byType(TextField).last, 'DELETE');
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Delete my account'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete my account'));
      await t.pumpAndSettle();
      expect(api.calls, contains('delete:123456'));
      expect(signOuts, 1);
    });
  });

  test('failure() explains network errors plainly and passes the server\'s own message through', () {
    expect(failure(ApiException.network()), 'You need to be online to do this.');
    expect(failure(ApiException(status: 409, code: 'CONFLICT', message: 'You already have a pending request of this kind.')), 'You already have a pending request of this kind.');
    expect(failure(StateError('x'), 'Fallback'), 'Fallback');
  });

  group('workout day reminder', () {
    test('rings on planned weekdays only, and is off without a plan', () {
      final log = {'reminder': {'on': true, 'time': '06:45'}, 'week': {'1': ['r1'], '3': ['r1'], '5': <String>[]}};
      final p = ReminderPlan.of(log, now: DateTime(2026, 10, 10));
      expect(p.on, isTrue);
      expect([p.hour, p.minute], [6, 45]);
      expect(p.days, [1, 3]);
      expect(ReminderPlan.of({'reminder': {'on': true}, 'week': {}}).on, isFalse, reason: 'nothing planned, nothing to remind');
      expect(ReminderPlan.of({'week': {'1': ['r']}}).on, isFalse, reason: 'off until the member turns it on');
    });
    test('today is skipped when a workout is already logged', () {
      final now = DateTime(2026, 10, 10, 9);
      final log = {'reminder': {'on': true, 'time': '07:30'}, 'week': {'6': ['r']}, 'workouts': [{'d': '2026-10-10', 'start': now.millisecondsSinceEpoch, 'end': now.millisecondsSinceEpoch + 1}]};
      expect(ReminderPlan.of(log, now: now).skipThrough, '2026-10-10');
      expect(ReminderPlan.of({...log, 'workouts': []}, now: now).skipThrough, '');
    });
    test('a damaged time falls back to the default instead of crashing', () {
      expect(ReminderPlan.of({'reminder': {'on': true, 'time': 'soon'}, 'week': {'0': ['r']}}).hour, 7);
    });
  });
}
