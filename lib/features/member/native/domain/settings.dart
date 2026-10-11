// The member's settings, read from the log document with openGym's own key names and defaults
// (store/useStore.js DEF, lib/history.js effortOf, lib/workout-controls.js).
//
// Nothing is copied: the log document stays the one source of truth, so a setting changes the same way
// everywhere it is read, syncs with the account like any other change, and a log written by openGym
// keeps every setting it carries. Readers are forgiving (a value this version does not know reads as
// its default); writers go through [Prefs.set] so only known, well-formed values are stored.
import 'accent.dart';
import 'rows.dart';

const effortKinds = ['none', 'rir', 'rpe'];
const oneRmFormulas = ['epley', 'brzycki', 'lombardi', 'oconner', 'mayhew', 'wathan', 'lander', 'weighted'];

/// Effort scales: step, floor and ceiling (lib/history.js EFFORT).
const effortScale = {
  'rir': (step: 0.5, min: 0.0, max: 10.0, label: 'RIR'),
  'rpe': (step: 0.5, min: 6.0, max: 10.0, label: 'RPE'),
};

/// One tap of an effort stepper (lib/history.js stepEffort). null means "nothing logged".
double? stepEffort(String kind, double? cur, int dir) {
  final e = effortScale[kind];
  if (e == null) return cur;
  if (cur == null) return dir < 0 ? null : e.min;
  final n = (cur + dir * e.step) * 100;
  final v = n.roundToDouble() / 100;
  if (dir < 0 && v < e.min) return null;
  return dir > 0 ? (v < e.max ? v : e.max) : (v > e.min ? v : e.min);
}

/// A typed effort is capped but not floored (lib/history.js capEffort).
double capEffort(String kind, double v) {
  final e = effortScale[kind];
  return e == null ? v : (v < e.max ? v : e.max);
}

class Prefs {
  const Prefs(this.s);
  final Json s;

  bool _on(String key, {bool otherwise = true}) => s[key] is bool ? s[key] as bool : otherwise;
  String _str(String key, List<String> allowed, String fallback) {
    final v = s[key];
    return v is String && allowed.contains(v) ? v : fallback;
  }

  // ---- units and numbers --------------------------------------------------------------------------------------
  String get unit => s['unit'] == 'lb' ? 'lb' : 'kg';

  /// Decimals shown on weights: 1, or 2 for quarter plates (display only).
  int get decimals => s['wdec'] == 2 ? 2 : 1;
  String get oneRmFormula => _str('oneRmFormula', oneRmFormulas, 'epley');

  /// First day of the week as a JS getDay() index: 1 Monday, 0 Sunday.
  int get weekStart => (numOrNull(s['weekStart'])?.toInt() ?? 1) == 0 ? 0 : 1;

  // ---- workout ------------------------------------------------------------------------------------------------
  /// Seconds of rest after a set; 0 turns the timer off.
  int get restSec {
    final v = numOrNull(s['restSec']);
    return v == null ? 90 : v.round().clamp(0, 900);
  }

  String get effort {
    final e = s['effort'];
    if (e == 'none' || effortScale.containsKey(e)) return e as String;
    return s['showRir'] == true ? 'rir' : 'none';
  }

  /// What shows under each exercise while training: last time's sets, or the best set ever.
  String get logRef => s['logRef'] == 'best' ? 'best' : 'last';
  bool get collapseCompleted => _on('collapseCompleted', otherwise: false);
  bool get weighIn => s['weighIn'] != false;
  bool get keepAwake => s['keepAwake'] != false;

  /// "Workout day reminder": on/off and the time of day ('HH:MM').
  bool get reminderOn => asMap(s['reminder'])['on'] == true;
  String get reminderTime => RegExp(r'^\d{1,2}:\d{2}$').hasMatch('${asMap(s['reminder'])['time']}') ? '${asMap(s['reminder'])['time']}' : '07:30';

  /// 'full', 'mini' or 'off' for the exercise pictures in a workout.
  String get gifSize => s['gifSize'] == 'mini' || s['gifSize'] == 'off' ? s['gifSize'] as String : 'full';

  /// Whose reps a planned session opens with: the plan's, or last time's.
  String get startFrom => s['startFrom'] == 'last' ? 'last' : 'plan';

  /// Plus/minus buttons on weight, reps and effort fields (workout controls `steppers`).
  bool get steppers => asMap(s['wc'])['steppers'] != false;

  // ---- timer alerts -------------------------------------------------------------------------------------------
  bool get sound => _on('sound');
  bool get vibrate => s['vibrate'] != false;
  bool get timerFlash => _on('timerFlash', otherwise: false);

  // ---- look and home ------------------------------------------------------------------------------------------
  String get theme => _str('theme', const ['dark', 'light', 'system'], 'dark');
  String get accent => accentKeyOf(s);
  String get bodyFigure => s['body'] == 'female' ? 'female' : 'male';
  bool get checkInCard => s['checkIn'] != false;
  bool get weightCard => s['showWeightCard'] != false;
  bool get connectionBar => s['connStatus'] != false;

  /// 'time' or 'vol': what the Activity heatmap shades by.
  String get heatmapMetric => s['heatmapMetric'] == 'vol' ? 'vol' : 'time';

  // ---- equipment ----------------------------------------------------------------------------------------------
  List<Json> get equipProfiles => asRows(s['equipProfiles']);
  bool get equipFilterOn => s['equipFilterOn'] == true;
  String? get activeEquipId => s['activeEquipId'] is String ? s['activeEquipId'] as String : null;
}

/// Writes (or clears, when [v] is null) a set's effort on [kind]'s scale. A set carries either `rir` or `rpe`,
/// never both, so logging one drops the other.
void setEffort(Json set, String kind, double? v) {
  if (!effortScale.containsKey(kind)) return;
  if (v == null) {
    set.remove(kind);
    return;
  }
  set[kind] = v;
  set.remove(kind == 'rir' ? 'rpe' : 'rir');
}

/// The effort a set carries on [kind]'s scale, or null when it was not rated that way.
double? effortOf(Json set, String kind) => numOrNull(set[kind])?.toDouble();
