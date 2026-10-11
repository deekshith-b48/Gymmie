import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/features/member/native/domain/assigned.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/domain/merge.dart';
import 'package:gym_book_app/core/network/api_exception.dart';
import 'package:gym_book_app/features/member/member_models.dart';
import 'package:gym_book_app/features/member/native/domain/rows.dart';
import 'package:gym_book_app/features/member/native/domain/visits.dart';
import 'package:gym_book_app/features/member/native/domain/session.dart';
import 'package:gym_book_app/features/member/native/log_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise ex(String id, {Map<String, double> w = const {'chest': 1}, bool cardio = false, bool assisted = false}) => Exercise(
  id: id, name: 'Ex $id', bodypart: 'chest', equipment: 'barbell', category: '', img: '', gif: '', weights: w,
  cardio: cardio, assisted: assisted,
);

Json workout(String id, String day, String exId, List<List<num>> rows, {bool done = true}) => {
  'id': id, 'd': day, 'start': DateTime.parse('${day}T17:00:00Z').millisecondsSinceEpoch,
  'entries': [
    {'id': exId, 'sets': [for (final r in rows) {'w': r[0], 'r': r[1], 'done': done}]},
  ],
};

void main() {
  group('starting a session', () {
    test('a new exercise opens with three rows at the known working weight, or 0', () {
      final s = defaultLog();
      var e = buildEntry(ex('a'), s);
      expect((e['sets'] as List).length, 3);
      expect(e['sets'][0], {'w': 0, 'r': 10, 'done': false});
      s['exWeights'] = {'a': {'w': 60}};
      e = buildEntry(ex('a'), s);
      expect(e['sets'][0]['w'], 60);
    });

    test('freestyle reproduces what you did last time, set for set', () {
      final s = defaultLog();
      (s['workouts'] as List).add(workout('h1', '2026-09-01', 'a', [[50, 8], [55, 6]]));
      final e = buildEntry(ex('a'), s);
      expect([for (final r in e['sets']) [r['w'], r['r'], r['done']]], [[50, 8, false], [55, 6, false]]);
    });

    test('warm-ups and unfinished sets of last time are not copied; a deload session is skipped', () {
      final s = defaultLog();
      final w = workout('h1', '2026-09-01', 'a', [[40, 5], [80, 5]]);
      (w['entries'][0]['sets'][0] as Json)['phase'] = 'warmup';
      (s['workouts'] as List).add(w);
      expect([for (final r in buildEntry(ex('a'), s)['sets']) r['w']], [80]);
      (s['workouts'] as List).add({...workout('h2', '2026-09-02', 'a', [[20, 5]]), 'excludeFromProgression': true});
      expect([for (final r in buildEntry(ex('a'), s)['sets']) r['w']], [80]);
    });

    test('a cardio exercise opens with minutes and speed', () {
      final e = buildEntry(ex('c', cardio: true, w: const {}), defaultLog());
      expect(e['sets'][0], {'min': 20, 'speed': 8, 'done': false});
    });
  });

  group('editing', () {
    test('ticking stamps the time, unticking removes it', () {
      final row = <String, dynamic>{'w': 50, 'r': 5, 'done': false};
      toggleDone(row, 1000);
      expect(row, {'w': 50, 'r': 5, 'done': true, 'at': 1000});
      toggleDone(row, 2000);
      expect(row.containsKey('at'), isFalse);
      expect(row['done'], isFalse);
    });
    test('add set copies the last row unticked; remove never empties an entry', () {
      final e = <String, dynamic>{'id': 'a', 'sets': <Json>[{'w': 50, 'r': 5, 'done': true, 'at': 5}]};
      addSet(e);
      expect(e['sets'][1], {'w': 50, 'r': 5, 'done': false});
      expect(removeSet(e, 1), isTrue);
      expect(removeSet(e, 0), isFalse);
      expect((e['sets'] as List).length, 1);
    });
  });

  group('finishing', () {
    test('saves only what was done, counts volume, remembers the weight and flags a record', () {
      final s = defaultLog();
      final e = buildEntry(ex('a'), s);
      final rows = (e['sets'] as List).cast<Json>();
      rows[0]..['w'] = 60..['r'] = 5;
      rows[1]..['w'] = 60..['r'] = 5;
      toggleDone(rows[0], 1_000_000);
      toggleDone(rows[1], 1_100_000);
      final active = newSession(id: 's1', day: '2026-10-10', now: 900_000, name: 'Freestyle', entries: [e]);
      final r = finishSession(s, active, now: 1_200_000);
      expect(r.weightRecords, ['a']);
      expect(r.workout['vol'], 600);
      expect((r.workout['entries'][0]['sets'] as List).length, 3, reason: 'the unticked row is kept as logged');
      expect(r.workout['entries'][0]['topW'], 60);
      expect(s['exWeights']['a'], {'w': 60, 'd': '2026-10-10'});
      expect((s['workouts'] as List).single['id'], 's1');
      expect(setsDone(r.workout), 2);
    });

    test('an exercise with no ticked set is dropped; a lighter session is no record', () {
      final s = defaultLog();
      (s['workouts'] as List).add(workout('h1', '2026-09-01', 'a', [[100, 5]]));
      s['exWeights'] = {'a': {'w': 100}};
      final a = buildEntry(ex('a'), s);
      final b = buildEntry(ex('b'), s);
      toggleDone((a['sets'] as List).first as Json, 5);
      final r = finishSession(s, newSession(id: 's2', day: '2026-10-10', now: 1, name: 'x', entries: [a, b]), now: 10);
      expect(r.workout['entries'].map((e) => e['id']).toList(), ['a']);
      expect(r.weightRecords, isEmpty);
      expect(s['exWeights']['a']['w'], 100);
    });

    test('more reps at the same weight is a strength record, not a weight record', () {
      final s = defaultLog();
      (s['workouts'] as List).add(workout('h1', '2026-09-01', 'a', [[100, 3]]));
      final a = {'id': 'a', 'sets': [<String, dynamic>{'w': 100, 'r': 8, 'done': true}]};
      final r = finishSession(s, newSession(id: 's3', day: '2026-10-10', now: 1, name: 'x', entries: [a]), now: 10);
      expect(r.weightRecords, isEmpty);
      expect(r.e1rmRecords.single.est, greaterThan(r.e1rmRecords.single.prev));
    });
  });

  group('exercise finding', () {
    final list = [
      ex('1', w: const {'chest': 1, 'triceps': 0.4}),
      ex('2', w: const {'triceps': 1}),
      ex('3', w: const {'biceps': 1}),
      ex('4', w: const {'chest': 0.4}),
    ];
    test('a focus lists primary hits first, then helpers, and nothing unrelated', () {
      expect([for (final e in exercisesForFocus(list, {'chest'})) e.id], ['1', '4']);
      expect([for (final e in exercisesForFocus(list, {'chest', 'triceps'})) e.id], ['1', '2', '4']);
      expect(exercisesForFocus(list, {}), isEmpty);
    });
    test('search needs every word', () {
      expect([for (final e in searchExercises(list, 'ex 1')) e.id], ['1']);
      expect(searchExercises(list, 'ex zzz'), isEmpty);
      expect(searchExercises(list, '  ').length, 4);
    });
  });

  group('merging two devices', () {
    test('keeps every logged session and weigh-in from both, this phone wins a clash', () {
      final local = {...defaultLog(), 'unit': 'lb', 'workouts': [workout('a', '2026-09-02', 'x', [[1, 1]]), workout('c', '2026-09-03', 'x', [[9, 9]])], 'bodyweight': [{'d': '2026-09-02', 'w': 80}]};
      final remote = {...defaultLog(), 'unit': 'lb', 'workouts': [workout('b', '2026-09-01', 'x', [[2, 2]]), workout('c', '2026-09-03', 'x', [[5, 5]])], 'bodyweight': [{'d': '2026-09-01', 'w': 81}, {'d': '2026-09-02', 'w': 99}]};
      final m = mergeLogs(local, remote);
      expect((m['workouts'] as List).map((w) => w['id']).toList(), ['b', 'a', 'c']);
      expect((m['workouts'] as List).last['entries'][0]['sets'][0]['w'], 9);
      expect((m['bodyweight'] as List).map((b) => b['w']).toList(), [81, 80]);
      expect(m['unit'], 'lb');
      expect(local['workouts'], hasLength(2), reason: 'inputs untouched');
    });
    test('two units: the later switch wins and the other copy is converted, never read in the wrong unit', () {
      final kg = {'unit': 'kg', 'workouts': [workout('a', '2026-09-01', 'x', [[100, 5]])], 'bodyweight': [{'d': '2026-09-01', 'w': 80}], 'exWeights': {'x': {'w': 100}}};
      final lb = {'unit': 'lb', 'unitSet': {'at': 5, 'convert': true}, 'workouts': [workout('b', '2026-09-02', 'x', [[220.5, 5]])], 'bodyweight': [{'d': '2026-09-02', 'w': 176.4}]};
      final m = mergeLogs(kg, lb);
      expect(m['unit'], 'lb');
      expect(m['unitSet'], {'at': 5, 'convert': true});
      final a = (m['workouts'] as List).firstWhere((w) => w['id'] == 'a');
      expect(a['entries'][0]['sets'][0]['w'], 220.5, reason: '100 kg is 220.5 lb');
      expect((m['bodyweight'] as List).first['w'], 176.4);
      expect(asMap(asMap(m['exWeights'])['x'])['w'], 220.5);
      // the same two copies the other way round give the same answer
      final m2 = mergeLogs(lb, kg);
      expect(m2['unit'], 'lb');
      expect((m2['workouts'] as List).firstWhere((w) => w['id'] == 'a')['entries'][0]['sets'][0]['w'], 220.5);
    });
    test('a switch that kept the numbers only relabels the other copy', () {
      final old = {'unit': 'kg', 'workouts': [workout('a', '2026-09-01', 'x', [[100, 5]])]};
      final relabelled = {'unit': 'lb', 'unitSet': {'at': 9, 'convert': false}, 'workouts': <Object?>[]};
      final m = mergeLogs(old, relabelled);
      expect(m['unit'], 'lb');
      expect((m['workouts'] as List).single['entries'][0]['sets'][0]['w'], 100);
    });
    test('a phone that never set a setting cannot overwrite the account\'s choice', () {
      final fresh = defaultLog()..['workouts'] = [workout('a', '2026-09-01', 'x', [[1, 1]])];
      final account = {'unit': 'lb', 'restSec': 120, 'weekStart': 0, 'theme': 'light', 'workouts': <Object?>[]};
      final m = mergeLogs(fresh, account);
      expect([m['unit'], m['restSec'], m['weekStart'], m['theme']], ['lb', 120, 0, 'light']);
    });
    test('the unfinished workout never travels and is never taken from the other device', () {
      final m = mergeLogs({...defaultLog(), 'active': {'id': 'mine'}}, {...defaultLog(), 'active': {'id': 'theirs'}});
      expect(m['active'], {'id': 'mine'});
      expect(mergeLogs(defaultLog()..remove('active'), {'active': {'id': 'theirs'}}).containsKey('active'), isFalse);
    });
    test('best-known weights keep the heavier one', () {
      final m = mergeLogs({'exWeights': {'a': {'w': 50}, 'b': {'w': 20}}}, {'exWeights': {'a': {'w': 70}, 'c': {'w': 5}}});
      expect({for (final e in asMap(m['exWeights']).entries) e.key: e.value['w']}, {'a': 70, 'b': 20, 'c': 5});
    });
  });

  group('MemberLogStore sync', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('works offline, keeps its changes across a restart, and pushes when the network is back', () async {
      final api = _FakeApi()..offline = true;
      final a = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await a.load();
      a.update((s) => (s['workouts'] as List).add(workout('w1', '2026-10-01', 'x', [[10, 10]])));
      await a.sync();
      expect(a.status, SyncStatus.offline);
      expect(a.dirty, isTrue);
      // "restart"
      final b = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await b.load();
      expect(b.state['workouts'], hasLength(1));
      expect(b.dirty, isTrue);
      api.offline = false;
      await b.sync();
      expect(b.status, SyncStatus.idle);
      expect(b.dirty, isFalse);
      expect(api.doc.rev, 1);
      expect(api.doc.state!['workouts'], hasLength(1));
      expect(api.doc.state!.containsKey('active'), isFalse);
    });

    test('a clean phone adopts a newer server copy and keeps its own unfinished workout', () async {
      final api = _FakeApi();
      final a = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await a.load();
      a.updateLocalOnly((s) => s['active'] = {'id': 'live'});
      api.doc = LogDoc(5, 'w', {...defaultLog(), 'workouts': [workout('r1', '2026-10-01', 'x', [[1, 1]])]});
      await a.sync();
      expect(a.state['workouts'], hasLength(1));
      expect(a.state['active'], {'id': 'live'});
      expect(a.baseRev, 5);
    });

    test('both changed: merged, pushed against the server revision, nothing lost', () async {
      final api = _FakeApi()..doc = LogDoc(3, 'w', {...defaultLog(), 'workouts': [workout('remote', '2026-10-01', 'x', [[1, 1]])]});
      final a = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await a.load();
      a.update((s) => (s['workouts'] as List).add(workout('mine', '2026-10-02', 'x', [[2, 2]])));
      await a.sync();
      expect((api.doc.state!['workouts'] as List).map((w) => w['id']).toList(), ['remote', 'mine']);
      expect(a.state['workouts'], hasLength(2));
      expect(a.dirty, isFalse);
      expect(api.lastBaseRev, 3);
    });

    test('a write that loses a race is read, merged and retried', () async {
      final api = _FakeApi()..raceOnce = true;
      final a = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await a.load();
      a.update((s) => (s['workouts'] as List).add(workout('mine', '2026-10-02', 'x', [[2, 2]])));
      await a.sync();
      expect(a.status, SyncStatus.idle);
      expect((api.doc.state!['workouts'] as List).map((w) => w['id']).toSet(), {'mine', 'raced'});
    });

    test('a damaged saved copy does not stop the app', () async {
      await prefs.setString('k:state', '{not json');
      final a = MemberLogStore(key: 'k', prefs: prefs);
      await a.load();
      expect(a.state['workouts'], isEmpty);
    });

    test('delete everything clears the server copy and this phone; sign-out wipes only the phone', () async {
      final api = _FakeApi();
      final a = MemberLogStore(key: 'k', prefs: prefs, api: api, syncDelay: const Duration(days: 1));
      await a.load();
      a.update((s) => (s['workouts'] as List).add(workout('w1', '2026-10-01', 'x', [[10, 10]])));
      await a.sync();
      await a.wipeLocal();
      expect(prefs.getString('k:state'), isNull);
      expect(api.doc.state, isNotNull, reason: 'the server copy survives a sign-out');
      await a.eraseAll();
      expect(api.doc.state, isNull);
    });
  });

