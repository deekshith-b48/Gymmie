import 'package:flutter/material.dart';

import '../domain/catalogue.dart';
import '../domain/plan.dart';
import '../domain/rows.dart';
import '../domain/session.dart';
import 'focus_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'weigh_in.dart';
import 'widgets.dart';
import 'workout_screen.dart';

/// Opens the running workout, or says why it cannot.
void openWorkout(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WorkoutScreen()));

/// Starts a session from routines (their own sets and reps, last time's weights). False if one is running.
bool startRoutines(NativeScope sc, List<Json> routines, {num? bw}) {
  if (sc.store.active != null || routines.isEmpty) return false;
  final entries = entriesFromRoutines(sc.state, sc.catalogue, routines);
  if (entries.isEmpty) return false;
  final now = DateTime.now();
  sc.store.updateLocalOnly((s) {
    s['active'] = newSession(
      id: 'w${now.microsecondsSinceEpoch.toRadixString(36)}',
      day: isoOf(now),
      now: now.millisecondsSinceEpoch,
      name: routines.map((r) => '${r['name']}').join(' + '),
      routineIds: [for (final r in routines) '${r['id']}'],
      entries: entries,
      bw: bw,
    );
  });
  return true;
}

/// Starts a workout the way the Start button does: weigh in first (unless switched off), then [start] with the
/// weight, then open the workout. [hasEntries] says up front whether there is anything to start, so nobody is
/// asked to weigh in for an empty routine.
Future<void> startAndOpen(
  BuildContext context,
  NativeScope sc,
  bool Function(num? bw) start, {
  String? emptyMessage,
  bool Function()? hasEntries,
}) async {
  if (sc.store.active != null) {
    toast(context, 'Finish the current workout first.');
    return;
  }
  if (hasEntries != null && !hasEntries()) {
    toast(context, emptyMessage ?? 'There is nothing to start.');
    return;
  }
  final w = await askWeighIn(context, sc);
  if (!w.start || !context.mounted) return;
  if (start(w.bw)) {
    openWorkout(context);
  } else {
    toast(context, emptyMessage ?? 'Finish the current workout first.');
  }
}

/// Whether the routines hold at least one exercise this app knows.
bool routinesHaveEntries(NativeScope sc, List<Json> routines) => entriesFromRoutines(sc.state, sc.catalogue, routines).isNotEmpty;

/// "Start workout": today's plan, other routines, freestyle, or a focus.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final now = DateTime.now();
      final today = routinesOn(sc.state, now);
      final todayIds = {for (final r in today) '${r['id']}'};
      final others = [for (final r in asRows(sc.state['routines'])) if (!todayIds.contains('${r['id']}')) r];
      final running = sc.store.active != null;
      return Scaffold(
        appBar: AppBar(title: const Text('Start workout')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (running) OgCard(
            onTap: () => openWorkout(context),
            child: Row(children: [
              Icon(Icons.play_circle_fill, color: OG.orange, size: 32), const SizedBox(width: 12),
              Expanded(child: Text('Resume ${sc.store.active!['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              Icon(Icons.chevron_right, color: OG.dim),
            ]),
          ),
          if (today.isNotEmpty) OgCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Today's plan", style: TextStyle(color: OG.acc, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(today.map((r) => '${r['name']}').join(' + '), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: running ? null : () => startAndOpen(context, sc, (bw) => startRoutines(sc, today, bw: bw), emptyMessage: 'These routines have no exercises yet.', hasEntries: () => routinesHaveEntries(sc, today)),
                icon: const Icon(Icons.play_arrow), label: const Text('Start'),
              ),
            ]),
          ),
          if (others.isNotEmpty) ...[
            const SectionLabel('Other routines'),
            for (final r in others) OgCard(
              onTap: running ? null : () => startAndOpen(context, sc, (bw) => startRoutines(sc, [r], bw: bw), emptyMessage: 'This routine has no exercises yet.', hasEntries: () => routinesHaveEntries(sc, [r])),
              child: Row(children: [
                Icon(Icons.fitness_center, color: OG.acc), const SizedBox(width: 12),
                Expanded(child: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${asRows(r['ex']).length} exercises', style: TextStyle(color: OG.dim, fontSize: 12)),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: running ? null : () => startFreestyleSession(context, sc),
            icon: const Icon(Icons.shuffle), label: const Text('Freestyle workout (pick as you go)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: running ? null : () => openFocus(context),
            icon: const Icon(Icons.accessibility_new), label: const Text('Choose a focus'),
          ),
        ]),
      );
    });
  }
}

/// The body-map flow; starts the picked exercises and replaces itself with the workout.
void openFocus(BuildContext context) {
  final sc = NativeScope.of(context);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => FocusScreen(onStart: (picks, name) async {
    if (sc.store.active != null) {
      toast(ctx, 'Finish the current workout first.');
      return;
    }
    final w = await askWeighIn(ctx, sc);
    if (!w.start || !ctx.mounted) return;
    final ok = startFreestyle(sc, picks, name, bw: w.bw);
    final nav = Navigator.of(ctx);
    if (ok) {
      nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => const WorkoutScreen()));
    } else {
      toast(ctx, 'Finish the current workout first.');
    }
  })));
}

/// Freestyle: an empty session you add exercises to as you go (after the weigh-in, unless it is switched off).
Future<void> startFreestyleSession(BuildContext context, NativeScope sc) async {
  if (sc.store.active != null) {
    toast(context, 'Finish the current workout first.');
    return;
  }
  final w = await askWeighIn(context, sc);
  if (!w.start || !context.mounted) return;
  final now = DateTime.now();
  sc.store.updateLocalOnly((s) => s['active'] = newSession(
    id: 'w${now.microsecondsSinceEpoch.toRadixString(36)}', day: isoOf(now), now: now.millisecondsSinceEpoch,
    name: 'Freestyle', entries: <Json>[], bw: w.bw,
  ));
  Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const WorkoutScreen()));
}

List<Exercise> pickedExercises(NativeScope sc, Iterable<String> ids) => [for (final id in ids) ?sc.exercise(id)];

/// Starts a session from a trainer plan's day. False if a workout is already running.
bool startPlanDay(NativeScope sc, String name, List<Json> entries, {num? bw}) {
  if (sc.store.active != null || entries.isEmpty) return false;
  final now = DateTime.now();
  sc.store.updateLocalOnly((s) {
    s['active'] = newSession(
      id: 'w${now.microsecondsSinceEpoch.toRadixString(36)}', day: isoOf(now), now: now.millisecondsSinceEpoch,
      name: name, entries: entries, bw: bw,
    );
  });
  return true;
}
