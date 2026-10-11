import '../../member_models.dart';
import 'plan.dart';

/// Visits per week for the last [weeks] weeks, oldest first, the last entry being the week of [today].
List<int> visitsPerWeek(Iterable<Visit> visits, DateTime today, {int weekStart = 1, int weeks = 12}) {
  final first = weekStartOf(today, weekStart).subtract(Duration(days: 7 * (weeks - 1)));
  final counts = List<int>.filled(weeks, 0);
  for (final v in visits) {
    final p = v.date.split('-');
    if (p.length != 3) continue;
    final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    final w = d.difference(first).inDays ~/ 7;
    if (!d.isBefore(first) && w >= 0 && w < weeks) counts[w]++;
  }
  return counts;
}

/// Share of a membership's period that has passed (0..1), by calendar dates.
double periodElapsed(String start, String end, DateTime today) {
  DateTime? p(String s) => DateTime.tryParse(s);
  final a = p(start), b = p(end);
  if (a == null || b == null) return 0;
  final total = b.difference(a).inDays + 1;
  if (total <= 0) return 1;
  final done = DateTime(today.year, today.month, today.day).difference(a).inDays + 1;
  return (done / total).clamp(0.0, 1.0);
}
