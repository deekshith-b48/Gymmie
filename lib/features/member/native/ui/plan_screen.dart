import 'package:flutter/material.dart';

import '../domain/plan.dart';
import '../domain/rows.dart';
import 'library_screen.dart';
import '../../../../core/widgets/exercise_animation.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Routines and which weekdays they are planned for.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final routines = asRows(sc.state['routines']);
      return SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        const Text('Plan', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        OgCard(child: Column(children: [
          for (var i = 0; i < 7; i++) _weekRow(sc, i),
        ])),
        const SectionLabel('Routines'),
        if (routines.isEmpty) OgCard(child: Text('No routines yet. Create one, add exercises, then plan it on the days you train.', style: TextStyle(color: OG.dim))),
        for (final r in routines) OgCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineEditor(routineId: '${r['id']}'))),
          child: Row(children: [
            Icon(Icons.fitness_center, color: OG.acc), const SizedBox(width: 12),
            Expanded(child: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Text('${asRows(r['ex']).length} exercises', style: TextStyle(color: OG.dim, fontSize: 12)),
            Icon(Icons.chevron_right, color: OG.dim),
          ]),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(onPressed: () => _create(context, sc), icon: const Icon(Icons.add), label: const Text('New routine')),
      ]));
    });
  }

  Widget _weekRow(NativeScope sc, int i) {
    // i: 0 Monday .. 6 Sunday; the plan is keyed by JS getDay() (Sunday 0)
    final key = '${(i + 1) % 7}';
    final day = asMap(sc.state['week'])[key];
    final ids = day is List ? day.map((e) => '$e').toList() : (day is String && day.isNotEmpty ? [day] : <String>[]);
    final names = [for (final id in ids) ?routineById(sc.state, id)?['name']];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 100, child: Text(_dayNames[i], style: TextStyle(color: OG.dim))),
        Expanded(child: Text(names.isEmpty ? 'Rest' : names.join(' + '), style: TextStyle(fontWeight: FontWeight.w600, color: names.isEmpty ? OG.dim : OG.text))),
      ]),
    );
  }

  Future<void> _create(BuildContext context, NativeScope sc) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New routine'),
        content: TextField(controller: c, autofocus: true, maxLength: 40, decoration: const InputDecoration(hintText: 'e.g. Push day'), onSubmitted: (t) => Navigator.pop(ctx, t.trim())),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create'))],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final id = 'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    sc.store.update((s) => (s['routines'] as List).add(newRoutine(id, name)));
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RoutineEditor(routineId: id)));
  }
}

