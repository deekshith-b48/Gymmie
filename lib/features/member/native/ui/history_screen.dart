import 'package:flutter/material.dart';

import '../domain/rows.dart';
import '../domain/session.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final list = asRows(sc.state['workouts']).reversed.toList();
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: list.isEmpty
            ? Center(child: Text('No workouts yet', style: TextStyle(color: OG.dim)))
            : ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: list.length,
                itemBuilder: (context, i) {
                  final w = list[i];
                  final dur = (w['end'] is num && w['start'] is num) ? Duration(milliseconds: ((w['end'] as num) - (w['start'] as num)).toInt()) : null;
                  return OgCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkoutDetail(workout: w))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${w['name'] ?? 'Workout'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('${w['d']}${dur == null ? '' : ' · ${fmtDuration(dur)}'} · ${setsDone(w)} sets · ${fmtNum(numOrNull(w['vol']) ?? workoutVolume(w))} ${sc.unit()}', style: TextStyle(color: OG.dim, fontSize: 12)),
                      ])),
                      if ((w['prs'] as List? ?? const []).isNotEmpty) Icon(Icons.emoji_events, color: OG.orange),
                      Icon(Icons.chevron_right, color: OG.dim),
                    ]),
                  );
                },
              ),
      );
    });
  }
}

class WorkoutDetail extends StatelessWidget {
  const WorkoutDetail({super.key, required this.workout});
  final Json workout;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final prs = {for (final p in (workout['prs'] as List? ?? const [])) '$p'};
    return Scaffold(
      appBar: AppBar(title: Text('${workout['name'] ?? 'Workout'}'), actions: [
        IconButton(icon: Icon(Icons.delete_outline, color: OG.red), onPressed: () async {
          if (!await confirm(context, 'Delete this workout?', message: 'It leaves your history and stats.', ok: 'Delete', danger: true)) return;
          sc.store.update((s) => (s['workouts'] as List).removeWhere((w) => identical(w, workout) || (w is Map && w['id'] != null && w['id'] == workout['id'])));
          if (context.mounted) Navigator.of(context).pop();
        }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${workout['d']}', style: TextStyle(color: OG.dim)),
        if ('${workout['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${workout['note']}', style: TextStyle(color: OG.orange))),
        const SizedBox(height: 12),
        for (final e in asRows(workout['entries'])) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(sc.exercise('${e['id']}')?.name ?? '${e['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (prs.contains('${e['id']}')) Icon(Icons.emoji_events, color: OG.orange, size: 20),
          ]),
          const SizedBox(height: 6),
          for (final s in asRows(e['sets'])) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Icon(s['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: s['done'] == true ? OG.acc : OG.dim),
            const SizedBox(width: 8),
            Text(s.containsKey('min') ? '${fmtNum(numOrNull(s['min']) ?? 0)} min · ${fmtNum(numOrNull(s['speed']) ?? 0)} km/h' : '${fmtNum(numOrNull(s['w']) ?? 0)} ${sc.unit()} × ${fmtNum(numOrNull(s['r']) ?? 0)}${isWarmupRow(s) ? '  (warm-up)' : ''}', style: TextStyle(color: s['done'] == true ? OG.text : OG.dim)),
          ])),
          if ('${e['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${e['note']}', style: TextStyle(color: OG.orange, fontSize: 13))),
        ])),
      ]),
    );
  }
}