group('the trainer-assigned workout', () {
  final cat = Catalogue.parse(
    '{"muscles":[{"id":"chest","name":"Chest"}],"bodyparts":[],"exercises":['
    '{"id":"25","n":"Barbell Bench Press","bp":"chest","eq":"barbell","w":{"chest":1}},'
    '{"id":"26","n":"Bench Press Stretch With Band","bp":"chest","eq":"band","w":{"chest":1}},'
    '{"id":"27","n":"Push Up","bp":"chest","eq":"body weight","w":{"chest":1}}]}',
  );
  test('a line finds its exercise by reference, exact name or best name match', () {
    expect(resolvePlanExercise(cat, {'exerciseId': 'og:27', 'name': 'zzz'}, null)?.id, '27');
    expect(resolvePlanExercise(cat, {'name': 'push up'}, null)?.id, '27');
    expect(resolvePlanExercise(cat, {'exerciseId': 'lib:bb-bench-press', 'name': 'Bench Press'}, null)?.id, '25', reason: 'shortest match wins');
    expect(resolvePlanExercise(cat, {'name': 'Underwater basket weaving'}, null), isNull);
    expect(resolvePlanExercise(cat, {'name': ''}, null), isNull);
  });
  test('reps ranges and words become a number', () {
    expect([repsFrom('8-10'), repsFrom('12'), repsFrom('AMRAP'), repsFrom(5), repsFrom('0'), repsFrom(null)], [8, 12, 10, 5, 10, 10]);
  });
  test('a plan day becomes planned entries with its sets and reps; unknown lines are reported, not guessed', () {
    final r = entriesFromPlanDay(defaultLog(), cat, {'exercises': [
      {'name': 'Barbell Bench Press', 'sets': 4, 'reps': '6-8'},
      {'name': 'Nonsense Move', 'sets': 3, 'reps': '10'},
    ]});
    expect(r.entries, hasLength(1));
    expect(r.entries.first['sets'], hasLength(4));
    expect(r.entries.first['sets'][0]['r'], 6);
    expect(r.skipped, ['Nonsense Move']);
  });
});