class RoutineEditor extends StatelessWidget {
  const RoutineEditor({super.key, required this.routineId});
  final String routineId;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final r = routineById(sc.state, routineId);
      if (r == null) return const Scaffold(body: Center(child: Text('This routine was removed')));
      final ex = asRows(r['ex']);
      void edit(void Function(Json r) fn) => sc.store.update((s) => fn(routineById(s, routineId)!));
      return Scaffold(
        appBar: AppBar(
          title: Text('${r['name']}'),
          actions: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
              final c = TextEditingController(text: '${r['name']}');
              final n = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('Rename'), content: TextField(controller: c, autofocus: true, maxLength: 40),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
              ));
              if (n != null && n.isNotEmpty) edit((r) => r['name'] = n);
            }),
            IconButton(icon: Icon(Icons.delete_outline, color: OG.red), onPressed: () async {
              if (!await confirm(context, 'Delete ${r['name']}?', message: 'Past workouts keep their history.', ok: 'Delete', danger: true)) return;
              sc.store.update((s) {
                s['routines'] = [for (final x in asRows(s['routines'])) if (x['id'] != routineId) x];
                final week = asMap(s['week']);
                for (final k in week.keys.toList()) {
                  final v = week[k];
                  if (v is List) week[k] = [for (final id in v) if (id != routineId) id];
                  if (v == routineId) week.remove(k);
                }
                s['week'] = week;
              });
              if (context.mounted) Navigator.of(context).pop();
            }),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionLabel('Days'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 7; i++) FilterChip(
              label: Text(_dayNames[i].substring(0, 3)),
              selected: _planned(sc.state, (i + 1) % 7, routineId),
              onSelected: (on) => sc.store.update((s) {
                final week = asMap(s['week']);
                final key = '${(i + 1) % 7}';
                final cur = week[key];
                final ids = cur is List ? cur.map((e) => '$e').toList() : (cur is String && cur.isNotEmpty ? [cur] : <String>[]);
                on ? (ids.contains(routineId) ? null : ids.add(routineId)) : ids.remove(routineId);
                week[key] = ids;
                s['week'] = week;
              }),
            ),
          ]),
          const SectionLabel('Exercises'),
          if (ex.isEmpty) OgCard(child: Text('No exercises yet.', style: TextStyle(color: OG.dim))),
          for (var i = 0; i < ex.length; i++) _ExRow(
            key: ValueKey('${ex[i]['id']}-$i'),
            item: ex[i],
            onChange: (fn) => edit((r) => fn(asRows(r['ex'])[i])),
            onRemove: () => edit((r) => (r['ex'] as List).removeAt(i)),
            onMove: (d) => edit((r) {
              final l = r['ex'] as List;
              final j = i + d;
              if (j < 0 || j >= l.length) return;
              final x = l.removeAt(i);
              l.insert(j, x);
            }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final e = await Navigator.of(context).push<dynamic>(MaterialPageRoute(builder: (_) => const LibraryScreen(picking: true)));
              if (e == null) return;
              edit((r) => (r['ex'] as List).add({'id': e.id, 'sets': 3, 'reps': 10, 'weight': 0, 'mode': e.mode}));
            },
            icon: const Icon(Icons.add), label: const Text('Add exercise'),
          ),
        ]),
      );
    });
  }

  static bool _planned(Json s, int weekday, String id) {
    final v = asMap(s['week'])['$weekday'];
    return v is List ? v.contains(id) : v == id;
  }
}

class _ExRow extends StatelessWidget {
  const _ExRow({super.key, required this.item, required this.onChange, required this.onRemove, required this.onMove});
  final Json item;
  final void Function(void Function(Json item) fn) onChange;
  final VoidCallback onRemove;
  final void Function(int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final ex = sc.exercise('${item['id']}');
    return OgCard(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Column(children: [
        Row(children: [
          GestureDetector(
            onTap: ex == null ? null : () => showExerciseAnimation(context, ex.name, ExerciseMediaUrls.of(base: sc.mediaBase, img: ex.img, gif: ex.gif)),
            child: ExerciseThumb(ex, mediaBase: sc.mediaBase, size: 40),
          ), const SizedBox(width: 10),
          Expanded(child: Text(ex?.name ?? '${item['id']}', style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(icon: Icon(Icons.arrow_upward, size: 18, color: OG.dim), onPressed: () => onMove(-1)),
          IconButton(icon: Icon(Icons.arrow_downward, size: 18, color: OG.dim), onPressed: () => onMove(1)),
          IconButton(icon: Icon(Icons.close, size: 18, color: OG.dim), onPressed: onRemove),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _lab('Sets', StepperField(value: numOrNull(item['sets']) ?? 3, step: 1, min: 1, max: 20, width: 56, onChanged: (v) => onChange((i) => i['sets'] = v.round()))),
          _lab('Reps', StepperField(value: numOrNull(item['reps']) ?? 10, step: 1, min: 1, max: 100, width: 56, onChanged: (v) => onChange((i) => i['reps'] = v.round()))),
          _lab(sc.unit(), StepperField(value: numOrNull(item['weight']) ?? 0, step: sc.unit() == 'lb' ? 5 : 2.5, width: 56, onChanged: (v) => onChange((i) => i['weight'] = v))),
        ]),
      ]),
    );
  }

  Widget _lab(String t, Widget w) => Column(children: [Text(t, style: TextStyle(color: OG.dim, fontSize: 11)), w]);
}
