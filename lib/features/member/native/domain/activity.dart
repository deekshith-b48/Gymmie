// The Stats "Activity (last 12 months)" heatmap, ported from openGym's components/Heatmap.jsx and the
// history helpers it reads (workoutDay, workoutDuration, workoutVolume in lib/history.js).
//
// One column per week (53 of them, ending in the current week), one cell per day, shaded in five levels by
// quartiles of the chosen metric over the days that have it: time trained or volume lifted.
import 'plan.dart' show isoOf;
import 'rows.dart';
import 'session.dart' show workoutVolume;

/// `Number(value)` as openGym's timestampOf reads it: a finite number or numeric string, else null.
double? _timestamp(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String && v.trim().isNotEmpty) {
    final n = double.tryParse(v.trim());
    return n != null && n.isFinite ? n : null;
  }
  return null;
}

/// The local calendar day a workout belongs to: its own `d`, else the day of its start time. Records with
/// neither stay out of the activity map.
String? workoutDay(Object? w) {
  final m = asMap(w);
  final day = '${m['d'] ?? ''}';
  final hit = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (hit != null) {
    final date = DateTime(int.parse(hit[1]!), int.parse(hit[2]!), int.parse(hit[3]!), 12);
    if (isoOf(date) == day) return day;
  }
  final start = _timestamp(m['start']);
  if (start != null) {
    final date = DateTime.fromMillisecondsSinceEpoch(start.round());
    return isoOf(date);
  }
  return null;
}

/// Milliseconds between the saved start and end of a session (0 when either is missing).
double workoutDuration(Object? w) {
  final m = asMap(w);
  final start = _timestamp(m['start']), end = _timestamp(m['end']);
  if (start == null || end == null) return 0;
  return end - start < 0 ? 0 : end - start;
}

/// Recomputed from the completed sets; a legacy record without entries only has its cached total.
double _volumeOf(Json w) {
  if (w['entries'] is List) {
    final v = workoutVolume(w);
    return v.isFinite && v > 0 ? v : 0;
  }
  final v = numOrNull(w['vol'])?.toDouble();
  return v != null && v.isFinite && v > 0 ? v : 0;
}

class DayTotals {
  DayTotals();
  int workouts = 0;
  double volume = 0;
  int minutes = 0;
}

class HeatCell {
  const HeatCell({required this.iso, required this.level, required this.isToday, required this.future, this.totals});
  final String iso;

  /// 0 = no workout, 1 to 4 = from the lightest to the most.
  final int level;
  final bool isToday;
  final bool future;
  final DayTotals? totals;
}

class HeatmapData {
  const HeatmapData({required this.columns, required this.months, required this.dayLabels});

  /// 53 weeks, each 7 cells long, oldest first.
  final List<List<HeatCell>> columns;

  /// One label per column ('' when none): the month name over the first week that starts it.
  final List<String> months;

  /// 'Mon' / 'Wed' / 'Fri' on their rows (week-start aware), null elsewhere.
  final List<String?> dayLabels;
}

const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Per-day totals of every workout in [state].
Map<String, DayTotals> dayTotals(Json state) {
  final agg = <String, DayTotals>{};
  for (final w in asRows(state['workouts'])) {
    final day = workoutDay(w);
    if (day == null) continue;
    final a = agg.putIfAbsent(day, DayTotals.new);
    a.workouts++;
    a.volume += _volumeOf(w);
    a.minutes += (workoutDuration(w) / 60000).round().clamp(0, 1 << 30);
  }
  return agg;
}

/// The grid for [state], ending in the week of [today]. [metric] is 'time' or 'vol'; [weekStart] a JS
/// getDay() index (1 Monday, 0 Sunday).
HeatmapData buildHeatmap(Json state, {required DateTime today, required String metric, required int weekStart}) {
  final byVolume = metric == 'vol';
  final agg = dayTotals(state);
  double valueOf(DayTotals a) => byVolume ? a.volume : a.minutes.toDouble();
  final values = [for (final a in agg.values) if (valueOf(a) > 0) valueOf(a)]..sort();
  double q(double p) => values.isEmpty ? 0 : values[(p * values.length).floor().clamp(0, values.length - 1)];
  final t1 = q(0.25), t2 = q(0.5), t3 = q(0.75);
  int level(DayTotals? a) {
    if (a == null) return 0;
    final v = valueOf(a);
    return v == 0 ? 1 : v >= t3 ? 4 : v >= t2 ? 3 : v >= t1 ? 2 : 1;
  }

  final noon = DateTime(today.year, today.month, today.day, 12);
  int offset(int day) => (day - weekStart + 7) % 7; // JS getDay(): Sunday is 0
  final end = noon.subtract(Duration(days: offset(noon.weekday % 7)));
  final start = end.subtract(const Duration(days: 52 * 7));
  final todayIso = isoOf(noon);

  final labels = List<String?>.filled(7, null);
  labels[offset(1)] = 'Mon';
  labels[offset(3)] = 'Wed';
  labels[offset(5)] = 'Fri';

  final months = <String>[];
  final columns = <List<HeatCell>>[];
  var lastMonth = -1;
  for (var wk = 0; wk <= 52; wk++) {
    final colStart = DateTime(start.year, start.month, start.day + wk * 7, 12);
    final mo = colStart.month - 1;
    final showMonth = mo != lastMonth && colStart.day <= 7 && wk < 51;
    months.add(showMonth ? monthNames[mo] : '');
    if (colStart.day <= 7) lastMonth = mo;
    final cells = <HeatCell>[];
    for (var d = 0; d < 7; d++) {
      final day = DateTime(colStart.year, colStart.month, colStart.day + d, 12);
      final iso = isoOf(day);
      final a = agg[iso];
      cells.add(HeatCell(iso: iso, level: level(a), isToday: iso == todayIso, future: day.isAfter(noon), totals: a));
    }
    columns.add(cells);
  }
  return HeatmapData(columns: columns, months: months, dayLabels: labels);
}