group('gym stats helpers', () {
  test('visits are counted per week, newest week last, outside the window ignored', () {
    final today = DateTime(2026, 10, 10); // a Saturday; the week starts Monday 5 Oct
    final v = [for (final d in ['2026-10-09', '2026-10-05', '2026-10-04', '2026-09-28', '2025-01-01', '2026-10-12']) Visit(d, '${d}T10:00:00Z', null, 'qr')];
    final w = visitsPerWeek(v, today, weeks: 4);
    expect(w, [0, 0, 2, 2], reason: '2 this week (9th, 5th), 2 last week (4th, 28 Sep) and the old / future ones ignored');
  });
  test('how far through its period a membership is', () {
    expect(periodElapsed('2026-10-01', '2026-10-10', DateTime(2026, 10, 5)), 0.5);
    expect(periodElapsed('2026-10-01', '2026-10-10', DateTime(2026, 9, 1)), 0.0);
    expect(periodElapsed('2026-10-01', '2026-10-10', DateTime(2027, 1, 1)), 1.0);
    expect(periodElapsed('bad', 'dates', DateTime(2026, 10, 5)), 0.0);
  });
});

group('when the server refuses the session', () {
  test('a 403 is shown as an error, the changes are kept, and the app is told to re-check the sign-in', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var told = 0;
    final s = MemberLogStore(key: 'k', prefs: prefs, api: _RefusingApi(), syncDelay: const Duration(days: 1))..onAuthProblem = () => told++;
    await s.load();
    s.update((x) => (x['workouts'] as List).add(workout('w1', '2026-10-01', 'x', [[10, 10]])));
    await s.sync();
    expect(s.status, SyncStatus.error);
    expect((s.lastError as ApiException).status, 403);
    expect(s.dirty, isTrue);
    expect(s.state['workouts'], hasLength(1));
    expect(told, 1);
  });
});

}

