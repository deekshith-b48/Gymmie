// The settings-related domain code must answer what openGym's JavaScript answers (accent colours, unit
// conversion, the Activity heatmap, effort stepping, equipment). Fixtures: node member-app/scripts/gen-fixtures.mjs
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/features/member/native/domain/accent.dart';
import 'package:gym_book_app/features/member/native/domain/activity.dart';
import 'package:gym_book_app/features/member/native/domain/catalogue.dart';
import 'package:gym_book_app/features/member/native/domain/equipment.dart';
import 'package:gym_book_app/features/member/native/domain/rows.dart';
import 'package:gym_book_app/features/member/native/domain/settings.dart';
import 'package:gym_book_app/features/member/native/domain/starter.dart';
import 'package:gym_book_app/features/member/native/domain/units.dart';

bool same(Object? a, Object? b) {
  if (a is num && b is num) return (a - b).abs() < 1e-6 || (a.isNaN && b.isNaN);
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      final av = a[k], bv = b[k];
      if (av == null && bv == null) continue;
      if ((av == null) != (bv == null)) return false;
      if (!same(av, bv)) return false;
    }
    return true;
  }
  return a == b;
}

String? why(Object? a, Object? b, [String path = '']) {
  if (a is num && b is num) return (a - b).abs() < 1e-6 ? null : '$path: $a vs $b';
  if (a is List && b is List) {
    if (a.length != b.length) return '$path: length ${a.length} vs ${b.length}';
    for (var i = 0; i < a.length; i++) {
      final w = why(a[i], b[i], '$path[$i]');
      if (w != null) return w;
    }
    return null;
  }
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      if (a[k] == null && b[k] == null) continue;
      final w = why(a[k], b[k], '$path.$k');
      if (w != null) return w;
    }
    return null;
  }
  return a == b ? null : '$path: $a vs $b';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final g = jsonDecode(File('test/member/fixtures/golden.json').readAsStringSync()) as Map<String, dynamic>;

  group('accent colours', () {
    test('"made readable" and the text colour on it agree with openGym on both themes', () {
      final rows = g['accents'] as List;
      expect(rows.length, greaterThan(50));
      for (final r in rows) {
        final hex = r['hex'] as String;
        expect(isGrey(hex), r['grey'], reason: hex);
        expect(readableIn(hex, 'dark'), r['dark'], reason: 'dark $hex');
        expect(readableIn(hex, 'light'), r['light'], reason: 'light $hex');
        final dark = readableIn(hex, 'dark'), light = readableIn(hex, 'light');
        expect([inkOnBoth(dark, mix(dark, '#000000', 0.25)), inkOnBoth(light, mix(light, '#000000', 0.25))], r['ink'], reason: hex);
        expect((contrast(hex, '#1c1c1e') - (r['contrast'] as num)).abs() < 1e-9, isTrue, reason: hex);
      }
    });

    test('a stored value is never trusted: only a plain six-digit hex is a colour', () {
      expect(cleanHex('#FF8800'), '#ff8800');
      for (final bad in ['#abc', 'red', 'url(x)', 12, null, '#12345678', '#gggggg', '']) {
        expect(cleanHex(bad), isNull, reason: '$bad');
      }
      expect(accentKeyOf({'accent': 'sky'}), 'sky');
      expect(accentKeyOf({'accent': 'custom', 'accentCustom': '#336699'}), 'custom');
      expect(accentKeyOf({'accent': 'custom', 'accentCustom': 'nope'}), 'lime', reason: 'no usable colour: the default');
      expect(accentKeyOf({'accent': 'neon'}), 'lime');
      expect(accentKeyOf(const {}), 'lime');
    });
  });

  final cat = Catalogue.parse(File('assets/member/exercises.json').readAsStringSync());

  group('kg and lb', () {
    test('every weight in a whole log converts the way openGym converts it, both ways', () {
      for (final c in g['unitCases'] as List) {
        final got = convertStateUnit(asMap(c['log']), c['to'] as String, equipmentOf: (id) => cat.byId(id)?.equipment);
        final w = why(got, c['out']);
        expect(w, isNull, reason: '${c['from']} → ${c['to']}: $w');
      }
    });

    test('single weights and body weights round to what a gym can load', () {
      for (final r in g['weights'] as List) {
        final v = r['v'] as num;
        expect(same(convertWeight(v, 'kg', 'lb'), r['lb']), isTrue, reason: 'kg→lb $v');
        expect(same(convertWeight(v, 'lb', 'kg'), r['kg']), isTrue, reason: 'lb→kg $v');
        expect(same(convertBodyWeight(v, 'kg', 'lb'), r['bwLb']), isTrue, reason: 'bw kg→lb $v');
        expect(same(convertBodyWeight(v, 'lb', 'kg'), r['bwKg']), isTrue, reason: 'bw lb→kg $v');
      }
    });

    test('the input is never changed, and the same unit is a no-op', () {
      final log = {'unit': 'kg', 'bodyweight': [{'d': '2026-01-01', 'w': 80}]};
      final out = convertStateUnit(log, 'lb');
      expect((log['bodyweight'] as List).first['w'], 80);
      expect(out['unit'], 'lb');
      expect(convertStateUnit(log, 'kg')['bodyweight'], log['bodyweight']);
    });
  });

  group('Activity heatmap', () {
    test('a workout\'s day and duration are read exactly as openGym reads them', () {
      for (final h in g['heat'] as List) {
        final ws = asRows(h['workouts']);
        final days = h['days'] as List;
        for (var i = 0; i < ws.length; i++) {
          expect(workoutDay(ws[i]), days[i]['day'], reason: jsonEncode(ws[i]));
          expect((workoutDuration(ws[i]) - (days[i]['ms'] as num)).abs() < 1e-6, isTrue, reason: jsonEncode(ws[i]));
        }
      }
    });

    test('the grid, its five shades, the month labels and the weekday labels match, for both week starts and both metrics', () {
      for (final h in g['heat'] as List) {
        final p = (h['today'] as String).split('-').map(int.parse).toList();
        final data = buildHeatmap({'workouts': h['workouts']}, today: DateTime(p[0], p[1], p[2], 12), metric: h['metric'] as String, weekStart: h['weekStart'] as int);
        final cols = h['cols'] as List;
        expect(data.columns.length, 53);
        for (var c = 0; c < cols.length; c++) {
          for (var d = 0; d < 7; d++) {
            final want = cols[c][d] as Map<String, dynamic>;
            final got = data.columns[c][d];
            expect(got.iso, want['iso'], reason: 'column $c row $d');
            expect(got.level, want['level'], reason: '${want['iso']} (${h['metric']}, week from ${h['weekStart']})');
            expect(got.future, want['future'], reason: want['iso'] as String);
          }
        }
        expect(data.months, (h['months'] as List).cast<String>());
        expect(data.dayLabels, (h['dayLabels'] as List).cast<String?>());
        // some day was shaded in every case (the fixtures are not all empty)
        expect(data.columns.expand((c) => c).any((c) => c.level == 4), isTrue);
      }
    });

    test('an empty log is an empty grid; today is marked and the future is flagged', () {
      final data = buildHeatmap({'workouts': <Object?>[]}, today: DateTime(2026, 10, 10, 15), metric: 'time', weekStart: 1);
      expect(data.columns.expand((c) => c).every((c) => c.level == 0), isTrue);
      final cells = data.columns.expand((c) => c).toList();
      expect(cells.where((c) => c.isToday).map((c) => c.iso), ['2026-10-10']);
      expect(cells.where((c) => c.future).first.iso, '2026-10-11');
      expect(cells.last.iso, '2026-10-11', reason: 'the grid ends on the last day of this week (Sunday)');
    });
  });

  group('effort and equipment', () {
    test('stepping an effort field and capping a typed one match openGym', () {
      for (final r in g['efforts'] as List) {
        if (r.containsKey('cap')) {
          expect(capEffort(r['kind'] as String, (r['cap'] as num).toDouble()), (r['out'] as num).toDouble(), reason: '$r');
        } else {
          final got = stepEffort(r['kind'] as String, (r['cur'] as num?)?.toDouble(), r['dir'] as int);
          expect(got, (r['out'] as num?)?.toDouble(), reason: '$r');
        }
      }
    });

    test('setEffort keeps one scale per set', () {
      final s = <String, dynamic>{'rir': 2};
      setEffort(s, 'rpe', 8);
      expect(s, {'rpe': 8.0});
      setEffort(s, 'rpe', null);
      expect(s, isEmpty);
    });

    test('the equipment checklist, the accessories an exercise needs and what a profile allows match openGym', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final cat = Catalogue.parse(File('assets/member/exercises.json').readAsStringSync());
      final all = allEquipment(cat.exercises);
      expect(all, (g['allEquipment'] as List).cast<String>());
      final lists = [for (final l in g['eqLists'] as List) (l as List).cast<String>()];
      for (final r in g['equip'] as List) {
        final ex = cat.byId(r['id'] as String)!;
        expect(accessoriesOf(ex), (r['acc'] as List).cast<String>(), reason: ex.name);
        for (var i = 0; i < lists.length; i++) {
          expect(eqAvailable(lists[i], ex, all), (r['avail'] as List)[i], reason: '${ex.name} with ${lists[i]}');
        }
      }
    });
  });

  group('starter plans', () {
    test('every exercise a starter plan names exists in the exercise library', () {
      final cat = Catalogue.parse(File('assets/member/exercises.json').readAsStringSync());
      for (final id in starterExerciseIds()) {
        expect(cat.byId(id), isNotNull, reason: 'exercise $id');
      }
    });

    test('loading a plan adds its routines on its weekdays, touches nothing else, and is idempotent', () {
      final log = <String, dynamic>{
        'routines': [{'id': 'mine', 'name': 'My routine', 'ex': <Object?>[]}],
        'week': {'1': ['mine'], '6': ['mine']},
      };
      expect(loadStarterPlan(log, 'ppl', newId: (i) => 'p$i'), isTrue);
      final routines = asRows(log['routines']);
      expect(routines.map((r) => r['name']), ['My routine', 'Push Day', 'Pull Day', 'Leg Day']);
      expect(asMap(log['week'])['1'], ['p0'], reason: 'Monday now holds Push Day');
      expect(asMap(log['week'])['3'], ['p1']);
      expect(asMap(log['week'])['5'], ['p2']);
      expect(asMap(log['week'])['6'], ['mine'], reason: 'a weekday the plan does not use is left alone');
      loadStarterPlan(log, 'ppl', newId: (i) => 'q$i');
      expect(asRows(log['routines']).length, 4, reason: 'the same plan reuses its routines');
      expect(asMap(log['week'])['1'], ['p0']);
      expect(loadStarterPlan(log, 'nope'), isFalse);
      expect(asRows(log['routines']).length, 4);
    });
  });
}
