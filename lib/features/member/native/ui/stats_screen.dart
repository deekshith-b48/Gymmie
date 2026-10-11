import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/activity.dart' show workoutDay;
import '../domain/history.dart' as hist;
import '../domain/plan.dart';
import '../domain/rows.dart';
import '../domain/session.dart';
import 'activity_card.dart';
import 'gym_stats.dart';
import 'history_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final s = sc.state;
      final workouts = asRows(s['workouts']);
      final today = DateTime.now();
      final ws = sc.prefs.weekStart;
      final weeks = <double>[];
      for (var k = 7; k >= 0; k--) {
        final start = weekStartOf(today, ws).subtract(Duration(days: 7 * k));
        final days = {for (var i = 0; i < 7; i++) isoOf(start.add(Duration(days: i)))};
        weeks.add(workouts.where((w) => days.contains('${w['d']}')).fold(0.0, (a, w) => a + (numOrNull(w['vol']) ?? workoutVolume(w))));
      }
      final maxV = weeks.fold(0.0, (a, b) => b > a ? b : a);
      final monthKey = isoOf(today).substring(0, 7);
      final monthCount = workouts.where((w) => workoutDay(w)?.substring(0, 7) == monthKey).length;
      // body weight change over the last 30 days (openGym: last weigh-in minus the first of the window)
      final cutoff = today.subtract(const Duration(days: 30));
      final bw30 = [for (final b in asRows(s['bodyweight'])) if ((DateTime.tryParse('${b['d']}') ?? DateTime(2000)).isAfter(cutoff)) b];
      final num? delta30 = bw30.length > 1 ? (numOrNull(bw30.last['w']) ?? 0) - (numOrNull(bw30.first['w']) ?? 0) : null;
      final totalVol = workouts.fold(0.0, (a, w) => a + (numOrNull(w['vol']) ?? workoutVolume(w)));
      // best estimated 1RM per exercise
      final ids = {for (final w in workouts) for (final e in asRows(w['entries'])) '${e['id']}'};
      bool assisted(String id) => sc.exercise(id)?.assisted ?? false;
      final strength = [
        for (final id in ids)
          if (hist.best1RM(s, id, formula: sc.prefs.oneRmFormula, isAssisted: assisted) case final b?) (id, b),
      ]..sort((a, b) => b.$2.est.compareTo(a.$2.est));
      return SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        const Text('Stats', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const GymStats(),
        const SectionLabel('Training'),
        Row(children: [
          Expanded(child: _Tile('Workouts', '${workouts.length}')),
          const SizedBox(width: 10),
          Expanded(child: _Tile('This month', '$monthCount')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _Tile('Week streak', '${weekStreak(s, today)}')),
          const SizedBox(width: 10),
          Expanded(child: _Tile('Weight 30d', delta30 == null ? '–' : '${delta30 > 0 ? '+' : ''}${fmtNum(delta30)} ${sc.unit()}', small: true)),
        ]),
        const SizedBox(height: 12),
        const ActivityCard(),
        OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Weekly volume', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('${fmtNum(totalVol)} ${sc.unit()} lifted in total', style: TextStyle(color: OG.dim, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(height: 110, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < weeks.length; i++) Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                height: maxV == 0 ? 3 : (weeks[i] / maxV * 110).clamp(3, 110).toDouble(),
                decoration: BoxDecoration(color: i == weeks.length - 1 ? OG.acc : OG.acc.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(4)),
              ),
            )),
          ])),
        ])),
        const SectionLabel('Strength (estimated 1RM)'),
        if (strength.isEmpty) OgCard(child: Text('Log sets with weight and reps to see your estimated one-rep max.', style: TextStyle(color: OG.dim))),
        for (final (id, b) in strength.take(12)) OgCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StrengthChart(exerciseId: id))),
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text(sc.exercise(id)?.name ?? id, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${fmtNum(b.est)} ${sc.unit()}', style: TextStyle(color: OG.acc, fontWeight: FontWeight.w800, fontSize: 16)),
            Icon(Icons.chevron_right, color: OG.dim),
          ]),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())), icon: const Icon(Icons.history), label: const Text('Workout history')),
      ]));
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.small = false});
  final String label;
  final String value;
  final bool small;
  @override
  Widget build(BuildContext context) => OgCard(
    margin: EdgeInsets.zero, padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: OG.dim, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: small ? 20 : 22, fontWeight: FontWeight.w800)),
    ]),
  );
}

class StrengthChart extends StatelessWidget {
  const StrengthChart({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final pts = hist.e1rmSeries(sc.state, exerciseId, formula: sc.prefs.oneRmFormula, isAssisted: (id) => sc.exercise(id)?.assisted ?? false);
    final spots = [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].y)];
    return Scaffold(
      appBar: AppBar(title: Text(sc.exercise(exerciseId)?.name ?? exerciseId)),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Estimated one-rep max per session', style: TextStyle(color: OG.dim)),
        const SizedBox(height: 16),
        if (spots.length < 2)
          Expanded(child: Center(child: Text('Two sessions are needed to draw a curve.', style: TextStyle(color: OG.dim))))
        else
          Expanded(child: LineChart(LineChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: (spots.length / 4).ceilToDouble().clamp(1, 999), getTitlesWidget: (v, _) {
                final i = v.toInt();
                return i < 0 || i >= pts.length ? const SizedBox.shrink() : Text('${pts[i].d}'.substring(5), style: TextStyle(color: OG.dim, fontSize: 10));
              })),
            ),
            lineBarsData: [LineChartBarData(spots: spots, isCurved: false, color: OG.acc, barWidth: 3, dotData: const FlDotData(show: true))],
          ))),
      ])),
    );
  }
}