class _FakeApi implements LogApi {
  LogDoc doc = const LogDoc(0, null, null);
  bool offline = false;
  bool raceOnce = false;
  int? lastBaseRev;

  @override
  Future<LogDoc> fetchLog() async {
    if (offline) throw const LogOffline();
    return doc;
  }

  @override
  Future<LogDoc> pushLog(Json state, int baseRev) async {
    if (offline) throw const LogOffline();
    if (raceOnce) {
      raceOnce = false;
      doc = LogDoc(doc.rev + 1, 'x', {...defaultLog(), 'workouts': [workout('raced', '2026-10-03', 'x', [[3, 3]])]});
    }
    lastBaseRev = baseRev;
    if (baseRev != doc.rev) throw LogConflict(doc);
    return doc = LogDoc(doc.rev + 1, 'w${doc.rev + 1}', state);
  }

  @override
  Future<void> eraseLog() async => doc = const LogDoc(0, null, null);
}

class _RefusingApi implements LogApi {
  @override
  Future<LogDoc> fetchLog() async => throw ApiException(status: 403, code: 'FORBIDDEN', message: 'no');
  @override
  Future<LogDoc> pushLog(Json state, int baseRev) async => throw ApiException(status: 403, code: 'FORBIDDEN', message: 'no');
  @override
  Future<void> eraseLog() async {}
}
