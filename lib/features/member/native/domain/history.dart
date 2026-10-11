// History lookups and records, ported from openGym's lib/history.js and lib/onerm.js.
//
// Phase 1 covers rep, timed and cardio rows and per-side rows. Dumbbell "each/total" meaning
// conversions (lib/dumbbells.js) are not applied: loads are read as logged.
import 'onerm.dart';
import 'rows.dart';

typedef IsAssisted = bool Function(String id);

/// JS `Number(map[key])` with `undefined` (absent key) as NaN and `null` as 0.
double numAt(Json m, String key) => m.containsKey(key) ? jsNumber(m[key]) : double.nan;

bool entryExcluded(Object? w, Object? entry) =>
    asMap(w)['excludeFromProgression'] == true || asMap(entry)['noProg'] == true;

/// Which routine a saved entry was planned by.
String? entryRoutineId(Object? w, Object? en) {
  final e = asMap(en);
  final rid = e['rid'];
  if (rid is String && rid.isNotEmpty) return rid;
  final entries = asRows(asMap(w)['entries']);
  if (entries.any((x) => x['rid'] != null && x['rid'] != '')) return null;
  final wm = asMap(w);
  final ids = wm['routineIds'];
  final first = ids is List ? (ids.isEmpty ? null : ids.first) : ids;
  final v = first ?? wm['routineId'];
  return v is String ? v : null;
}

Json? _entryIn(Json w, String exId, String? rid) {
  for (final e in asRows(w['entries'])) {
    if (e['id'] == exId && (rid == null || rid.isEmpty || entryRoutineId(w, e) == rid)) return e;
  }
  return null;
}

class LastEntry {
  const LastEntry({required this.d, required this.sets, required this.target, this.rid, this.planned});
  final Object? d;
  final List<Json> sets;
  final Json? target;
  final String? rid;
  final Object? planned;

  Json toJson() => {
    'd': d, 'sets': sets, 'target': target,
    if (rid != null) 'rid': rid,
    if (planned != null && planned != false) 'planned': planned,
  };
}

LastEntry? _lastEntryIn(Json s, String exId, String? rid) {
  final workouts = asRows(s['workouts']);
  for (var i = workouts.length - 1; i >= 0; i--) {
    final w = workouts[i];
    final en = _entryIn(w, exId, rid);
    if (en == null) continue;
    if (entryExcluded(w, en)) continue;
    final done = [for (final x in asRows(en['sets'])) if (x['done'] == true && !isWarmupRow(x)) x];
    if (done.isNotEmpty) {
      final slot = entryRoutineId(w, en);
      return LastEntry(
        d: w['d'], sets: done, target: en['target'] is Map ? asMap(en['target']) : null,
        rid: slot, planned: en['planned'],
      );
    }
  }
  return null;
}

/// What you did last time for an exercise: its own routine's session first, then any.
LastEntry? lastEntryFor(Json s, String exId, [String? rid]) {
  if (rid != null && rid.isNotEmpty) {
    final own = _lastEntryIn(s, exId, rid);
    if (own != null) return own;
  }
  return _lastEntryIn(s, exId, null);
}

double betterWeight(bool assisted, double a, double b) => assisted ? (a < b ? a : b) : (a > b ? a : b);

/// The best load of one entry (the smallest on an assistance machine); 0 when none.
double bestWeightForEntry(Object? entry, {IsAssisted? isAssisted}) {
  final e = asMap(entry);
  final target = asMap(e['target'] ?? e);
  final sets = e['sets'];
  final workRows = sets is List ? [for (final s in asRows(sets)) if (phaseForSet(s) == 'work') s] : <Json>[];
  final repsRows = metricRowsForEntry(entry, 'reps');
  final completedRows = repsRows.isNotEmpty
      ? repsRows
      : [for (final s in workRows) if (hasCompletedWork(s) && !isWarmupRow(s)) s];
  final id = e['id'];
  final assisted = id is String && (isAssisted?.call(id) ?? false);
  var best = 0.0;
  var hasUsable = false;
  for (final set in completedRows) {
    final done = isSideSet(set)
        ? [for (final side in [asMap(asMap(set['sides'])['L']), asMap(asMap(set['sides'])['R'])]) if (side['done'] == true) side]
        : [set];
    for (final cs in done) {
      final weight = numAt(cs, 'w');
      if (!weight.isFinite) continue;
      if (assisted && !(weight > 0)) continue;
      best = hasUsable ? betterWeight(assisted, best, weight) : weight;
      hasUsable = true;
    }
  }
  if (hasUsable) return best;
  final parentMode = modeForSet(const <String, dynamic>{}, target);
  final hasNonReps = workRows.any((s) => modeForSet(s, target) != 'reps');
  final hasWarmup = sets is List && asRows(sets).any(isWarmupRow);
  final top = numAt(e, 'topW');
  if (parentMode == 'reps' && !hasNonReps && !hasWarmup && top.isFinite &&
      (best <= 0 || (assisted ? top > 0 && top < best : top > best))) {
    best = top;
  }
  return best;
}

