// The persisted boundary for a finished session, ported from openGym's lib/finish-workout.js.
import 'history.dart';
import 'rows.dart';

const forgottenGapMs = 20 * 60 * 1000;

Json _finishedRow(Json set) {
  final sideMarked = isSideSet(set) &&
      (asMap(asMap(set['sides'])['L'])['weightOrigin'] != null ||
          asMap(asMap(set['sides'])['R'])['weightOrigin'] != null);
  if (set['planSec'] == null && set['weightOrigin'] == null && !sideMarked) return set;
  final rest = Map<String, dynamic>.from(set)..remove('planSec')..remove('weightOrigin');
  if (sideMarked) {
    Json strip(Object? side) => Map<String, dynamic>.from(asMap(side))..remove('weightOrigin');
    final sides = asMap(rest['sides']);
    rest['sides'] = {...sides, 'L': strip(sides['L']), 'R': strip(sides['R'])};
  }
  return set['planSec'] == null || rest['done'] == true ? rest : {...rest, 'sec': set['planSec']};
}

double _rowLengthMs(Json set) {
  double n(Object? v) {
    final x = jsNumber(v);
    return x > 0 ? x : 0;
  }
  if (isSideSet(set)) {
    final sides = asMap(set['sides']);
    return (n(asMap(sides['L'])['sec']) + n(asMap(sides['R'])['sec'])) * 1000;
  }
  return n(set['min']) * 60000 + n(set['sec']) * 1000;
}

/// When a session really ended: a long gap between ticks means it was over before Finish was tapped.
double sessionEnd(Object? active, double now, [int gap = forgottenGapMs]) {
  final ticks = <({double at, double len})>[
    for (final e in asRows(asMap(active)['entries']))
      for (final s in asRows(e['sets']))
        if (hasCompletedWork(s) && s['at'] is num && (s['at'] as num).isFinite)
          (at: (s['at'] as num).toDouble(), len: _rowLengthMs(s)),
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (ticks.isEmpty) return now;
  var reach = ticks.first.at + ticks.first.len;
  for (final t in ticks.skip(1)) {
    if (t.at - t.len - reach > gap) break;
    reach = reach > t.at + t.len ? reach : t.at + t.len;
  }
  return now - reach > gap ? reach : now;
}

void _cleanupSg(List<Json> ex) {
  for (var i = 0; i < ex.length; i++) {
    final e = ex[i];
    final sg = e['sg'];
    if (sg != null && sg != '' && !((i > 0 && ex[i - 1]['sg'] == sg) || (i + 1 < ex.length && ex[i + 1]['sg'] == sg))) {
      e.remove('sg');
    }
  }
  for (final e in ex) {
    if (e['sg'] == null || e['sg'] == '') {
      e.remove('sgName');
      e.remove('sgRest');
    }
  }
}

/// The finished workout as saved to history: only what was logged.
Json buildCompletedWorkout(Json active, {required double end, List<Object?> prs = const [], IsAssisted? isAssisted}) {
  final entries = <Json>[];
  for (final entry in asRows(active['entries'])) {
    final completed = <String, dynamic>{
      'id': entry['id'],
      'sets': [for (final s in asRows(entry['sets'])) _finishedRow(s)],
      'topW': () {
        final b = bestWeightForEntry(entry, isAssisted: isAssisted);
        return b == 0 || b.isNaN ? null : _num(b);
      }(),
      'target': entry['target'],
      if (entry['rid'] != null && entry['rid'] != '') 'rid': entry['rid'],
      if (entry['noProg'] == true) 'noProg': true,
      if (entry['planned'] != null && entry['planned'] != false) 'planned': entry['planned'],
      if (entry['sg'] != null && entry['sg'] != '') 'sg': entry['sg'],
    };
    final note = '${entry['note'] ?? ''}'.trim();
    if (note.isNotEmpty) {
      completed['note'] = note;
      if (entry['notePin'] == true) completed['notePin'] = true;
    }
    if ((completed['sets'] as List).any(hasCompletedWork)) entries.add(completed);
  }
  _cleanupSg(entries);
  final sessionNote = '${active['note'] ?? ''}'.trim();
  final ri = active['routineIds'] ?? (active['routineId'] != null ? [active['routineId']] : []);
  final routineIds = ri is List ? ri : [ri];
  final allNoProg = entries.isNotEmpty && entries.every((e) => e['noProg'] == true);
  return {
    'id': active['id'],
    'd': active['d'],
    'start': active['start'],
    'end': _num(end),
    'routineIds': routineIds,
    'routineId': routineIds.isEmpty ? null : routineIds.first,
    'name': active['name'],
    'bw': active['bw'],
    'entries': entries,
    'prs': prs,
    if (allNoProg) 'excludeFromProgression': true,
    if (sessionNote.isNotEmpty) 'note': sessionNote,
  };
}

/// JSON numbers that are whole stay ints (1.0 would serialise as 1.0, JS as 1).
Object _num(double v) => v == v.truncateToDouble() && v.abs() < 1e15 ? v.toInt() : v;
