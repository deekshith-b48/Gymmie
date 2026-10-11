// Estimated one-rep max, ported from openGym's lib/onerm.js.
import 'dart:math' as math;

import 'rows.dart';

const repCap = 12;
const weightedRepCap = 15;
const defaultFormula = 'epley';

final Map<String, double Function(double, double)> formulas = {
  'epley': (w, r) => w * (1 + r / 30),
  'brzycki': (w, r) => w * 36 / (37 - r),
  'lombardi': (w, r) => w * math.pow(r, 0.1),
  'oconner': (w, r) => w * (1 + r / 40),
  'mayhew': (w, r) => (w * 100) / (52.2 + 41.9 * math.exp(-0.055 * r)),
  'wathan': (w, r) => (w * 100) / (48.8 + 53.8 * math.exp(-0.075 * r)),
  'lander': (w, r) => (w * 100) / (101.3 - 2.67123 * r),
};

const _rirPct = [100, 95.5, 92.2, 89.2, 86.3, 83.7, 81.1, 78.6, 76.2, 73.9, 71.7, 69.5, 67.5, 65.5, 63.6];

double _rirEstimate(double w, double effectiveReps) {
  // JS Math.round rounds half up; Dart's rounds half away from zero. Same for the positive range used here.
  final idx = math.min(math.max(effectiveReps.round() - 1, 0), _rirPct.length - 1);
  return (w * 100) / _rirPct[idx];
}

class _Weight {
  const _Weight(this.a, this.v);
  final double a;
  final double Function(double) v;
}

final Map<String, _Weight> _weights = {
  'epley': _Weight(0.95, (r) => r <= 6 ? 1 : math.max(0.4, 1 - (r - 6) * 0.12)),
  'brzycki': _Weight(1.10, (r) => r <= 8 ? 1 : math.max(0.3, 1 - (r - 8) * 0.18)),
  'lombardi': _Weight(0.85, (r) => r <= 5 ? 1 : math.max(0.4, 1 - (r - 5) * 0.10)),
  'oconner': _Weight(0.90, (r) => r <= 6 ? 1 : math.max(0.4, 1 - (r - 6) * 0.12)),
  'mayhew': _Weight(0.95, (r) => r <= 8 ? 1 : math.max(0.5, 1 - (r - 8) * 0.10)),
  'wathan': _Weight(0.90, (r) => r <= 7 ? 1 : math.max(0.4, 1 - (r - 7) * 0.12)),
  'lander': _Weight(0.85, (r) => r <= 7 ? 1 : math.max(0.35, 1 - (r - 7) * 0.15)),
  'rir': _Weight(1.00, (r) => r <= 10 ? 1 : math.max(0.4, 1 - (r - 10) * 0.15)),
};

double weightedEstimate(double w, double effectiveReps) {
  var total = 0.0;
  var wsum = 0.0;
  for (final e in formulas.entries) {
    final wt = _weights[e.key]!.a * _weights[e.key]!.v(effectiveReps);
    total += e.value(w, effectiveReps) * wt;
    wsum += wt;
  }
  final rirWt = _weights['rir']!.a * _weights['rir']!.v(effectiveReps);
  total += _rirEstimate(w, effectiveReps) * rirWt;
  wsum += rirWt;
  return total / wsum;
}

double _round1(double n) => (n * 10).round() / 10;

/// One set's estimate, or null when it cannot honestly be answered.
double? estimate1RM(Object? w, Object? r, [String formula = defaultFormula, Object? rir]) {
  final weight = jsNumber(w);
  final reps = jsNumber(r);
  if (!weight.isFinite || !reps.isFinite) return null;
  if (weight <= 0 || reps < 1) return null;
  final rirN = rir == null ? double.nan : jsNumber(rir);
  final validRir = rir != null && rirN >= 0;
  if (reps == 1 && (!validRir || rirN == 0)) return _round1(weight);

  if (formula == 'weighted') {
    final eff = validRir ? reps + rirN : reps;
    if (eff > weightedRepCap) return null;
    final est = weightedEstimate(weight, eff);
    if (!est.isFinite || est <= 0) return null;
    return _round1(est);
  }
  if (reps > repCap) return null;
  final fn = formulas[formula] ?? formulas[defaultFormula]!;
  final est = reps == 1 ? weight : fn(weight, reps.roundToDouble());
  if (!est.isFinite || est <= 0) return null;
  return _round1(est);
}

class BestSet {
  const BestSet(this.est, this.w, this.r);
  final double est;
  final double w;
  final int r;
}

/// Best estimate out of one entry's completed sets; assistance machines never produce one.
BestSet? bestSetOf(Object? entry, {String formula = defaultFormula, bool Function(String id)? isAssisted}) {
  final e = asMap(entry);
  final id = e['id'];
  if (id is String && (isAssisted?.call(id) ?? false)) return null;
  BestSet? best;
  for (final s in metricRowsForEntry(entry, 'reps')) {
    final sets = isSideSet(s)
        ? [for (final side in [asMap(asMap(s['sides'])['L']), asMap(asMap(s['sides'])['R'])]) if (side['done'] == true) side]
        : [s];
    for (final set in sets) {
      final est = estimate1RM(set['w'], set['r'], formula, set['rir']);
      if (est != null && (best == null || est > best.est)) {
        best = BestSet(est, jsNumber(set['w']), jsNumber(set['r']).round());
      }
    }
  }
  return best;
}
