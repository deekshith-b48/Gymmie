// The weekly plan and simple progress counters (openGym: effectiveRoutineIds, lib/format.js week
// helpers). Routines are plain maps: {id, name, emoji, ex: [{id, sets, reps, weight}]}.
import 'catalogue.dart';
import 'rows.dart';
import 'session.dart';

String isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The routines planned for a date: a per-date choice first (`dayPlan`, or 'rest'), else the weekday's.
List<String> routineIdsOn(Json state, DateTime date) {
  final override = asMap(state['dayPlan'])[isoOf(date)];
  if (override == 'rest') return const [];
  if (override is String && override.isNotEmpty) return [override];
  final day = asMap(state['week'])['${date.weekday % 7}']; // JS getDay(): Sunday is 0
  if (day is List) return [for (final x in day) if (x is String && x.isNotEmpty) x];
  if (day is String && day.isNotEmpty) return [day];
  return const [];
}

Json? routineById(Json state, String id) {
  for (final r in asRows(state['routines'])) {
    if (r['id'] == id) return r;
  }
  return null;
}

List<Json> routinesOn(Json state, DateTime date) =>
    [for (final id in routineIdsOn(state, date)) ?routineById(state, id)];

/// The first day of the week containing [d] (`weekStart` as JS getDay(): 1 Monday, 0 Sunday).
DateTime weekStartOf(DateTime d, int weekStart) {
  final day = DateTime(d.year, d.month, d.day);
  final offset = (day.weekday % 7 - weekStart + 7) % 7;
  return day.subtract(Duration(days: offset));
}

int _weekStart(Json s) => (s['weekStart'] as num?)?.toInt() ?? 1;

Set<String> workoutDays(Json state) => {
  for (final w in asRows(state['workouts']))
    if ('${w['d']}'.length == 10) '${w['d']}',
};

int workoutsInWeek(Json state, DateTime anyDay) {
  final start = weekStartOf(anyDay, _weekStart(state));
  final days = {for (var i = 0; i < 7; i++) isoOf(start.add(Duration(days: i)))};
  return asRows(state['workouts']).where((w) => days.contains('${w['d']}')).length;
}

/// Consecutive weeks with at least one workout, counting back from this week (a week still in
/// progress without a workout does not break a streak that reaches last week).
int weekStreak(Json state, DateTime today) {
  final days = workoutDays(state);
  final ws = _weekStart(state);
  var start = weekStartOf(today, ws);
  bool has(DateTime s) => [for (var i = 0; i < 7; i++) isoOf(s.add(Duration(days: i)))].any(days.contains);
  var n = 0;
  if (!has(start)) start = start.subtract(const Duration(days: 7));
  while (has(start)) {
    n++;
    start = start.subtract(const Duration(days: 7));
  }
  return n;
}

Json newRoutine(String id, String name) => {'id': id, 'name': name, 'emoji': 'dumbbell', 'ex': <Object?>[]};

/// A session built from routines, in order; exercises the catalogue no longer knows are skipped.
List<Json> entriesFromRoutines(Json state, Catalogue cat, List<Json> routines) {
  final out = <Json>[];
  for (final r in routines) {
    for (final p in asRows(r['ex'])) {
      final ex = cat.find('${p['id']}', state['customEx']);
      if (ex == null) continue;
      out.add(buildEntry(
        ex, state,
        rid: '${r['id']}',
        sets: (numOrNull(p['sets']) ?? 3).toInt(),
        reps: (numOrNull(p['reps']) ?? 10).toInt(),
        planWeight: numOrNull(p['weight']),
        planned: true,
        repsFromLast: state['startFrom'] == 'last',
      ));
    }
  }
  return out;
}
