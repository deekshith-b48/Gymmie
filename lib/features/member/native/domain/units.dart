// Converting a log between kg and lb, ported from openGym's lib/units.js. The unit switch used to only
// relabel the numbers (60 kg became "60 lb"); this walks every stored weight once. Rounded to what a gym
// can load: lb to the nearest 0.5, kg to the nearest 0.25, so a value converted there and back lands where
// it started for any plate-loadable number.
import 'dart:convert';

import 'rows.dart';
import 'session.dart' show workoutVolume;

const _lbPerKg = 2.2046226218;

dynamic convertWeight(Object? value, String from, String to) {
  if (from == to) return value;
  final v = numOrNull(value);
  if (v == null || value == '') return value;
  return to == 'lb' ? (v * _lbPerKg * 2).round() / 2 : (v / _lbPerKg * 4).round() / 4;
}

/// Body weight is not loaded on a bar, so it keeps a tenth in either unit (kg → lb → kg comes home).
dynamic convertBodyWeight(Object? value, String from, String to) {
  if (from == to) return value;
  final v = numOrNull(value);
  if (v == null || value == '') return value;
  return ((to == 'lb' ? v * _lbPerKg : v / _lbPerKg) * 10).round() / 10;
}

Json _convSet(Json set, String from, String to) {
  final out = Map<String, dynamic>.from(set);
  if (isSideSet(set)) {
    final sides = asMap(set['sides']);
    final l = _convSet(asMap(sides['L']), from, to);
    final r = _convSet(asMap(sides['R']), from, to);
    out['sides'] = {'L': l, 'R': r};
    final lw = jsNumber(l['w']), rw = jsNumber(r['w']);
    out['w'] = lw.isNaN || rw.isNaN ? out['w'] : (lw > rw ? lw : rw);
    return out;
  }
  if (out['w'] != null) out['w'] = convertWeight(out['w'], from, to);
  if (out['drops'] is List) {
    out['drops'] = [for (final d in asRows(out['drops'])) {...d, 'w': convertWeight(d['w'], from, to)}];
  }
  return out;
}

Json _convTarget(Json cfg, String from, String to) {
  final out = Map<String, dynamic>.from(cfg);
  if (out['weight'] != null) out['weight'] = convertWeight(out['weight'], from, to);
  // A per-exercise increment is a load too: 2.5 kg is 5 lb, not 2.5 lb.
  final inc = numOrNull(out['inc']);
  if (inc != null && inc > 0 && (out['mode'] == null || out['mode'] == 'reps')) out['inc'] = convertWeight(inc, from, to);
  if (out['warmup'] is List) {
    out['warmup'] = [for (final w in out['warmup'] as List) w is Map && w['weight'] != null ? {...asMap(w), 'weight': convertWeight(w['weight'], from, to)} : w];
  }
  if (out['pyramidWeight'] is List) {
    out['pyramidWeight'] = [for (final w in out['pyramidWeight'] as List) (numOrNull(w) ?? 0) > 0 ? convertWeight(w, from, to) : w];
  }
  return out;
}

Json _convEntry(Json e, String from, String to) {
  final out = Map<String, dynamic>.from(e);
  if (out['topW'] != null) out['topW'] = convertWeight(out['topW'], from, to);
  if (e['target'] is Map) out['target'] = _convTarget(asMap(e['target']), from, to);
  if (e['planned'] is Map) out['planned'] = _convTarget(asMap(e['planned']), from, to);
  if (e['sets'] is List) out['sets'] = [for (final s in asRows(e['sets'])) _convSet(s, from, to)];
  return out;
}

// A bar override is a stamped object: the 45 lb bar IS the 20 kg bar, so an override that equals the old unit's
// standard bar for that equipment drops out and the new unit's default takes over (45 lb → 20 kg, not 20.5).
// An explicit 0 ("no bar") stays 0. Any other bar converts like a weight, and drops out too if it lands on the
// new default. Without [equipmentOf] (the merge has no exercise library) every bar simply converts.
const _barKg = {'barbell': 20, 'olympic barbell': 20, 'ez barbell': 10, 'smith machine': 9, 'trap bar': 25};
const _barLb = {'barbell': 45, 'olympic barbell': 45, 'ez barbell': 25, 'smith machine': 20, 'trap bar': 55};

Json _convBars(Json bars, String from, String to, String? Function(String id)? equipmentOf) {
  num? standard(String? eq, String unit) => eq == null ? null : (unit == 'lb' ? _barLb : _barKg)[eq];
  final out = <String, dynamic>{};
  for (final e in bars.entries) {
    final v = e.value;
    if (v is! num || !v.isFinite || v < 0) continue;
    if (v == 0) {
      out[e.key] = 0;
      continue;
    }
    final eq = equipmentOf?.call(e.key);
    if (eq != null && eq.isNotEmpty && v == standard(eq, from)) continue;
    final c = convertWeight(v, from, to);
    if (eq != null && eq.isNotEmpty && c == standard(eq, to)) continue;
    out[e.key] = c;
  }
  return out;
}

/// A new log with every weight expressed in [to] and `unit` set to it.
Json convertStateUnit(Json state, String to, {String? Function(String id)? equipmentOf}) {
  final s = asMap(jsonDecode(jsonEncode(state)));
  final from = s['unit'] == 'lb' ? 'lb' : 'kg';
  if (from == to) return s;
  Json convSession(Json w) {
    final out = Map<String, dynamic>.from(w);
    out['entries'] = [for (final e in asRows(w['entries'])) _convEntry(e, from, to)];
    if (out['bw'] != null) out['bw'] = convertBodyWeight(out['bw'], from, to);
    if (numOrNull(out['vol']) != null) {
      out['vol'] = workoutVolume({'entries': [for (final e in asRows(out['entries'])) if (e['sets'] is List) e]});
    }
    return out;
  }

  s['unit'] = to;
  if (s['bodyweight'] is List) s['bodyweight'] = [for (final b in asRows(s['bodyweight'])) {...b, 'w': convertBodyWeight(b['w'], from, to)}];
  if (s['targetW'] != null) s['targetW'] = convertBodyWeight(s['targetW'], from, to);
  if (s['exWeights'] is Map) {
    s['exWeights'] = {
      for (final e in asMap(s['exWeights']).entries)
        e.key: e.value is Map ? {...asMap(e.value), 'w': convertWeight(asMap(e.value)['w'], from, to)} : convertWeight(e.value, from, to),
    };
  }
  if (s['barWeights'] is Map) s['barWeights'] = _convBars(asMap(s['barWeights']), from, to, equipmentOf);
  if (s['routines'] is List) {
    s['routines'] = [for (final r in asRows(s['routines'])) {...r, 'ex': [for (final cfg in asRows(r['ex'])) _convTarget(cfg, from, to)]}];
  }
  if (s['workouts'] is List) s['workouts'] = [for (final w in asRows(s['workouts'])) convSession(w)];
  if (s['active'] is Map) s['active'] = convSession(asMap(s['active']));
  return s;
}
