// Turning the workout plan a trainer assigned (Gymmie's plan document) into a session in the member's log.
import 'catalogue.dart';
import 'rows.dart';
import 'session.dart';

/// The catalogue exercise a plan line means: its `og:<id>` reference, else the exact name, else the best
/// name match. Null when nothing fits (the line is then skipped rather than guessed).
Exercise? resolvePlanExercise(Catalogue cat, Json item, Object? customEx) {
  final ref = '${item['exerciseId'] ?? ''}';
  if (ref.startsWith('og:')) {
    final e = cat.find(ref.substring(3), customEx);
    if (e != null) return e;
  }
  final name = '${item['name'] ?? ''}'.trim().toLowerCase();
  if (name.isEmpty) return null;
  final all = cat.withCustom(customEx);
  for (final e in all) {
    if (e.name.toLowerCase() == name) return e;
  }
  final hits = searchExercises(all, name);
  if (hits.isEmpty) return null;
  // shortest name first: "Bench Press" beats "Bench Press Stretch With Band"
  hits.sort((a, b) => a.name.length.compareTo(b.name.length));
  return hits.first;
}

/// "8-10" → 8, "12" → 12, "AMRAP" → 10.
int repsFrom(Object? v, [int fallback = 10]) {
  final m = RegExp(r'\d+').firstMatch('$v');
  final n = m == null ? null : int.tryParse(m.group(0)!);
  return n == null || n < 1 ? fallback : n.clamp(1, 100);
}

class PlanDayEntries {
  const PlanDayEntries(this.entries, this.skipped);
  final List<Json> entries;
  final List<String> skipped;
}

PlanDayEntries entriesFromPlanDay(Json state, Catalogue cat, Json day) {
  final entries = <Json>[];
  final skipped = <String>[];
  for (final item in asRows(day['exercises'])) {
    final ex = resolvePlanExercise(cat, item, state['customEx']);
    if (ex == null) {
      skipped.add('${item['name']}');
      continue;
    }
    entries.add(buildEntry(
      ex, state,
      sets: ((numOrNull(item['sets']) ?? 3).toInt()).clamp(1, 20),
      reps: repsFrom(item['reps']),
      planned: true,
    ));
  }
  return PlanDayEntries(entries, skipped);
}
