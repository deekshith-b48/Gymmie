// Building, editing and finishing a workout session. The finishing rules are ports of openGym's
// sheets.jsx doFinishWorkout / lib/history.js; the starting rows are a Phase 1 simplification of
// buildSets: reproduce what you did last time (or the plan), with no warm-up ramp, pyramids,
// dumbbell meaning or automatic progression yet.
import 'catalogue.dart';
import 'finish.dart';
import 'history.dart';
import 'onerm.dart' show defaultFormula;
import 'rows.dart';

// ---- counting ---------------------------------------------------------------------------------------------------

int setUnits(Object? s) => isSideSet(s) ? 2 : 1;

int doneUnits(Object? s) {
  if (isSideSet(s)) {
    final sides = asMap(asMap(s)['sides']);
    return (asMap(sides['L'])['done'] == true ? 1 : 0) + (asMap(sides['R'])['done'] == true ? 1 : 0);
  }
  return asMap(s)['done'] == true ? 1 : 0;
}

int setsDone(Object? workout) => [
  for (final e in asRows(asMap(workout)['entries'])) for (final s in asRows(e['sets'])) doneUnits(s),
].fold(0, (a, b) => a + b);

int setUnitsTotal(Object? entries) => [
  for (final e in asRows(entries)) for (final s in asRows(e['sets'])) setUnits(s),
].fold(0, (a, b) => a + b);

double _completedVolume(Json s) {
  if (isSideSet(s)) {
    final sides = asMap(s['sides']);
    return _completedVolume(asMap(sides['L'])) + _completedVolume(asMap(sides['R']));
  }
  if (s['done'] != true) return 0;
  return jsNumber(s['w']).nanTo0 * jsNumber(s['r']).nanTo0;
}

extension on double {
  double get nanTo0 => isNaN ? 0 : this;
}

/// Total completed load × reps, warm-ups excluded.
double workoutVolume(Object? w) {
  var v = 0.0;
  for (final e in asRows(asMap(w)['entries'])) {
    for (final s in asRows(e['sets'])) {
      if (!isWarmupRow(s)) v += _completedVolume(s);
    }
  }
  return v;
}

/// Best load an exercise ever reached across history (the smallest on an assistance machine).
double bestWeightFor(Json state, String exId, {IsAssisted? isAssisted}) {
  var best = 0.0;
  final assisted = isAssisted?.call(exId) ?? false;
  for (final w in asRows(state['workouts'])) {
    for (final e in asRows(w['entries'])) {
      if (e['id'] != exId) continue;
      final b = bestWeightForEntry(e, isAssisted: isAssisted);
      if (b > 0) best = best > 0 ? betterWeight(assisted, best, b) : b;
    }
  }
  return best;
}

bool beatsWeight(bool assisted, double w, double prev) => w > 0 && (prev <= 0 || (assisted ? w < prev : w > prev));

// ---- starting ---------------------------------------------------------------------------------------------------

Json _row(String mode, {num w = 0, num r = 10, num min = 20, num speed = 8, num sec = 45}) => switch (mode) {
  'cardio' => {'min': min, 'speed': speed, 'done': false},
  'time' => {'sec': sec, 'w': w, 'done': false},
  _ => {'w': w, 'r': r, 'done': false},
};

/// One exercise's entry for a new session.
///
/// Freestyle ([planned] false) reproduces what you did last time, set for set. A planned exercise
/// (from a routine) opens with the routine's own set count and reps, and history only decides the
/// weight, the way openGym's "planned sessions start from" does. With no history the weight is the
/// last known working weight, then the routine's own.
Json buildEntry(
  Exercise ex,
  Json state, {
  String? rid,
  int sets = 3,
  int reps = 10,
  num? planWeight,
  bool planned = false,
  bool repsFromLast = false,
}) {
  final mode = ex.mode;
  final last = lastEntryFor(state, ex.id, rid);
  final known = jsNumber(asMap(asMap(state['exWeights'])[ex.id])['w']);
  final fallbackW = known.isFinite && known > 0 ? known : (planWeight ?? 0);
  final rows = <Json>[];
  final n = planned ? (sets < 1 ? 1 : sets) : (last != null && last.sets.isNotEmpty ? last.sets.length : sets);
  for (var i = 0; i < n; i++) {
    final prev = last == null || last.sets.isEmpty ? null : last.sets[i < last.sets.length ? i : last.sets.length - 1];
    rows.add(switch (mode) {
      'cardio' => _row('cardio', min: numOrNull(prev?['min']) ?? 20, speed: numOrNull(prev?['speed']) ?? 8),
      _ => _row(
        'reps',
        w: numOrNull(prev?['w']) ?? fallbackW,
        r: planned && !repsFromLast ? reps : (numOrNull(prev?['r']) ?? reps),
      ),
    });
  }
  return {
    'id': ex.id,
    'target': {'mode': mode, 'sets': rows.length, 'reps': reps, 'weight': rows.isEmpty ? 0 : (rows.first['w'] ?? 0)},
    'sets': rows,
    if (rid != null && rid.isNotEmpty) 'rid': rid,
  };
}

