import 'package:flutter/material.dart';

import '../../member_models.dart';
import '../domain/assigned.dart';
import '../domain/rows.dart';
import 'scope.dart';
import 'start_screen.dart';
import 'theme.dart';
import 'weigh_in.dart';
import 'widgets.dart';

/// The workout and diet plan the trainer assigned. A workout day can be started as a session.
class AssignedPlanScreen extends StatelessWidget {
  const AssignedPlanScreen({super.key, required this.plans, this.startOnDiet = false});
  final AssignedPlans plans;
  final bool startOnDiet;

  @override
  Widget build(BuildContext context) {
    final tabs = [if (plans.workout != null) 'Workout', if (plans.diet != null) 'Diet'];
    return DefaultTabController(
      length: tabs.length, initialIndex: startOnDiet && tabs.length > 1 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(title: const Text('From your trainer'), bottom: TabBar(tabs: [for (final t in tabs) Tab(text: t)], indicatorColor: OG.acc, labelColor: OG.acc)),
        body: TabBarView(children: [
          if (plans.workout != null) _Workout(plan: plans.workout!),
          if (plans.diet != null) _Diet(plan: plans.diet!),
        ]),
      ),
    );
  }
}

class _Workout extends StatelessWidget {
  const _Workout({required this.plan});
  final Json plan;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final days = asRows(plan['days']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${plan['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      if ('${plan['goal'] ?? ''}'.isNotEmpty || '${plan['level'] ?? ''}'.isNotEmpty)
        Text([plan['goal'], plan['level']].where((e) => e != null && '$e'.isNotEmpty).join(' · '), style: TextStyle(color: OG.dim)),
      if ('${plan['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${plan['description']}', style: TextStyle(color: OG.dim))),
      const SizedBox(height: 12),
      for (final d in days) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        for (final e in asRows(d['exercises'])) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
          Expanded(child: Text('${e['name']}')),
          Text('${e['sets']} × ${e['reps']}', style: TextStyle(color: OG.dim)),
        ])),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: sc.store.active != null ? null : () async {
            final r = entriesFromPlanDay(sc.state, sc.catalogue, d);
            if (r.entries.isEmpty) {
              toast(context, 'None of these exercises could be matched. Ask your trainer.');
              return;
            }
            final w = await askWeighIn(context, sc);
            if (!w.start || !context.mounted) return;
            final ok = startPlanDay(sc, '${plan['name']} · ${d['name']}', r.entries, bw: w.bw);
            if (ok) {
              if (r.skipped.isNotEmpty) toast(context, '${r.skipped.length} exercise${r.skipped.length == 1 ? '' : 's'} could not be matched and ${r.skipped.length == 1 ? 'was' : 'were'} left out.');
              openWorkout(context);
            }
          },
          icon: const Icon(Icons.play_arrow), label: Text(sc.store.active != null ? 'Finish your current workout first' : 'Start this day'),
        ),
      ])),
    ]);
  }
}

class _Diet extends StatelessWidget {
  const _Diet({required this.plan});
  final Json plan;

  @override
  Widget build(BuildContext context) {
    final meals = asRows(plan['meals']);
    final macros = asMap(plan['macros']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${plan['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text([if (plan['calorieTarget'] != null) '${plan['calorieTarget']} kcal', if (plan['dietaryPreference'] != null) '${plan['dietaryPreference']}', if (macros.isNotEmpty) 'P ${macros['protein'] ?? 0} · C ${macros['carbs'] ?? 0} · F ${macros['fat'] ?? 0} g'].join('  ·  '), style: TextStyle(color: OG.dim)),
      if ('${plan['notes'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${plan['notes']}', style: TextStyle(color: OG.dim))),
      const SizedBox(height: 12),
      for (final m in meals) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), if ('${m['time'] ?? ''}'.isNotEmpty) Text('${m['time']}', style: TextStyle(color: OG.dim))]),
        const SizedBox(height: 6),
        for (final i in asRows(m['items'])) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
          Expanded(child: Text('${i['name']}')),
          Text('${fmtNum(numOrNull(i['quantity']) ?? 1)} ${i['unit'] ?? ''}${i['kcal'] != null ? ' · ${i['kcal']} kcal' : ''}', style: TextStyle(color: OG.dim, fontSize: 12)),
        ])),
      ])),
    ]);
  }
}
