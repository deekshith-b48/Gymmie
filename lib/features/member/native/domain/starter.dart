// The starter-plan catalog and "Load starter plan", ported from openGym's lib/starter.js and
// sheets.jsx loadStarterPlan. Routines are [key, name, emoji, [[exerciseId, sets, reps], ...]]; the key is
// what a plan's schedule points at. Names stay canonical English: they become ordinary routines.
import 'rows.dart';

typedef _R = (String key, String name, String emoji, List<(String id, int sets, int reps)> ex);

const List<_R> _ppl = [
  ('push', 'Push Day', 'barbell', [('0025', 4, 8), ('0047', 3, 10), ('0426', 3, 10), ('0334', 3, 12), ('0241', 3, 12), ('0251', 3, 10)]),
  ('pull', 'Pull Day', 'pullup', [('2330', 4, 10), ('0027', 4, 8), ('1323', 3, 10), ('0031', 3, 10), ('0313', 3, 12)]),
  ('legs', 'Leg Day', 'legs', [('0043', 4, 8), ('0085', 3, 10), ('0739', 3, 12), ('0585', 3, 12), ('0586', 3, 12), ('0605', 4, 15)]),
];

const List<_R> _upperLower = [
  ('upper-a', 'Upper A', 'barbell', [('0025', 3, 8), ('2330', 3, 10), ('0047', 2, 10), ('1323', 2, 10), ('0334', 2, 12), ('0241', 2, 12), ('0031', 2, 12)]),
  ('lower-a', 'Lower A', 'legs', [('0043', 3, 8), ('0085', 3, 8), ('0739', 2, 10), ('0586', 2, 12), ('0605', 3, 15)]),
  ('upper-b', 'Upper B', 'barbell', [('0047', 3, 8), ('0027', 3, 8), ('0426', 2, 10), ('2330', 2, 10), ('0334', 2, 12), ('0241', 2, 12), ('0313', 2, 12)]),
  ('lower-b', 'Lower B', 'legs', [('0739', 3, 10), ('0085', 2, 10), ('0585', 2, 12), ('0586', 3, 12), ('0605', 3, 15)]),
];

const List<_R> _fullBody = [
  ('fb-a', 'Full Body A', 'figureStrength', [('0043', 3, 8), ('0025', 3, 8), ('2330', 3, 10), ('0586', 3, 12), ('0334', 2, 12), ('0031', 2, 12)]),
  ('fb-b', 'Full Body B', 'figureStrength', [('0085', 3, 8), ('0047', 3, 10), ('1323', 3, 10), ('0585', 3, 12), ('0334', 2, 12), ('0241', 2, 12)]),
  ('fb-c', 'Full Body C', 'figureStrength', [('0739', 3, 10), ('0025', 2, 10), ('0027', 3, 10), ('0426', 2, 10), ('0586', 3, 12), ('0605', 3, 15)]),
];

const List<_R> _fiveByFive = [
  ('5x5-a', '5×5 A', 'barbell', [('0043', 5, 5), ('0025', 5, 5), ('0027', 5, 5)]),
  ('5x5-b', '5×5 B', 'barbell', [('0085', 5, 5), ('0426', 5, 5), ('2330', 5, 5)]),
  ('5x5-c', '5×5 C', 'barbell', [('0739', 5, 5), ('0047', 5, 5), ('1323', 5, 5)]),
];

class StarterPlan {
  const StarterPlan(this.id, this.name, this.about, this._routines, this._schedule);
  final String id;
  final String name;
  final String about;
  final List<_R> _routines;

  /// (weekday as a JS getDay() index, routine key): 1 is Monday. Fixed weeks only.
  final List<(int day, String key)> _schedule;

  List<int> get days => [for (final s in _schedule) s.$1];
  int get daysPerWeek => _schedule.length;
}

const starterPlans = <StarterPlan>[
  StarterPlan('ppl', 'Push / Pull / Legs', 'Push, pull and legs each get their own day.', _ppl, [(1, 'push'), (3, 'pull'), (5, 'legs')]),
  StarterPlan('upper-lower', 'Upper / Lower', 'Upper body twice, lower body twice.', _upperLower, [(1, 'upper-a'), (2, 'lower-a'), (4, 'upper-b'), (5, 'lower-b')]),
  StarterPlan('full-body', 'Full Body', 'Three sessions, the whole body each time.', _fullBody, [(1, 'fb-a'), (3, 'fb-b'), (5, 'fb-c')]),
  StarterPlan('5x5', '5×5', 'Five sets of five on the main barbell lifts.', _fiveByFive, [(1, '5x5-a'), (3, '5x5-b'), (5, '5x5-c')]),
];

StarterPlan? starterPlanById(String id) {
  for (final p in starterPlans) {
    if (p.id == id) return p;
  }
  return null;
}

/// Every exercise id the catalogue of plans uses (for tests: each must exist in the exercise library).
Set<String> starterExerciseIds() => {
  for (final p in starterPlans) for (final r in p._routines) for (final e in r.$4) e.$1,
};

/// Adds the plan's routines (reusing one the member already has under the same name and exercises) and puts
/// them on the plan's weekdays. Existing routines are never touched and only the weekdays the plan asks for
/// change. Returns false for an unknown plan, changing nothing. [newId] makes routine ids.
bool loadStarterPlan(Json state, String planId, {String Function(int index)? newId}) {
  final plan = starterPlanById(planId);
  if (plan == null) return false;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  String mint(int i) => newId != null ? newId(i) : 'r$stamp$i';
  final routines = (state['routines'] is List ? state['routines'] as List : (state['routines'] = <Object?>[]));
  final week = state['week'] is Map ? state['week'] as Map : (state['week'] = <String, dynamic>{});
  bool sameLift(Json have, List<(String, int, int)> ex) {
    final a = asRows(have['ex']);
    return a.length == ex.length && [for (var i = 0; i < a.length; i++) a[i]['id'] == ex[i].$1].every((x) => x);
  }

  final idOf = <String, String>{};
  for (var i = 0; i < plan._routines.length; i++) {
    final (key, name, emoji, ex) = plan._routines[i];
    Json? have;
    for (final r in asRows(routines)) {
      if (r['name'] == name && sameLift(r, ex)) {
        have = r;
        break;
      }
    }
    if (have != null) {
      idOf[key] = '${have['id']}';
    } else {
      final id = mint(i);
      routines.add({'id': id, 'name': name, 'emoji': emoji, 'ex': [for (final e in ex) {'id': e.$1, 'sets': e.$2, 'reps': e.$3, 'weight': 0}]});
      idOf[key] = id;
    }
  }
  for (final (day, key) in plan._schedule) {
    final id = idOf[key];
    if (id != null) week['$day'] = [id];
  }
  return true;
}
