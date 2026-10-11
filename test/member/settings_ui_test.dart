// The member's Settings: every page, every row, and what each setting does to the screens it affects.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/features/member/native/domain/backup.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/domain/plan.dart' show isoOf;
import 'package:gym_book_app/features/member/native/domain/rows.dart';
import 'package:gym_book_app/features/member/native/log_store.dart';
import 'package:gym_book_app/features/member/native/ui/activity_card.dart';
import 'package:gym_book_app/features/member/native/ui/home_screen.dart';
import 'package:gym_book_app/features/member/native/ui/library_screen.dart';
import 'package:gym_book_app/features/member/native/ui/native_app.dart';
import 'package:gym_book_app/features/member/native/ui/scope.dart';
import 'package:gym_book_app/features/member/native/ui/settings_pages.dart';
import 'package:gym_book_app/features/member/native/ui/settings_screen.dart';
import 'package:gym_book_app/features/member/native/ui/start_screen.dart';
import 'package:gym_book_app/features/member/native/ui/theme.dart';
import 'package:gym_book_app/features/member/native/ui/workout_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_ui_test.dart' show FakeGymApi, overview, setSize;

late Catalogue cat;
late MemberLogStore store;
late FakeGymApi api;
int signOuts = 0;
int signOutsEverywhere = 0;
bool everywhereFails = false;

Widget host(Widget home) => NativeScope(
  store: store, catalogue: cat, memberName: 'Asha Rao', mediaBase: null, overview: overview, gymApi: api,
  signOut: () async => signOuts++,
  signOutEverywhere: () async {
    if (everywhereFails) throw ApiException.network();
    signOutsEverywhere++;
  },
  child: ThemedMemberApp(store: store, home: home),
);

Json workout(String id, String day, {int minutes = 40, double w = 60, int r = 8, String ex = '0025'}) => {
  'id': id, 'd': day, 'start': DateTime.parse('${day}T10:00:00').millisecondsSinceEpoch, 'end': DateTime.parse('${day}T10:00:00').millisecondsSinceEpoch + minutes * 60000,
  'name': 'Session $id', 'entries': [{'id': ex, 'sets': [{'w': w, 'r': r, 'done': true}, {'w': w, 'r': r, 'done': true}]}],
};


/// Taps [f] after scrolling it fully into view (a row can be built yet below the screen edge).
Future<void> tapT(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable));
    if (list.evaluate().isNotEmpty) await t.scrollUntilVisible(f, 200, scrollable: list.first);
  }
  if (f.evaluate().length == 1) {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }
  await t.tap(f);
}

Future<void> open(WidgetTester t, String page, {String? row}) async {
  await t.pumpWidget(host(const SettingsScreen()));
  await t.pumpAndSettle();
  await tapT(t, find.text(page));
  await t.pumpAndSettle();
  if (row != null) {
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.text(row), 200, scrollable: list);
  }
}

