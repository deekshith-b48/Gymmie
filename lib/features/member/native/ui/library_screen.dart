import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import '../domain/equipment.dart';
import '../domain/history.dart' as hist;
import '../domain/rows.dart';
import '../../../../core/widgets/exercise_animation.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Every exercise: search, muscle and equipment filters. With [picking] a tap returns the exercise.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.picking = false});
  final bool picking;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _q = '';
  String? _muscle;
  String? _equipment;
  int _shown = 60;

  // The tab stays alive behind Settings, so it listens to the log: an equipment profile switched on there, a
  // favourite starred in the detail page, or a custom exercise shows up the moment the member comes back.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: NativeScope.of(context).store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final sc = NativeScope.of(context);
    final all = sc.allExercises;
    // Settings → Equipment: with a profile on, only what that equipment allows (body weight always stays).
    final profile = activeProfile(sc.state);
    final allEq = profile == null ? const <String>[] : allEquipment(all);
    final have = profileEquipment(profile);
    var list = profile == null ? all : [for (final e in all) if (eqAvailable(have, e, allEq)) e];
    if (_muscle != null) list = exercisesForFocus(list, {_muscle!});
    if (_equipment != null) list = [for (final e in list) if (e.equipment == _equipment) e];
    list = searchExercises(list, _q);
    final fav = {...(sc.state['favEx'] as List? ?? const []).map((e) => '$e')};
    if (fav.isNotEmpty) {
      list = [...list.where((e) => fav.contains(e.id)), ...list.where((e) => !fav.contains(e.id))];
    }
    final equip = ({for (final e in all) if (e.equipment.isNotEmpty) e.equipment}.toList()..sort());
    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          decoration: const InputDecoration(hintText: 'Search exercises', prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() { _q = v; _shown = 60; }),
        ),
      ),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final m in sc.catalogue.muscles)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FilterChip(
            label: Text(m.name), selected: _muscle == m.id,
            onSelected: (on) => setState(() { _muscle = on ? m.id : null; _shown = 60; }),
          )),
      ])),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final q in equip)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FilterChip(
            label: Text(q), selected: _equipment == q,
            onSelected: (on) => setState(() { _equipment = on ? q : null; _shown = 60; }),
          )),
      ])),
      if (profile != null) Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(children: [
          Icon(Icons.filter_alt_outlined, size: 16, color: OG.acc), const SizedBox(width: 6),
          Expanded(child: Text('Only what you can do with ${profile['name']}', style: TextStyle(color: OG.dim, fontSize: 12.5))),
          TextButton(onPressed: () => sc.store.update((x) => x['equipFilterOn'] = false), child: const Text('Show everything')),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 2), child: Align(alignment: Alignment.centerLeft, child: Text('${list.length} exercises', style: TextStyle(color: OG.dim, fontSize: 12)))),
      Expanded(child: list.isEmpty
          ? Center(child: Text('No match', style: TextStyle(color: OG.dim)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _shown < list.length ? _shown + 1 : list.length,
              itemBuilder: (context, i) {
                if (i >= _shown) {
                  return Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: () => setState(() => _shown += 60), child: const Text('Show more')));
                }
                final e = list[i];
                return OgCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  onTap: () => widget.picking ? Navigator.of(context).pop(e) : Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExerciseDetail(exercise: e))),
                  child: Row(children: [
                    ExerciseThumb(e, mediaBase: sc.mediaBase),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text([e.bodypart, e.equipment].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: OG.dim, fontSize: 12)),
                    ])),
                    Icon(widget.picking ? Icons.add_circle_outline : Icons.chevron_right, color: OG.dim),
                  ]),
                );
              },
            )),
    ]);
    if (!widget.picking) {
      return SafeArea(bottom: false, child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('Exercises', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)))),
        Expanded(child: body),
      ]));
    }
    return Scaffold(appBar: AppBar(title: const Text('Add exercise')), body: body);
  }
}

class ExerciseDetail extends StatelessWidget {
  const ExerciseDetail({super.key, required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final e = exercise;
      final fav = (sc.state['favEx'] as List? ?? const []).contains(e.id);
      final best = hist.best1RM(sc.state, e.id, formula: sc.prefs.oneRmFormula, isAssisted: (id) => sc.exercise(id)?.assisted ?? false);
      final last = hist.lastEntryFor(sc.state, e.id);
      final muscles = e.weights.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return Scaffold(
        appBar: AppBar(actions: [
          IconButton(
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? OG.orange : OG.dim),
            onPressed: () => sc.store.update((s) {
              final l = [...(s['favEx'] as List? ?? const [])];
              fav ? l.remove(e.id) : l.add(e.id);
              s['favEx'] = l;
            }),
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _bigMedia(sc, e),
          const SizedBox(height: 16),
          Text(e.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text([e.bodypart, e.equipment, e.category].where((s) => s.isNotEmpty).join(' · '), style: TextStyle(color: OG.dim)),
          const SectionLabel('Muscles'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in muscles) Chip(label: Text('${sc.catalogue.muscleName(m.key)}${m.value == 1 ? '' : ' (helps)'}'), backgroundColor: m.value == 1 ? OG.acc.withValues(alpha: 0.25) : OG.card2),
          ]),
          const SectionLabel('Your history'),
          OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (best == null && last == null) Text('Nothing logged yet', style: TextStyle(color: OG.dim)),
            if (best != null) Text('Estimated 1RM  ${fmtNum(best.est)} ${sc.unit()}  (${fmtNum(best.w)} × ${best.r}, ${best.d})', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (last != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Last time (${last.d}):  ${last.sets.map((s) => '${fmtNum(numOrNull(s['w']) ?? 0)}×${fmtNum(numOrNull(s['r']) ?? 0)}').join(' · ')}', style: TextStyle(color: OG.dim))),
          ])),
        ]),
      );
    });
  }
}

/// The exercise's animation, large, as in openGym's exercise sheet: still first, the clip plays over it, tap to pause.
Widget _bigMedia(NativeScope sc, Exercise e) {
  final u = ExerciseMediaUrls.of(base: sc.mediaBase, img: e.img, gif: e.gif);
  if (u.still == null && u.clip == null) return Center(child: ExerciseThumb(e, mediaBase: sc.mediaBase, size: 120));
  return ExerciseAnimation(stillUrl: u.still, clipUrl: u.clip, height: 300, label: e.name);
}