class E1rmPoint {
  const E1rmPoint(this.t, this.d, this.y, this.w, this.r);
  final double t;
  final Object? d;
  final double y;
  final double w;
  final int r;
  Json toJson() => {'t': t, 'd': d, 'y': y, 'w': w, 'r': r};
}

List<E1rmPoint> e1rmSeries(Json s, String exId, {String formula = defaultFormula, IsAssisted? isAssisted}) {
  if (isAssisted?.call(exId) ?? false) return const [];
  final pts = <E1rmPoint>[];
  for (final w in asRows(s['workouts'])) {
    BestSet? best;
    for (final en in asRows(w['entries'])) {
      if (en['id'] != exId) continue;
      final c = bestSetOf(en, formula: formula, isAssisted: isAssisted);
      if (c != null && (best == null || c.est > best.est)) best = c;
    }
    if (best != null) pts.add(E1rmPoint(workoutAt(w), w['d'], best.est, best.w, best.r));
  }
  return pts;
}

class Record1RM {
  const Record1RM(this.est, this.w, this.r, this.d, this.t);
  final double est;
  final double w;
  final int r;
  final Object? d;
  final double t;
}

Record1RM? best1RM(Json s, String exId, {String formula = defaultFormula, IsAssisted? isAssisted}) {
  Record1RM? best;
  for (final p in e1rmSeries(s, exId, formula: formula, isAssisted: isAssisted)) {
    if (best == null || p.y > best.est) best = Record1RM(p.y, p.w, p.r, p.d, p.t);
  }
  return best;
}

class NewRecord {
  const NewRecord(this.est, this.w, this.r, this.prev);
  final double est;
  final double w;
  final int r;
  final double prev;
}

/// Did this entry beat every estimate before it? `s` must not yet contain the workout.
NewRecord? is1RMRecord(Json s, String exId, Object? entry, {String formula = defaultFormula, IsAssisted? isAssisted}) {
  final now = bestSetOf(entry, formula: formula, isAssisted: isAssisted);
  if (now == null) return null;
  final prev = best1RM(s, exId, formula: formula, isAssisted: isAssisted);
  return prev == null || now.est > prev.est ? NewRecord(now.est, now.w, now.r, prev?.est ?? 0) : null;
}

class HeaviestSet {
  const HeaviestSet(this.w, this.r, this.d);
  final double w;
  final int r;
  final Object? d;
}

/// The heaviest finished working set of an exercise in any workout (Settings → Workout → "Best set"): the
/// smallest positive load on an assistance machine, more reps winning a tie. null when it was never done.
HeaviestSet? heaviestSet(Json s, String exId, {IsAssisted? isAssisted}) {
  final assisted = isAssisted?.call(exId) ?? false;
  HeaviestSet? best;
  for (final w in asRows(s['workouts'])) {
    for (final e in asRows(w['entries'])) {
      if (e['id'] != exId || entryExcluded(w, e)) continue;
      for (final set in asRows(e['sets'])) {
        if (isWarmupRow(set)) continue;
        final rows = isSideSet(set)
            ? [for (final side in [asMap(asMap(set['sides'])['L']), asMap(asMap(set['sides'])['R'])]) side]
            : [set];
        for (final x in rows) {
          if (x['done'] != true) continue;
          final wt = numAt(x, 'w');
          final reps = numOrNull(x['r'])?.toInt() ?? 0;
          if (!wt.isFinite || wt <= 0) continue;
          final better = best == null || (assisted ? wt < best.w : wt > best.w) || (wt == best.w && reps > best.r);
          if (better) best = HeaviestSet(wt, reps, w['d']);
        }
      }
    }
  }
  return best;
}
