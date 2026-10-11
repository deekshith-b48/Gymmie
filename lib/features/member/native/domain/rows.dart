// Row, mode and phase rules of a logged set, ported from openGym's lib/workout-model.js and the
// matching parts of lib/history.js. Sets stay plain JSON maps (never lossy typed copies) so that a
// log written by openGym survives a round trip through this app unchanged.
typedef Json = Map<String, dynamic>;

const modes = ['reps', 'time', 'cardio'];

Json asMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> asRows(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) e.cast<String, dynamic>()] : const [];
num? numOrNull(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final n = num.tryParse(v.trim());
    return n != null && n.isFinite ? n : null;
  }
  return null;
}

/// JS `Number(x)`: a missing value is 0 for arithmetic and NaN for finiteness checks.
double jsNumber(Object? v) {
  if (v == null) return 0;
  if (v is bool) return v ? 1 : 0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? double.nan;
  }
  return double.nan;
}

String _phase(Object? value, [String fallback = 'work']) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (token == 'warmup' || token == 'warm-up' || token == 'warm_up') return 'warmup';
  if (token == 'work') return 'work';
  return fallback == 'warmup' ? 'warmup' : 'work';
}

String phaseForSet(Object? set) {
  final s = asMap(set);
  final p = s['phase'];
  if (p != null && p != '') return _phase(p);
  return s['warmup'] == true ? 'warmup' : 'work';
}

bool isWarmupRow(Object? set) => phaseForSet(set) == 'warmup';

bool isSideSet(Object? set) {
  final s = asMap(set);
  final sides = s['sides'];
  return sides is Map && sides['L'] != null && sides['R'] != null && sides['L'] is! bool;
}

bool hasCompletedWork(Object? set) {
  if (isSideSet(set)) {
    final sides = asMap(asMap(set)['sides']);
    return asMap(sides['L'])['done'] == true || asMap(sides['R'])['done'] == true;
  }
  return asMap(set)['done'] == true;
}

String normalizeMode(Object? value, [String fallback = 'reps']) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (modes.contains(token)) return token;
  return modes.contains(fallback) ? fallback : 'reps';
}

String? _modeFromUnit(Object? value) {
  final token = value is String ? value.trim().toLowerCase() : '';
  if (const ['rep', 'reps', 'repetition', 'repetitions'].contains(token)) return 'reps';
  if (const ['sec', 'secs', 'second', 'seconds'].contains(token)) return 'time';
  if (const ['min', 'mins', 'minute', 'minutes'].contains(token)) return 'cardio';
  return null;
}

String? _explicitMode(Object? source) {
  final s = asMap(source);
  final v = s['mode'];
  final token = v is String ? v.trim().toLowerCase() : '';
  return modes.contains(token) ? token : _modeFromUnit(s['unit']);
}

String? _inferredMode(Object? source) {
  final v = asMap(source);
  final e = _explicitMode(v);
  if (e != null) return e;
  if ('${v['mode'] ?? ''}'.trim().toLowerCase() == 'amrap') return 'reps';
  if (v['min'] != null || v['speed'] != null) return 'cardio';
  if (v['sec'] != null || v['seconds'] != null || v['durationSec'] != null) return 'time';
  if (v['r'] != null || v['reps'] != null || v['actualReps'] != null) return 'reps';
  return null;
}

String modeForSet(Object? set, [Object? target]) =>
    _explicitMode(set) ?? _inferredMode(target ?? const {}) ?? _inferredMode(set) ?? 'reps';

/// The mode of an entry; `null` when its work rows mix modes.
String? modeForEntry(Object? entry, [String? fallback]) {
  final source = asMap(entry);
  final target = asMap(source['target'] ?? source);
  final sets = asRows(source['sets']);
  final work = sets.where((s) => !isWarmupRow(s)).toList();
  final observed = work.isNotEmpty ? work : sets;
  final seen = <String>{for (final s in observed) modeForSet(s, target)};
  if (seen.length > 1) return null;
  if (seen.length == 1) return seen.first;
  final t = _inferredMode(target);
  if (t != null) return t;
  return fallback == null ? modeForSet(source, target) : normalizeMode(fallback);
}

List<Json> _workRowsForMode(Object? entry, String mode) {
  final source = asMap(entry);
  final target = asMap(source['target'] ?? source);
  final expected = normalizeMode(mode);
  return [
    for (final s in asRows(source['sets']))
      if (phaseForSet(s) == 'work' && modeForSet(s, target) == expected) s,
  ];
}

List<Json> _completedRowsForMode(Object? entry, String mode) => [
  for (final s in _workRowsForMode(entry, mode))
    if (hasCompletedWork(s) && !isWarmupRow(s)) s,
];

String? metricModeForEntry(Object? entry) {
  for (final m in modes) {
    if (_completedRowsForMode(entry, m).isNotEmpty) return m;
  }
  return modeForEntry(entry);
}

/// Completed work rows that carry the entry's metric (reps rows win over timed/cardio rows).
List<Json> metricRowsForEntry(Object? entry, [String? mode]) {
  final requested = mode?.trim().toLowerCase() ?? '';
  final resolved = modes.contains(requested) ? requested : metricModeForEntry(entry);
  return resolved == null ? const [] : _completedRowsForMode(entry, resolved);
}

/// Epoch ms a workout happened: its own start, else noon on its calendar day (local time).
double workoutAt(Object? w) {
  final m = asMap(w);
  final start = m['start'];
  if (start is num && start.isFinite) return start.toDouble();
  final day = m['d'];
  if (day is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
    final p = day.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], 12).millisecondsSinceEpoch.toDouble();
  }
  return double.nan;
}