Json newSession({
  required String id,
  required String day,
  required int now,
  required String name,
  required List<Json> entries,
  List<String> routineIds = const [],
  Object? bw,
}) => {
  'id': id, 'd': day, 'start': now, 'routineIds': routineIds, 'name': name,
  'bw': bw, 'cur': 0, 'entries': entries, 'workoutView': 'cards',
};

// ---- editing ----------------------------------------------------------------------------------------------------

/// Ticks a set done (stamping when) or undoes it.
void toggleDone(Json row, int now) {
  final done = row['done'] != true;
  row['done'] = done;
  if (done) {
    row['at'] = now;
  } else {
    row.remove('at');
  }
}

/// "One more like this": a copy of the last row, unticked.
void addSet(Json entry) {
  final sets = (entry['sets'] as List).cast<Json>();
  if (sets.isEmpty) return;
  final copy = Map<String, dynamic>.from(sets.last)..remove('done')..remove('at')..remove('planSec')..remove('weightOrigin');
  copy['done'] = false;
  sets.add(copy);
}

/// Removes set [i]; an entry is never emptied.
bool removeSet(Json entry, int i) {
  final sets = (entry['sets'] as List).cast<Json>();
  if (sets.length <= 1 || i < 0 || i >= sets.length) return false;
  sets.removeAt(i);
  return true;
}

// ---- finishing --------------------------------------------------------------------------------------------------

class FinishResult {
  const FinishResult(this.workout, this.weightRecords, this.e1rmRecords);
  final Json workout;
  final List<String> weightRecords;
  final List<NewRecord> e1rmRecords;
}

/// Turns the active session into a saved workout and updates [state] (history, known weights).
/// The caller clears `active`. Mirrors openGym's doFinishWorkout for a live (not back-dated) session.
FinishResult finishSession(Json state, Json active, {required int now, IsAssisted? isAssisted, String formula = defaultFormula}) {
  final prs = <String>[];
  final e1 = <NewRecord>[];
  for (final e in asRows(active['entries'])) {
    final id = '${e['id']}';
    final loads = [
      for (final s in asRows(e['sets']))
        if (s['done'] == true && !isWarmupRow(s) && jsNumber(s['w']) > 0) jsNumber(s['w']),
    ];
    final assisted = isAssisted?.call(id) ?? false;
    final mx = loads.isEmpty ? 0.0 : loads.reduce((a, b) => betterWeight(assisted, a, b));
    if (beatsWeight(assisted, mx, bestWeightFor(state, id, isAssisted: isAssisted))) prs.add(id);
    final rec = is1RMRecord(state, id, e, formula: formula, isAssisted: isAssisted);
    if (rec != null && !prs.contains(id)) e1.add(rec);
  }
  final w = buildCompletedWorkout(
    active,
    end: sessionEnd(active, now.toDouble()),
    prs: prs,
    isAssisted: isAssisted,
  );
  w['vol'] = workoutVolume(w);
  final weights = asMap(state['exWeights']);
  for (final e in asRows(w['entries'])) {
    final id = '${e['id']}';
    final mx = bestWeightForEntry(e, isAssisted: isAssisted);
    final assisted = isAssisted?.call(id) ?? false;
    if (mx > 0 && beatsWeight(assisted, mx, jsNumber(asMap(weights[id])['w']).nanTo0)) {
      weights[id] = {'w': mx, 'd': w['d']};
    }
  }
  state['exWeights'] = weights;
  (state['workouts'] as List? ?? (state['workouts'] = <Object?>[])).add(w);
  return FinishResult(w, prs, e1);
}