Future<void> toggle(WidgetTester t, String row) async {
  final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
  await t.scrollUntilVisible(find.text(row), 200, scrollable: list);
  await t.ensureVisible(find.text(row));
  await t.pumpAndSettle();
  await t.tap(find.text(row));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    cat = await Catalogue.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = MemberLogStore(key: 'settings-test', prefs: await SharedPreferences.getInstance());
    await store.load();
    api = FakeGymApi();
    signOuts = 0;
    signOutsEverywhere = 0;
    everywhereFails = false;
    OG.palette = OGPalette.of(const {}, systemDark: true);
  });
  tearDown(() => OG.palette = OGPalette.of(const {}, systemDark: true));

  group('the Settings root', () {
    testWidgets('shows who you are, the pages and a preview of each', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const SettingsScreen()));
      await t.pumpAndSettle();
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Iron Temple'), findsOneWidget);
      for (final page in ['Workout', 'Timer alerts', 'Plan & schedule', 'Units', 'Equipment', 'Look & Home', 'Data & backup', 'About']) {
        expect(find.text(page), findsOneWidget, reason: page);
      }
      expect(find.text('1:30 rest'), findsOneWidget, reason: 'the default rest timer');
      expect(find.text('Sound · Vibrate'), findsOneWidget);
      expect(find.text('kg · 0.5'), findsOneWidget);
      expect(find.text('Dark · Green'), findsOneWidget);
    });

    testWidgets('search finds a row by its title or a word people use for it, and opens its page', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const SettingsScreen()));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'pounds');
      await t.pumpAndSettle();
      expect(find.text('Weight unit'), findsOneWidget);
      expect(find.text('1 RESULT'), findsOneWidget);
      await tapT(t, find.text('Weight unit'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Units'), findsOneWidget);
      Navigator.of(t.element(find.byType(Scaffold).first)).pop();
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'zzzz nothing');
      await t.pumpAndSettle();
      expect(find.textContaining('No setting matches'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'opt out');
      await t.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget, reason: 'the gym messages choice is searchable too');
    });

    test('every searchable row points at a page that exists', () {
      for (final e in settingsIndex) {
        expect(() => pageInfo(e.page), returnsNormally, reason: e.title);
      }
      expect(searchSettings('weigh').map((e) => e.title), contains('Weigh in before workouts'));
      expect(searchSettings('   '), isEmpty);
    });
  });

  group('switches and choices are saved in the log, and read back', () {
    final switches = <(String page, String row, String key, Object expected)>[
      ('Workout', 'Collapse completed exercises', 'collapseCompleted', true),
      ('Workout', 'Weigh in before workouts', 'weighIn', false),
      ('Workout', 'Keep screen awake', 'keepAwake', false),
      ('Timer alerts', 'Play a sound', 'sound', false),
      ('Timer alerts', 'Vibrate', 'vibrate', false),
      ('Timer alerts', 'Flash the screen', 'timerFlash', true),
      ('Look & Home', 'Gym check-in', 'checkIn', false),
      ('Look & Home', 'Body weight', 'showWeightCard', false),
      ('Look & Home', 'Show connection status', 'connStatus', false),
    ];
    for (final (page, row, key, want) in switches) {
      testWidgets('$page → $row', (t) async {
        await setSize(t);
        await open(t, page);
        await toggle(t, row);
        expect(store.state[key], want, reason: key);
        expect(store.dirty, isTrue, reason: 'it will sync to the account');
        await toggle(t, row);
        expect(store.state[key], !(want as bool), reason: 'and back');
      });
    }

    testWidgets('segmented and select rows', (t) async {
      await setSize(t);
      await open(t, 'Workout');
      await tapT(t, find.text('RIR'));
      await t.pumpAndSettle();
      expect(store.state['effort'], 'rir');
      await tapT(t, find.text('RPE'));
      await t.pumpAndSettle();
      expect(store.state['effort'], 'rpe');
      await tapT(t, find.text('Off').first);
      await t.pumpAndSettle();
      expect(store.state['effort'], 'none');
      await tapT(t, find.text('Small'));
      await t.pumpAndSettle();
      expect(store.state['gifSize'], 'mini');
      // the "Shown under each exercise" sheet
      await tapT(t, find.text('Shown under each exercise'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Best set'));
      await t.pumpAndSettle();
      expect(store.state['logRef'], 'best');
      // Fine-tuning
      await tapT(t, find.text('Fine-tuning'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Planned sessions start from'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Your last session'));
      await t.pumpAndSettle();
      expect(store.state['startFrom'], 'last');
      await toggle(t, 'Weight and reps buttons');
      expect(asMap(store.state['wc'])['steppers'], false);
    });

    testWidgets('Plan & schedule: the week can start on Sunday', (t) async {
      await setSize(t);
      await open(t, 'Plan & schedule');
      await tapT(t, find.text('Sunday'));
      await t.pumpAndSettle();
      expect(store.state['weekStart'], 0);
      await tapT(t, find.text('Monday'));
      await t.pumpAndSettle();
      expect(store.state['weekStart'], 1);
    });

    testWidgets('Units: decimals and the 1RM formula', (t) async {
      await setSize(t);
      await open(t, 'Units');
      await tapT(t, find.text('0.25'));
      await t.pumpAndSettle();
      expect(store.state['wdec'], 2);
      await tapT(t, find.text('1RM formula'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Brzycki'));
      await t.pumpAndSettle();
      expect(store.state['oneRmFormula'], 'brzycki');
    });
  });

  group('kg and lb', () {
    testWidgets('switching asks, and converting changes every stored weight', (t) async {
      await setSize(t);
      store.state['workouts'] = [workout('a', '2026-09-01', w: 100)];
      store.state['bodyweight'] = [{'d': '2026-09-01', 'w': 80}];
      await open(t, 'Units');
      await tapT(t, find.text('lb'));
      await t.pumpAndSettle();
      expect(find.text('Convert the numbers'), findsOneWidget);
      await tapT(t, find.text('Convert the numbers'));
      await t.pumpAndSettle();
      expect(store.state['unit'], 'lb');
      expect(asRows(asRows(asRows(store.state['workouts']).first['entries']).first['sets']).first['w'], 220.5);
      expect(asRows(store.state['bodyweight']).first['w'], 176.4);
      expect(asMap(store.state['unitSet'])['convert'], true, reason: 'stamped so another phone follows');
    });

    testWidgets('"keep the numbers" only changes the label; closing the sheet changes nothing', (t) async {
      await setSize(t);
      store.state['workouts'] = [workout('a', '2026-09-01', w: 100)];
      await open(t, 'Units');
      await tapT(t, find.text('lb'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10)); // dismiss the sheet
      await t.pumpAndSettle();
      expect(store.state['unit'], isNull, reason: 'untouched');
      await tapT(t, find.text('lb'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Keep the numbers, change the label'));
      await t.pumpAndSettle();
      expect(store.state['unit'], 'lb');
      expect(asRows(asRows(asRows(store.state['workouts']).first['entries']).first['sets']).first['w'], 100);
      expect(asMap(store.state['unitSet'])['convert'], false);
    });
  });

  group('Look & Home', () {
    testWidgets('the theme changes the whole app at once: dark, light, and system', (t) async {
      await setSize(t);
      await open(t, 'Look & Home');
      expect(OG.palette.dark, isTrue);
      await tapT(t, find.text('Light'));
      await t.pumpAndSettle();
      expect(store.state['theme'], 'light');
      expect(OG.palette.dark, isFalse);
      expect(OG.bg, const Color(0xFFF2F2F7));
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(Theme.of(t.element(find.byType(Scaffold).first)).brightness, Brightness.light);
      expect(scaffold.backgroundColor ?? Theme.of(t.element(find.byType(Scaffold).first)).scaffoldBackgroundColor, const Color(0xFFF2F2F7));
      await tapT(t, find.text('Dark'));
      await t.pumpAndSettle();
      expect(OG.palette.dark, isTrue);
      await tapT(t, find.text('System'));
      await t.pumpAndSettle();
      expect(store.state['theme'], 'system');
    });

    testWidgets('an accent: a preset recolours the app; your own colour is checked for contrast', (t) async {
      await setSize(t);
      await open(t, 'Look & Home');
      final green = OG.acc;
      await tapT(t, find.byKey(const ValueKey('accent-sky')));
      await t.pumpAndSettle();
      expect(store.state['accent'], 'sky');
      expect(OG.acc, isNot(green));
      expect(OG.acc, const Color(0xFF0A84FF));
      expect(find.text('Dark · Blue'), findsNothing); // the root is not on screen; the label on this page changes instead
      expect(find.text('Blue'), findsWidgets);
      // a colour of your own that would vanish into the dark theme is drawn lighter
      await tapT(t, find.byKey(const ValueKey('accent-custom')));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Hex'), '#102030');
      await t.pumpAndSettle();
      await tapT(t, find.text('Use this color'));
      await t.pumpAndSettle();
      expect(store.state['accent'], 'custom');
      expect(store.state['accentCustom'], '#102030');
      expect(OG.acc, isNot(const Color(0xFF102030)), reason: 'too dark to read on black');
      expect(find.textContaining('so it stays readable'), findsOneWidget);
    });

    testWidgets('the body diagram follows the setting', (t) async {
      await setSize(t);
      await open(t, 'Look & Home');
      await tapT(t, find.text('Female'));
      await t.pumpAndSettle();
      expect(store.state['body'], 'female');
    });
  });

  group('Equipment profiles', () {
    testWidgets('add a profile, tick what you own, filter the library by it, and turn it off', (t) async {
      await setSize(t);
      await open(t, 'Equipment');
      await tapT(t, find.text('Add equipment profile'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Home');
      await tapT(t, find.text('Add'));
      await t.pumpAndSettle();
      // the editor opens straight away; tick two things and save
      for (final label in ['dumbbell', 'bench']) {
        final chip = find.widgetWithText(FilterChip, label);
        await t.ensureVisible(chip);
        await tapT(t, chip);
        await t.pumpAndSettle();
      }
      await tapT(t, find.text('Save'));
      await t.pumpAndSettle();
      final profile = asRows(store.state['equipProfiles']).single;
      expect(profile['name'], 'Home');
      expect(profile['equipment'], containsAll(['dumbbell', 'bench']));
      expect(store.state['activeEquipId'], profile['id']);
      expect(store.state['equipFilterOn'], isNot(true), reason: 'nothing is filtered until you turn it on');
      await tapT(t, find.text('Filter by equipment'));
      await t.pumpAndSettle();
      expect(store.state['equipFilterOn'], true);
    });

    testWidgets('the library, and the picker, only list what the active profile allows', (t) async {
      await setSize(t);
      store.state['equipProfiles'] = [{'id': 'e1', 'name': 'Home', 'equipment': ['dumbbell', 'bench', 'pull-up bar'], 'accV': 1}];
      store.state['activeEquipId'] = 'e1';
      store.state['equipFilterOn'] = true;
      await t.pumpWidget(host(const Scaffold(body: LibraryScreen())));
      await t.pumpAndSettle();
      expect(find.textContaining('Only what you can do with Home'), findsOneWidget);
      final withProfile = find.textContaining(RegExp(r'^\d+ exercises$')).evaluate().first.widget as Text;
      store.state['equipFilterOn'] = false;
      store.update((_) {});
      await t.pumpAndSettle();
      final without = find.textContaining(RegExp(r'^\d+ exercises$')).evaluate().first.widget as Text;
      int n(Text w) => int.parse(w.data!.split(' ').first);
      expect(n(withProfile), lessThan(n(without)));
      expect(find.textContaining('Only what you can do'), findsNothing);
    });
  });

  group('My account', () {
    testWidgets('sign out, and sign out everywhere (which needs the server)', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const SettingsPage('account')));
      await t.pumpAndSettle();
      await tapT(t, find.text('Sign out').first);
      await t.pumpAndSettle();
      await tapT(t, find.widgetWithText(TextButton, 'Sign out'));
      await t.pumpAndSettle();
      expect(signOuts, 1);
      everywhereFails = true;
      await tapT(t, find.text('Sign out everywhere'));
      await t.pumpAndSettle();
      await tapT(t, find.widgetWithText(TextButton, 'Sign out everywhere'));
      await t.pumpAndSettle();
      expect(find.text('You need to be online to sign out everywhere.'), findsOneWidget);
      expect(signOutsEverywhere, 0, reason: 'nothing happened');
      everywhereFails = false;
      await tapT(t, find.text('Sign out everywhere'));
      await t.pumpAndSettle();
      await tapT(t, find.widgetWithText(TextButton, 'Sign out everywhere'));
      await t.pumpAndSettle();
      expect(signOutsEverywhere, 1);
    });

    testWidgets('Sync now and the sync line', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const SettingsPage('account')));
      await t.pumpAndSettle();
      expect(find.text('All changes saved to your account'), findsOneWidget);
      store.update((s) => s['sound'] = false, syncSoon: false);
      await t.pumpAndSettle();
      expect(find.text('Changes waiting to sync'), findsOneWidget);
    });
  });

  group('what the settings do to the screens', () {
    testWidgets('Home: the check-in button, the body-weight card and the connection banner follow their switches', (t) async {
      await setSize(t);
      t.view.physicalSize = const Size(1080, 5000);
      await t.pumpWidget(host(Scaffold(body: HomeScreen(onTab: (_) {}))));
      await t.pumpAndSettle();
      expect(find.text('Check in'), findsOneWidget);
      expect(find.text('Body weight'), findsOneWidget);
      store.update((s) {
        s['checkIn'] = false;
        s['showWeightCard'] = false;
      }, syncSoon: false);
      await t.pumpAndSettle();
      expect(find.text('Check in'), findsNothing);
      expect(find.text('My profile'), findsOneWidget, reason: 'the profile button stays');
      expect(find.text('Body weight'), findsNothing);
    });

    testWidgets('Home: a new member can load a starter plan in one tap', (t) async {
      await setSize(t);
      t.view.physicalSize = const Size(1080, 5000);
      await t.pumpWidget(host(Scaffold(body: HomeScreen(onTab: (_) {}))));
      await t.pumpAndSettle();
      await tapT(t, find.text('Load starter plan'));
      await t.pumpAndSettle();
      expect(find.text('Choose starter plan'), findsOneWidget);
      await tapT(t, find.text('Push / Pull / Legs'));
      await t.pumpAndSettle();
      expect(asRows(store.state['routines']).map((r) => r['name']), ['Push Day', 'Pull Day', 'Leg Day']);
      expect(asMap(store.state['week']).keys.toSet(), {'1', '3', '5'});
      expect(find.text('Push / Pull / Legs loaded'), findsOneWidget);
      expect(find.text('Welcome!'), findsNothing, reason: 'the plan is there, so the welcome card is gone');
    });

    testWidgets('Start asks to weigh in; the weight goes on the session and on the weigh-ins; skipping and the switch both work', (t) async {
      await setSize(t);
      store.state['routines'] = [{'id': 'r1', 'name': 'Push', 'ex': [{'id': '0025', 'sets': 3, 'reps': 8, 'weight': 0}]}];
      final now = DateTime.now();
      store.state['week'] = {'${now.weekday % 7}': ['r1']};
      await t.pumpWidget(host(const StartScreen()));
      await t.pumpAndSettle();
      await tapT(t, find.text('Start'));
      await t.pumpAndSettle();
      expect(find.text('Weigh in'), findsOneWidget);
      await tapT(t, find.text('Save and start'));
      await t.pumpAndSettle();
      expect(store.active, isNotNull);
      expect(store.active!['bw'], 70, reason: 'the default when nothing was logged yet');
      expect(asRows(store.state['bodyweight']).single['d'], isoOf(now));
      // switched off: no question
      Navigator.of(t.element(find.byType(WorkoutScreen))).pop();
      await t.pumpAndSettle();
      store.updateLocalOnly((s) => s['active'] = null);
      store.update((s) => s['weighIn'] = false, syncSoon: false);
      await t.pumpAndSettle();
      await tapT(t, find.text('Start'));
      await t.pumpAndSettle();
      expect(find.text('Weigh in'), findsNothing);
      expect(store.active, isNotNull);
      expect(store.active!['bw'], isNull);
    });

    testWidgets('a freestyle workout asks for the weigh-in too, and carries the weight', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const StartScreen()));
      await t.pumpAndSettle();
      await tapT(t, find.text('Freestyle workout (pick as you go)'));
      await t.pumpAndSettle();
      expect(find.text('Weigh in'), findsOneWidget);
      await tapT(t, find.text('Save and start'));
      await t.pumpAndSettle();
      expect(store.active, isNotNull);
      expect(store.active!['name'], 'Freestyle');
      expect(store.active!['bw'], 70);
      expect(asRows(store.state['bodyweight']), hasLength(1));
    });

    testWidgets('closing the weigh-in dialog starts nothing', (t) async {
      await setSize(t);
      store.state['routines'] = [{'id': 'r1', 'name': 'Push', 'ex': [{'id': '0025', 'sets': 3, 'reps': 8, 'weight': 0}]}];
      store.state['week'] = {'${DateTime.now().weekday % 7}': ['r1']};
      await t.pumpWidget(host(const StartScreen()));
      await t.pumpAndSettle();
      await tapT(t, find.text('Start'));
      await t.pumpAndSettle();
      await tapT(t, find.text('Cancel'));
      await t.pumpAndSettle();
      expect(store.active, isNull);
    });

    testWidgets('the workout: effort per set, the buttons switch, the rest timer and "Best set"', (t) async {
      await setSize(t);
      store.state['workouts'] = [workout('a', '2026-09-01', w: 100, r: 5)];
      store.state['effort'] = 'rir';
      store.state['logRef'] = 'best';
      store.state['weighIn'] = false;
      store.updateLocalOnly((s) => s['active'] = {
        'id': 'w1', 'd': isoOf(DateTime.now()), 'start': DateTime.now().millisecondsSinceEpoch, 'name': 'Push', 'entries': [{'id': '0025', 'sets': [{'w': 60, 'r': 8, 'done': false}, {'w': 60, 'r': 8, 'done': false}]}],
      });
      await t.pumpWidget(host(const WorkoutScreen()));
      await t.pumpAndSettle();
      expect(find.text('Best set: 100 kg × 5'), findsOneWidget);
      expect(find.text('RIR'), findsNWidgets(2), reason: 'one effort line per set');
      // + starts at 0 (nothing left in the tank), then steps up; − off the bottom clears it
      final plus = find.descendant(of: find.byType(ListView), matching: find.byIcon(Icons.add)).evaluate().length;
      expect(plus, greaterThan(0));
      await tapT(t, find.byTooltip('Done').first);
      await t.pumpAndSettle();
      expect(find.text('Rest'), findsOneWidget, reason: 'a rest timer starts when a set is ticked');
      // the member switches the rest timer off: ticking another set starts none
      await tapT(t, find.text('Skip'));
      store.update((s) => s['restSec'] = 0, syncSoon: false);
      await t.pumpAndSettle();
      await tapT(t, find.byTooltip('Done').last);
      await t.pumpAndSettle();
      expect(find.text('Rest'), findsNothing);
    });

    testWidgets('effort: stepping and typing write rir or rpe on the set, never both', (t) async {
      await setSize(t);
      store.state['effort'] = 'rir';
      store.updateLocalOnly((s) => s['active'] = {
        'id': 'w1', 'd': isoOf(DateTime.now()), 'start': DateTime.now().millisecondsSinceEpoch, 'name': 'Push', 'entries': [{'id': '0025', 'sets': [{'w': 60, 'r': 8, 'done': false, 'rpe': 8}]}],
      });
      await t.pumpWidget(host(const WorkoutScreen()));
      await t.pumpAndSettle();
      // the set was rated on the other scale: this scale shows empty, and the old rating is kept until you rate again
      final row = find.ancestor(of: find.text('RIR'), matching: find.byType(Row)).first;
      final plus = find.descendant(of: row, matching: find.byIcon(Icons.add));
      await tapT(t, plus);
      await t.pumpAndSettle();
      final set = asRows(asRows(store.active!['entries']).first['sets']).first;
      expect(set['rir'], 0.0, reason: 'empty + starts at the bottom of the scale');
      expect(set.containsKey('rpe'), isFalse, reason: 'one scale per set');
      await tapT(t, plus);
      await t.pumpAndSettle();
      expect(asRows(asRows(store.active!['entries']).first['sets']).first['rir'], 0.5);
      final minus = find.descendant(of: row, matching: find.byIcon(Icons.remove));
      await tapT(t, minus);
      await tapT(t, minus);
      await t.pumpAndSettle();
      expect(asRows(asRows(store.active!['entries']).first['sets']).first.containsKey('rir'), isFalse, reason: 'stepping off the bottom clears it');
    });

    testWidgets('finished exercises fold into one line when asked, and open again on tap', (t) async {
      await setSize(t);
      store.state['collapseCompleted'] = true;
      store.updateLocalOnly((s) => s['active'] = {
        'id': 'w1', 'd': isoOf(DateTime.now()), 'start': DateTime.now().millisecondsSinceEpoch, 'name': 'Push', 'entries': [
          {'id': '0025', 'sets': [{'w': 60, 'r': 8, 'done': true}]},
          {'id': '0047', 'sets': [{'w': 40, 'r': 10, 'done': false}]},
        ],
      });
      await t.pumpWidget(host(const WorkoutScreen()));
      await t.pumpAndSettle();
      expect(find.text('Add set'), findsOneWidget, reason: 'only the unfinished exercise is open');
      await tapT(t, find.byIcon(Icons.expand_more));
      await t.pumpAndSettle();
      expect(find.text('Add set'), findsNWidgets(2));
    });

    testWidgets('with the buttons switched off a number is tapped and typed', (t) async {
      await setSize(t);
      store.update((s) => s['wc'] = {'steppers': false}, syncSoon: false);
      store.updateLocalOnly((s) => s['active'] = {
        'id': 'w1', 'd': isoOf(DateTime.now()), 'start': DateTime.now().millisecondsSinceEpoch, 'name': 'Push', 'entries': [{'id': '0025', 'sets': [{'w': 60, 'r': 8, 'done': false}]}],
      });
      await t.pumpWidget(host(const WorkoutScreen()));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(ListView), matching: find.byIcon(Icons.remove)), findsNothing);
      await tapT(t, find.text('60'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '62.5');
      await tapT(t, find.text('OK'));
      await t.pumpAndSettle();
      expect(asRows(asRows(store.active!['entries']).first['sets']).first['w'], 62.5);
    });

    testWidgets('exercise pictures: hidden removes them from the workout', (t) async {
      await setSize(t);
      store.updateLocalOnly((s) => s['active'] = {
        'id': 'w1', 'd': isoOf(DateTime.now()), 'start': DateTime.now().millisecondsSinceEpoch, 'name': 'Push', 'entries': [{'id': '0025', 'sets': [{'w': 60, 'r': 8, 'done': false}]}],
      });
      await t.pumpWidget(host(const WorkoutScreen()));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.fitness_center), findsWidgets);
      store.update((s) => s['gifSize'] = 'off', syncSoon: false);
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.fitness_center), findsNothing);
    });
  });

  group('Stats → Activity', () {
    testWidgets('openGym\'s heatmap: shaded days, a Time/Volume switch that is remembered, and a tap that opens the workout', (t) async {
      await setSize(t);
      final today = DateTime.now();
      final d1 = isoOf(today.subtract(const Duration(days: 3)));
      final d2 = isoOf(today.subtract(const Duration(days: 9)));
      store.state['workouts'] = [workout('a', d1, minutes: 30), workout('b', d2, minutes: 90, w: 100)];
      await t.pumpWidget(host(const Scaffold(body: SingleChildScrollView(child: ActivityCard()))));
      await t.pumpAndSettle();
      expect(find.text('Activity (last 12 months)'), findsOneWidget);
      expect(find.text('Less time'), findsOneWidget);
      Color colorOf(String iso) => ((t.widget<Container>(find.byKey(ValueKey('hm-$iso'))).decoration! as BoxDecoration).color)!;
      expect(colorOf(d2), isNot(colorOf(d1)), reason: 'a longer session is a darker day');
      expect(colorOf(d1), isNot(OG.card2), reason: 'a trained day is shaded');
      final empty = isoOf(today.subtract(const Duration(days: 20)));
      expect(colorOf(empty), OG.card2);
      await tapT(t, find.text('Volume'));
      await t.pumpAndSettle();
      expect(store.state['heatmapMetric'], 'vol');
      expect(find.text('Less volume'), findsOneWidget);
      // tapping a trained day opens its workout; an empty day does nothing
      await tapT(t, find.byKey(ValueKey('hm-$empty')));
      await t.pumpAndSettle();
      expect(find.text('Session a'), findsNothing);
      await tapT(t, find.byKey(ValueKey('hm-$d1')));
      await t.pumpAndSettle();
      expect(find.text('Session a'), findsOneWidget);
    });

    testWidgets('two workouts on one day open a list to choose from', (t) async {
      await setSize(t);
      final d = isoOf(DateTime.now().subtract(const Duration(days: 2)));
      store.state['workouts'] = [workout('a', d), workout('b', d, ex: '0047')];
      await t.pumpWidget(host(const Scaffold(body: SingleChildScrollView(child: ActivityCard()))));
      await t.pumpAndSettle();
      await tapT(t, find.byKey(ValueKey('hm-$d')));
      await t.pumpAndSettle();
      expect(find.text('Session a'), findsOneWidget);
      expect(find.text('Session b'), findsOneWidget);
      await tapT(t, find.text('Session b'));
      await t.pumpAndSettle();
      expect(find.text('Session b'), findsWidgets);
    });

    testWidgets('a long press tells the day\'s totals, as hovering does in openGym', (t) async {
      await setSize(t);
      final d = isoOf(DateTime.now().subtract(const Duration(days: 4)));
      store.state['workouts'] = [workout('a', d, minutes: 45)];
      await t.pumpWidget(host(const Scaffold(body: SingleChildScrollView(child: ActivityCard()))));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(ValueKey('hm-$d')));
      await t.pumpAndSettle();
      expect(find.textContaining('$d · 1 workout · 45 min · 960 kg'), findsOneWidget);
    });

    testWidgets('the grid starts on the chosen first day of the week', (t) async {
      await setSize(t);
      await t.pumpWidget(host(const Scaffold(body: SingleChildScrollView(child: ActivityCard()))));
      await t.pumpAndSettle();
      final mon = t.getTopLeft(find.text('Mon')).dy, wed = t.getTopLeft(find.text('Wed')).dy;
      expect(wed - mon, 28, reason: 'Mon is row 0 and Wed row 2 when the week starts on Monday (rows are 14 apart)');
      store.update((s) => s['weekStart'] = 0, syncSoon: false);
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('Mon')).dy - mon, 14, reason: 'with Sunday first, Monday is one row further down');
    });
  });

  group('backups', () {
    test('an export is the openGym document without the unfinished workout, and importing it back is lossless', () {
      final log = {'unit': 'lb', 'workouts': [workout('a', '2026-09-01')], 'routines': <Object?>[], 'active': {'id': 'x'}, 'someOpenGymKey': {'keep': true}};
      final text = exportBackup(log);
      final back = parseBackup(text);
      expect(back.containsKey('active'), isFalse);
      expect(back['someOpenGymKey'], {'keep': true});
      expect(backupFileName(DateTime(2026, 10, 9)), 'gymmie-backup-2026-10-09.json');
      expect(backupSummary(back).workouts, 1);
    });

    test('a file that is not a backup is refused with a sentence a member can act on', () {
      for (final bad in ['', 'not json', '[]', '{"x":1}', '{"workouts":"no"}', '{"week":[]}', 'x' * (backupMaxBytes + 1)]) {
        expect(() => parseBackup(bad), throwsA(isA<BackupError>()), reason: bad.length > 40 ? 'huge' : bad);
      }
    });

    test('importing adds to the log: nothing logged is lost, this phone wins a clash, units are aligned', () async {
      store.state['workouts'] = [workout('mine', '2026-09-02', w: 100)];
      store.state['unit'] = 'kg';
      store.state['unitSet'] = {'at': 1, 'convert': true};
      final backup = parseBackup(jsonEncode({
        'unit': 'lb', 'unitSet': {'at': 5, 'convert': true}, 'workouts': [workout('old', '2026-08-01', w: 220.5), workout('mine', '2026-09-02', w: 1)],
        'routines': [{'id': 'r1', 'name': 'Push', 'ex': <Object?>[]}], 'bodyweight': [{'d': '2026-08-01', 'w': 176.4}],
      }));
      store.importBackup(backup);
      final ws = asRows(store.state['workouts']);
      expect(ws.map((w) => w['id']), ['old', 'mine'], reason: 'both logs are there');
      String wOf(Json w) => '${asRows(asRows(w['entries']).first['sets']).first['w']}';
      expect(store.state['unit'], 'lb', reason: 'the later unit switch wins');
      expect(wOf(ws.firstWhere((w) => w['id'] == 'mine')), '220.5', reason: 'this phone\'s 100 kg, converted, wins the clash over the backup\'s entry');
      expect(wOf(ws.firstWhere((w) => w['id'] == 'old')), '220.5');
      expect(asRows(store.state['routines']).single['name'], 'Push');
      expect(store.dirty, isTrue);
    });
  });
}
