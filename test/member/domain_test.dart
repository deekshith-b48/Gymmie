// The Dart domain port must answer exactly what openGym's JavaScript answers.
// Fixtures: node member-app/scripts/gen-fixtures.mjs
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_book_app/features/member/native/domain/finish.dart';
import 'package:gym_book_app/features/member/native/domain/history.dart';
import 'package:gym_book_app/features/member/native/domain/onerm.dart';
import 'package:gym_book_app/features/member/native/domain/rows.dart';
import 'package:gym_book_app/features/member/native/domain/session.dart';

/// Deep equality where 50 and 50.0 are the same number (JSON has one number type).
bool same(Object? a, Object? b) {
  if (a is num && b is num) return (a - b).abs() < 1e-9 || (a.isNaN && b.isNaN);
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      final av = a[k], bv = b[k];
      // JS drops `undefined`; null and absent are equal here.
      if ((av == null) != (bv == null) && !(av == null && bv == null)) return false;
      if (!same(av, bv)) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  final g = jsonDecode(File('test/member/fixtures/golden.json').readAsStringSync()) as Map<String, dynamic>;
  final assistedId = g['assistedId'] as String?;
  bool assisted(String id) => id == assistedId;

  test('one-rep-max estimates match for every formula, weight, rep count and RIR', () {
    final rows = g['oneRm'] as List;
    expect(rows.length, greaterThan(2000));
    for (final r in rows) {
      final got = estimate1RM(r['w'], r['r'], r['formula'] as String, r['rir']);
      final want = r['out'] as num?;
      expect(got == null, want == null, reason: '${r['formula']} ${r['w']}x${r['r']} rir ${r['rir']}');
      if (got != null) expect((got - want!).abs() < 1e-9, isTrue, reason: '${r['formula']} ${r['w']}x${r['r']} rir ${r['rir']}: $got vs $want');
    }
  });

  test('best set and best weight of an entry match (side sets, warm-ups, assistance)', () {
    for (final e in g['entries'] as List) {
      final entry = asMap(e['entry']);
      final best = bestSetOf(entry, isAssisted: assisted);
      final want = e['best'] as Map?;
      expect(best == null, want == null, reason: jsonEncode(entry));
      if (best != null) {
        expect(same({'est': best.est, 'w': best.w, 'r': best.r}, want), isTrue, reason: jsonEncode(entry));
      }
      expect(same(bestWeightForEntry(entry, isAssisted: assisted), e['bestW']), isTrue, reason: jsonEncode(entry));
    }
  });

  test('a session that was left open ends at its last real tick', () {
    for (final s in g['sessionEnds'] as List) {
      final got = sessionEnd(s['active'], (s['now'] as num).toDouble());
      expect(same(got, s['out']), isTrue, reason: '${s['out']} vs $got');
    }
  });

  test('a finished workout is saved exactly the way openGym saves it', () {
    for (final c in g['completed'] as List) {
      final got = buildCompletedWorkout(
        asMap(jsonDecode(jsonEncode(c['active']))),
        end: (c['end'] as num).toDouble(),
        isAssisted: assisted,
      );
      expect(same(got, c['out']), isTrue, reason: 'got ${jsonEncode(got)}\nwant ${jsonEncode(c['out'])}');
    }
  });

  test('workout volume and set counts match', () {
    for (final v in g['volumes'] as List) {
      expect(same(workoutVolume(v['w']), v['vol']), isTrue, reason: '${workoutVolume(v['w'])} vs ${v['vol']}');
      expect(setsDone(v['w']), v['done']);
      expect(setUnitsTotal(asMap(v['w'])['entries']), v['total']);
    }
  });

  test('all-time best weight per exercise matches', () {
    final s = asMap((g['history'] as Map)['S']);
    for (final b in g['bestWeights'] as List) {
      expect(same(bestWeightFor(s, b['id'] as String), b['out']), isTrue, reason: '${b['id']}');
    }
  });

  group('history', () {
    final h = g['history'] as Map<String, dynamic>;
    final s = asMap(h['S']);
    test('last time for an exercise, with and without its routine', () {
      for (final l in h['last'] as List) {
        final got = lastEntryFor(s, l['id'] as String, l['rid'] as String?);
        final want = l['out'];
        expect(got == null, want == null, reason: '${l['id']} ${l['rid']}');
        if (got != null) expect(same(got.toJson(), want), isTrue, reason: '${jsonEncode(got.toJson())} vs ${jsonEncode(want)}');
      }
    });
    test('strength curve, all-time best and new-record detection', () {
      for (final x in h['series'] as List) {
        final got = [for (final p in e1rmSeries(s, x['id'] as String)) p.toJson()];
        expect(same(got, x['out']), isTrue, reason: '${jsonEncode(got)} vs ${jsonEncode(x['out'])}');
      }
      for (final x in h['best'] as List) {
        final got = best1RM(s, x['id'] as String);
        final want = x['out'] as Map?;
        expect(got == null, want == null);
        if (got != null) expect(same({'est': got.est, 'w': got.w, 'r': got.r, 'd': got.d, 't': got.t}, want), isTrue);
      }
      for (final x in h['record'] as List) {
        final got = is1RMRecord(s, x['id'] as String, x['entry']);
        final want = x['out'] as Map?;
        expect(got == null, want == null);
        if (got != null) expect(same({'est': got.est, 'w': got.w, 'r': got.r, 'prev': got.prev}, want), isTrue);
      }
    });
  });
}
