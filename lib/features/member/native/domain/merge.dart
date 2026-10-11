// Merging two copies of a member's log when both changed (two devices, or offline edits).
//
// Phase 1 rules, deliberately simple and predictable:
//  * workouts, weigh-ins, measurements: union by identity, never losing a logged session;
//  * routines, custom exercises: union by id, this device's version wins a clash;
//  * everything else (settings, schedule, notes): this device's value wins, the other device's
//    keys this device lacks are kept;
//  * an unfinished workout (`active`) is device-local and never merged.
// Known limit: without tombstones a routine deleted on one device returns if the other still has it.
import 'rows.dart';
import 'units.dart';

String _workoutKey(Json w) => w['id'] != null ? '${w['id']}' : '${w['d']}|${w['start']}';

List<Json> _union(List<Json> mine, List<Json> theirs, String Function(Json) key, {bool sortByTime = false}) {
  final out = <String, Json>{};
  for (final x in theirs) {
    out[key(x)] = x;
  }
  for (final x in mine) {
    out[key(x)] = x;
  }
  final list = out.values.toList();
  if (sortByTime) list.sort((a, b) => workoutAt(a).compareTo(workoutAt(b)));
  return list;
}

String _unitOf(Json s) => s['unit'] == 'lb' ? 'lb' : 'kg';
// A copy that never chose a unit has no say: the one that did wins, whoever is newer.
double _unitStamp(Json s) => s['unit'] == null ? -1 : (numOrNull(asMap(s['unitSet'])['at'])?.toDouble() ?? 0);

/// Two copies written in different units (one phone switched kg/lb): the later switch wins. Its numbers are
/// kept as they are and the other copy is converted to match (or only relabelled, when the switch was
/// "keep the numbers"), so a weight is never read in the wrong unit. A tie goes to [local].
(Json, Json) _alignUnits(Json local, Json remote) {
  if (_unitOf(local) == _unitOf(remote)) return (local, remote);
  final remoteWins = _unitStamp(remote) > _unitStamp(local);
  final winner = remoteWins ? remote : local;
  final convert = asMap(winner['unitSet'])['convert'] != false;
  final to = _unitOf(winner);
  Json follow(Json loser) => convert ? convertStateUnit(loser, to) : {...loser, 'unit': to};
  final out = remoteWins ? (follow(local), remote) : (local, follow(remote));
  // the winner's stamp travels with the merged document
  if (winner['unitSet'] != null) {
    (remoteWins ? out.$1 : out.$2)['unitSet'] = winner['unitSet'];
  }
  return out;
}

/// [local] wins clashes; returns a new document and leaves both inputs untouched.
Json mergeLogs(Json local0, Json remote0) {
  final (local, remote) = _alignUnits(local0, remote0);
  final out = <String, dynamic>{...remote, ...local};
  out['workouts'] = _union(asRows(local['workouts']), asRows(remote['workouts']), _workoutKey, sortByTime: true);
  out['bodyweight'] = _union(asRows(local['bodyweight']), asRows(remote['bodyweight']), (w) => '${w['d']}')
    ..sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
  out['measurements'] = _union(asRows(local['measurements']), asRows(remote['measurements']), (w) => '${w['d']}')
    ..sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
  out['routines'] = _union(asRows(local['routines']), asRows(remote['routines']), (r) => '${r['id']}');
  out['customEx'] = _union(asRows(local['customEx']), asRows(remote['customEx']), (r) => '${r['id']}');
  final fav = <Object?>{...(remote['favEx'] as List? ?? const []), ...(local['favEx'] as List? ?? const [])};
  out['favEx'] = fav.toList();
  // best-known working weights: keep the heavier record per exercise
  final ew = <String, dynamic>{...asMap(remote['exWeights'])};
  asMap(local['exWeights']).forEach((k, v) {
    final a = jsNumber(asMap(v)['w']);
    final b = jsNumber(asMap(ew[k])['w']);
    if (!ew.containsKey(k) || (a.isFinite && (!b.isFinite || a >= b))) ew[k] = v;
  });
  out['exWeights'] = ew;
  if (local.containsKey('active')) {
    out['active'] = local['active'];
  } else {
    out.remove('active');
  }
  return out;
}
