import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import '../domain/equipment.dart';
import '../domain/session.dart';
import 'body_map.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Choose a focus": tap the muscles to train on the body map, review the exercises that hit
/// them, tick the ones you want, and start a session with exactly those (from GymMane's Train screen).
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.onStart});

  /// Called with the picked exercises and the session name; the caller starts the workout.
  final void Function(List<Exercise> picks, String name) onStart;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  BodyGeometry? _geo;
  Object? _error;
  int _step = 1;
  final Set<String> _muscles = {};
  final List<String> _picks = [];
  String _q = '';
  int _shown = 60;

  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) return;
    _loading = true;
    BodyGeometry.load(NativeScope.of(context).prefs.bodyFigure).then((g) {
      if (mounted) setState(() => _geo = g);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  void _toggleMuscle(String m) => setState(() => _muscles.contains(m) ? _muscles.remove(m) : _muscles.add(m));

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => _step = 1); },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => _step == 2 ? setState(() => _step = 1) : Navigator.of(context).pop()),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_step == 1 ? 'STEP 1 OF 2' : 'STEP 2 OF 2', style: TextStyle(fontSize: 11, color: OG.dim, letterSpacing: 1.2)),
            Text(_step == 1 ? 'Choose a focus' : _title(sc), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        body: _step == 1 ? _select(sc) : _review(sc),
      ),
    );
  }

  String _title(NativeScope sc) => _muscles.map(sc.catalogue.muscleName).join(' + ');

  Widget _select(NativeScope sc) {
    if (_error != null) return Center(child: Text('Could not load the body map: $_error', style: TextStyle(color: OG.dim)));
    return ListView(padding: const EdgeInsets.all(16), children: [
      OgCard(padding: const EdgeInsets.all(14), child: _geo == null
          ? const SizedBox(height: 360, child: Center(child: CircularProgressIndicator()))
          : BodyMap(geometry: _geo!, selected: _muscles, onToggle: _toggleMuscle)),
      Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Tap the muscles you want to train', style: TextStyle(color: OG.dim, fontSize: 13)))),
      Container(
        constraints: const BoxConstraints(minHeight: 44), alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in _muscles) InputChip(label: Text(sc.catalogue.muscleName(m)), onDeleted: () => _toggleMuscle(m)),
        ]),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _muscles.isEmpty ? null : () => setState(() { _step = 2; _picks.clear(); _q = ''; _shown = 60; }),
        child: const Text('Continue'),
      ),
    ]);
  }

  Widget _review(NativeScope sc) {
    final profile = activeProfile(sc.state); // Settings → Equipment
    final everything = sc.allExercises;
    final allEq = profile == null ? const <String>[] : allEquipment(everything);
    final have = profileEquipment(profile);
    final usable = profile == null ? everything : [for (final e in everything) if (eqAvailable(have, e, allEq)) e];
    final list = searchExercises(exercisesForFocus(usable, _muscles), _q);
    final n = _picks.length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(decoration: const InputDecoration(hintText: 'Search exercises', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() { _q = v; _shown = 60; })),
      ),
      Expanded(child: list.isEmpty
          ? Center(child: Text('No match', style: TextStyle(color: OG.dim)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _shown < list.length ? _shown + 1 : list.length,
              itemBuilder: (context, i) {
                if (i >= _shown) return OutlinedButton(onPressed: () => setState(() => _shown += 60), child: const Text('Show more'));
                final e = list[i];
                final on = _picks.contains(e.id);
                final primary = _muscles.any(e.primaryFor);
                return OgCard(
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                  onTap: () => setState(() => on ? _picks.remove(e.id) : _picks.add(e.id)),
                  child: Row(children: [
                    ExerciseThumb(e, mediaBase: sc.mediaBase),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(primary ? 'Primary target' : 'Also trains', style: TextStyle(color: OG.dim, fontSize: 12)),
                    ])),
                    Icon(on ? Icons.check_circle : Icons.add_circle_outline, color: on ? OG.acc : OG.dim),
                  ]),
                );
              },
            )),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: n == 0 ? null : () {
            final picks = [for (final id in _picks) ?sc.exercise(id)];
            widget.onStart(picks, _title(sc));
          },
          child: Text(n == 0 ? 'Pick an exercise' : 'Start · $n exercise${n == 1 ? '' : 's'}'),
        ),
      )),
    ]);
  }
}

/// Starts [picks] as a freestyle session. Returns false when one is already running.
bool startFreestyle(NativeScope sc, List<Exercise> picks, String name, {num? bw}) {
  if (sc.store.active != null || picks.isEmpty) return false;
  sc.store.updateLocalOnly((s) {
    final now = DateTime.now();
    s['active'] = newSession(
      id: 'w${now.microsecondsSinceEpoch.toRadixString(36)}',
      day: '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      now: now.millisecondsSinceEpoch,
      name: name.isEmpty ? 'Freestyle' : name,
      entries: [for (final e in picks) buildEntry(e, s)],
      bw: bw,
    );
  });
  return true;
}
