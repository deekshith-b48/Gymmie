import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/catalogue.dart';
import '../domain/history.dart' as hist;
import '../domain/rows.dart';
import '../domain/session.dart';
import '../domain/settings.dart';
import 'alerts.dart';
import 'library_screen.dart';
import '../../../../core/widgets/exercise_animation.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// The live session: tick sets off, adjust load and reps, rest timer, add exercises, finish.
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with WidgetsBindingObserver {
  Timer? _tick;
  DateTime? _restEnd;
  int _restTotal = 0;
  bool _restRang = false;
  bool _awake = false;
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _flashTimer?.cancel();
    _setAwake(false);
    super.dispose();
  }

  /// Settings → Workout → Keep screen awake. The plugin is best effort: a phone without it still trains.
  void _setAwake(bool on) {
    if (_awake == on) return;
    _awake = on;
    try {
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _onTick(); // the rest end is a clock time, so it is right on return
  }

  void _onTick() {
    if (!mounted) return;
    final end = _restEnd;
    if (end != null && !_restRang && !DateTime.now().isBefore(end)) {
      _restRang = true;
      final prefs = NativeScope.of(context).prefs;
      RestAlerts.ring(prefs);
      if (prefs.timerFlash) {
        _flash = true;
        _flashTimer?.cancel();
        _flashTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _flash = false);
        });
      }
    }
    setState(() {});
  }

  void _startRest(int sec) {
    if (sec <= 0) return; // the rest timer is switched off
    _restTotal = sec;
    _restEnd = DateTime.now().add(Duration(seconds: sec));
    _restRang = false;
  }

  Json? _active(NativeScope sc) => sc.store.active;

  void _edit(NativeScope sc, void Function(Json active) fn) =>
      sc.store.updateLocalOnly((s) => fn(asMap(s['active'])));

  Future<void> _addExercise(NativeScope sc) async {
    final ex = await Navigator.of(context).push<Exercise>(MaterialPageRoute(builder: (_) => const LibraryScreen(picking: true)));
    if (ex == null || !mounted) return;
    _edit(sc, (a) {
      final entry = buildEntry(ex, sc.state);
      (a['entries'] as List).add(entry);
    });
  }

  Future<void> _finish(NativeScope sc) async {
    final a = _active(sc);
    if (a == null) return;
    final done = setsDone({'entries': a['entries']});
    final total = setUnitsTotal(a['entries']);
    final msg = done == 0
        ? 'You have not ticked any set. Finish the workout anyway?'
        : done < total ? '${total - done} set${total - done == 1 ? '' : 's'} still unticked. Finish now?' : null;
    final go = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(done == 0 ? 'Nothing logged yet' : done < total ? 'Finish early?' : 'Finish workout?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(msg, style: TextStyle(color: OG.dim))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'finish'), child: const Text('Finish and save')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'discard'), style: OutlinedButton.styleFrom(foregroundColor: OG.red), child: const Text('Discard workout')),
        ]),
      )),
    );
    if (go == null || !mounted) return;
    if (go == 'discard') {
      if (!await confirm(context, 'Discard this workout?', message: 'Nothing from it is saved.', ok: 'Discard', danger: true)) return;
      sc.store.updateLocalOnly((s) => s['active'] = null);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    FinishResult? result;
    sc.store.update((s) {
      final act = asMap(s['active']);
      result = finishSession(s, act, now: DateTime.now().millisecondsSinceEpoch, isAssisted: (id) => sc.exercise(id)?.assisted ?? false, formula: sc.prefs.oneRmFormula);
      s['active'] = null;
    });
    _restEnd = null;
    if (!mounted || result == null) return;
    await _summary(sc, result!);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _summary(NativeScope sc, FinishResult r) {
    final w = r.workout;
    final dur = Duration(milliseconds: ((w['end'] as num) - (w['start'] as num)).toInt());
    String name(String id) => sc.exercise(id)?.name ?? id;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout saved'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${w['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('Time  ${fmtDuration(dur)}'),
          Text('Volume  ${fmtNum(w['vol'] as num)} ${sc.unit()}'),
          Text('Sets  ${setsDone(w)}'),
          if (r.weightRecords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('New records', style: TextStyle(color: OG.acc, fontWeight: FontWeight.w700)),
            for (final id in r.weightRecords) Text('  ${name(id)}'),
          ],
          if (r.e1rmRecords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Stronger than ever (estimated 1RM)', style: TextStyle(color: OG.acc, fontWeight: FontWeight.w700)),
            for (var i = 0; i < r.e1rmRecords.length; i++) Text('  ${fmtNum(r.e1rmRecords[i].est)} ${sc.unit()}'),
          ],
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(
      listenable: sc.store,
      builder: (context, _) {
        final a = _active(sc);
        if (a == null) {
          return Scaffold(body: Center(child: Text('No workout in progress', style: TextStyle(color: OG.dim))));
        }
        _setAwake(sc.prefs.keepAwake);
        final entries = asRows(a['entries']);
        final start = (a['start'] as num).toInt();
        final elapsed = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - start);
        final restEnd = _restEnd;
        final left = restEnd?.difference(DateTime.now());
        return PopScope(
          // back leaves the screen but keeps the workout running (Home shows Resume)
          canPop: true,
          child: Stack(children: [
            Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('${fmtDuration(elapsed)} · ${setsDone({'entries': entries})}/${setUnitsTotal(entries)} sets', style: TextStyle(fontSize: 12, color: OG.dim)),
              ]),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton(
                    onPressed: () => _finish(sc),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
                    child: const Text('Finish'),
                  ),
                ),
              ],
            ),
            body: ListView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, left != null && !left.isNegative ? 110 : 40),
              children: [
                for (var i = 0; i < entries.length; i++) _EntryCard(key: ValueKey('${entries[i]['id']}#$i'), index: i, entry: entries[i], onRest: _startRest, onEdit: (fn) => _edit(sc, (act) => fn(asRows(act['entries'])[i], act))),
                const SizedBox(height: 4),
                OutlinedButton.icon(onPressed: () => _addExercise(sc), icon: const Icon(Icons.add), label: const Text('Add exercise')),
              ],
            ),
            bottomSheet: left == null ? null : _RestBar(left: left, total: _restTotal, onAdd: () => setState(() { _restEnd = _restEnd!.add(const Duration(seconds: 15)); _restRang = false; _restTotal += 15; }), onSkip: () => setState(() => _restEnd = null)),
          ),
            // Settings → Timer alerts → Flash the screen: a brief wash of the accent when the rest ends.
            Positioned.fill(child: IgnorePointer(child: AnimatedOpacity(
              opacity: _flash ? 1 : 0, duration: const Duration(milliseconds: 160),
              child: ColoredBox(color: OG.acc.withValues(alpha: 0.35)),
            ))),
          ]),
        );
      },
    );
  }
}

class _RestBar extends StatelessWidget {
  const _RestBar({required this.left, required this.total, required this.onAdd, required this.onSkip});
  final Duration left;
  final int total;
  final VoidCallback onAdd;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final over = left.isNegative;
    final secs = left.inSeconds < 0 ? 0 : left.inSeconds;
    return Material(
      color: OG.card2,
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(over ? 'Rest over. Go!' : 'Rest', style: TextStyle(color: over ? OG.acc : OG.dim, fontWeight: FontWeight.w700)),
            Text(fmtDuration(Duration(seconds: secs)), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: total <= 0 ? 0 : (1 - secs / total).clamp(0, 1), color: OG.acc, backgroundColor: OG.line),
          ])),
          TextButton(onPressed: onAdd, child: const Text('+15s')),
          TextButton(onPressed: onSkip, child: Text(over ? 'Dismiss' : 'Skip')),
        ]),
      )),
    );
  }
}

class _EntryCard extends StatefulWidget {
  const _EntryCard({super.key, required this.index, required this.entry, required this.onRest, required this.onEdit});
  final int index;
  final Json entry;
  final void Function(int sec) onRest;
  final void Function(void Function(Json entry, Json active) fn) onEdit;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _open = false; // a collapsed (finished) exercise the member opened again

  Json get entry => widget.entry;
  void Function(int sec) get onRest => widget.onRest;
  void Function(void Function(Json entry, Json active) fn) get onEdit => widget.onEdit;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    final prefs = sc.prefs;
    final ex = sc.exercise('${entry['id']}');
    final rows = asRows(entry['sets']);
    final cardio = ex?.cardio == true || rows.any((r) => r.containsKey('min'));
    final restSec = prefs.restSec;
    final last = hist.lastEntryFor(sc.state, '${entry['id']}', entry['rid'] as String?);
    final best = prefs.logRef == 'best' && !cardio ? hist.heaviestSet(sc.state, '${entry['id']}', isAssisted: (id) => sc.exercise(id)?.assisted ?? false) : null;
    final media = ExerciseMediaUrls.of(base: sc.mediaBase, img: ex?.img ?? '', gif: ex?.gif ?? '');
    final hasClip = media.clip != null;
    // openGym: a big autoplaying animation, a small one, or none (Settings > Workout > Exercise pictures)
    final thumb = hasClip ? 0.0 : switch (prefs.gifSize) { 'off' => 0.0, 'mini' => 30.0, _ => 46.0 };
    final finished = rows.isNotEmpty && rows.every((r) => r['done'] == true);
    if (prefs.collapseCompleted && finished && !_open) {
      return OgCard(
        onTap: () => setState(() => _open = true),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Icon(Icons.check_circle, color: OG.acc, size: 22), const SizedBox(width: 12),
          Expanded(child: Text(ex?.name ?? '${entry['id']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(cardio ? '${rows.length} sets' : rows.map((r) => '${fmtNum(numOrNull(r['w']) ?? 0)}×${fmtNum(numOrNull(r['r']) ?? 0)}').take(3).join(' · '), style: TextStyle(color: OG.dim, fontSize: 12)),
          Icon(Icons.expand_more, color: OG.dim),
        ]),
      );
    }
    return OgCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasClip && prefs.gifSize != 'off') Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 10),
          child: ExerciseAnimation(
            key: ValueKey('anim-${entry['id']}-${prefs.gifSize}'),
            stillUrl: media.still, clipUrl: media.clip, label: ex?.name,
            height: prefs.gifSize == 'mini' ? 84 : 300, mini: prefs.gifSize == 'mini',
            onToggleSize: () => sc.store.update((s) => s['gifSize'] = prefs.gifSize == 'mini' ? 'full' : 'mini'),
          ),
        ),
        Row(children: [
          if (thumb > 0) ...[ExerciseThumb(ex, mediaBase: sc.mediaBase, size: thumb), const SizedBox(width: 12)],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ex?.name ?? '${entry['id']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (best != null) Text('Best set: ${fmtNum(best.w)} ${sc.unit()} × ${best.r}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OG.dim, fontSize: 12))
            else if (prefs.logRef == 'best' && !cardio) Text('Best set: not done yet', style: TextStyle(color: OG.dim, fontSize: 12))
            else if (last != null) Text('Last time: ${last.sets.map((s) => cardio ? '${fmtNum(numOrNull(s['min']) ?? 0)} min' : '${fmtNum(numOrNull(s['w']) ?? 0)}×${fmtNum(numOrNull(s['r']) ?? 0)}').join(' · ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OG.dim, fontSize: 12)),
          ])),
          if (prefs.collapseCompleted && finished) IconButton(onPressed: () => setState(() => _open = false), icon: Icon(Icons.expand_less, color: OG.dim)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: OG.dim),
            onSelected: (v) async {
              if (v == 'remove') {
                if (await confirm(context, 'Remove ${ex?.name ?? 'exercise'}?', ok: 'Remove', danger: true)) {
                  onEdit((e, a) => (a['entries'] as List).remove(e));
                }
              } else if (v == 'note') {
                final note = await _noteDialog(context, '${entry['note'] ?? ''}');
                if (note != null) onEdit((e, a) => note.isEmpty ? e.remove('note') : e['note'] = note);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'note', child: Text('Note')), PopupMenuItem(value: 'remove', child: Text('Remove exercise'))],
          ),
        ]),
        if ('${entry['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(4, 8, 8, 0), child: Text('${entry['note']}', style: TextStyle(color: OG.orange, fontSize: 13))),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(right: 8), child: Row(children: [
          SizedBox(width: 30, child: Text('SET', style: TextStyle(color: OG.dim, fontSize: 11))),
          Expanded(child: Center(child: Text(cardio ? 'MIN' : sc.unit().toUpperCase(), style: TextStyle(color: OG.dim, fontSize: 11)))),
          Expanded(child: Center(child: Text(cardio ? 'KM/H' : 'REPS', style: TextStyle(color: OG.dim, fontSize: 11)))),
          const SizedBox(width: 48),
        ])),
        for (var i = 0; i < rows.length; i++)
          _SetRow(
            key: ValueKey('${entry['id']}-$i-${rows.length}'),
            number: i + 1,
            row: rows[i],
            cardio: cardio,
            unit: sc.unit(),
            steppers: prefs.steppers,
            effort: prefs.effort,
            onChanged: (fn) => onEdit((e, a) => fn(asRows(e['sets'])[i])),
            onToggle: () => onEdit((e, a) {
              final r = asRows(e['sets'])[i];
              toggleDone(r, DateTime.now().millisecondsSinceEpoch);
              if (r['done'] == true && !isWarmupRow(r)) onRest(restSec);
            }),
            onRemove: rows.length > 1 ? () => onEdit((e, a) => removeSet(e, i)) : null,
          ),
        Row(children: [
          TextButton.icon(onPressed: () => onEdit((e, a) => addSet(e)), icon: const Icon(Icons.add, size: 18), label: const Text('Add set')),
        ]),
      ]),
    );
  }
}

Future<String?> _noteDialog(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Note'),
      content: TextField(controller: c, autofocus: true, maxLines: 4, maxLength: 500),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

class _SetRow extends StatelessWidget {
  const _SetRow({super.key, required this.number, required this.row, required this.cardio, required this.unit, required this.steppers, required this.effort, required this.onChanged, required this.onToggle, this.onRemove});
  final int number;
  final Json row;
  final bool cardio;
  final String unit;
  final bool steppers;

  /// 'none', 'rir' or 'rpe': which effort scale the member logs (Settings → Workout → Effort per set).
  final String effort;
  final void Function(void Function(Json row) fn) onChanged;
  final VoidCallback onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final done = row['done'] == true;
    final warm = isWarmupRow(row);
    final step = unit == 'lb' ? 5 : 2.5;
    return Dismissible(
      key: ObjectKey(row),
      direction: onRemove == null ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onRemove?.call();
        return false; // the rebuilt list drops the row; keep Dismissible from owning removal
      },
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), color: OG.red.withValues(alpha: 0.25), child: Icon(Icons.delete_outline, color: OG.red)),
      child: Container(
        margin: const EdgeInsets.only(right: 8, top: 4),
        decoration: BoxDecoration(color: done ? OG.acc.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Row(children: [
          SizedBox(width: 30, child: Padding(padding: const EdgeInsets.only(left: 6), child: Text(warm ? 'W' : '$number', style: TextStyle(color: warm ? OG.orange : OG.dim, fontWeight: FontWeight.w700)))),
          Expanded(child: Center(child: cardio
              ? StepperField(value: numOrNull(row['min']) ?? 0, step: 5, width: 60, buttons: steppers, onChanged: (v) => onChanged((r) => r['min'] = v))
              : StepperField(value: numOrNull(row['w']) ?? 0, step: step, width: 60, buttons: steppers, onChanged: (v) => onChanged((r) => r['w'] = v)))),
          Expanded(child: Center(child: cardio
              ? StepperField(value: numOrNull(row['speed']) ?? 0, step: 0.5, width: 60, buttons: steppers, onChanged: (v) => onChanged((r) => r['speed'] = v))
              : StepperField(value: numOrNull(row['r']) ?? 0, step: 1, width: 60, buttons: steppers, onChanged: (v) => onChanged((r) => r['r'] = v.round())))),
          SizedBox(width: 48, child: IconButton(
            tooltip: done ? 'Undo' : 'Done',
            onPressed: onToggle,
            icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? OG.acc : OG.dim, size: 28),
          )),
          ]),
          if (effort != 'none' && !cardio) Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 12, 6),
            child: _EffortLine(
              kind: effort, value: effortOf(row, effort), steppers: steppers,
              onChanged: (v) => onChanged((r) => setEffort(r, effort, v)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "RIR 2" under a set: how many reps were left in the tank (or the RPE), stepped like openGym's field.
/// Empty is not 0: an unrated set must not become "went to failure" from one stray tap.
class _EffortLine extends StatelessWidget {
  const _EffortLine({required this.kind, required this.value, required this.steppers, required this.onChanged});
  final String kind;
  final double? value;
  final bool steppers;
  final ValueChanged<double?> onChanged;

  Future<void> _type(BuildContext context) async {
    final c = TextEditingController(text: value == null ? '' : fmtNum(value!));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(effortScale[kind]!.label),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    if (r == null) return;
    final n = double.tryParse(r.replaceAll(',', '.'));
    onChanged(r.trim().isEmpty || n == null ? null : capEffort(kind, n));
  }

  @override
  Widget build(BuildContext context) {
    final label = effortScale[kind]!.label;
    final text = value == null ? '–' : fmtNum(value!);
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text(label, style: TextStyle(color: OG.dim, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      if (steppers) SizedBox(width: 30, height: 30, child: IconButton(padding: EdgeInsets.zero, iconSize: 16, color: OG.dim, onPressed: () => onChanged(stepEffort(kind, value, -1)), icon: const Icon(Icons.remove))),
      InkWell(
        onTap: () => _type(context), borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 38, minHeight: 30), alignment: Alignment.center,
          decoration: BoxDecoration(color: OG.card2, borderRadius: BorderRadius.circular(8)),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: value == null ? OG.dim : OG.text)),
        ),
      ),
      if (steppers) SizedBox(width: 30, height: 30, child: IconButton(padding: EdgeInsets.zero, iconSize: 16, color: OG.dim, onPressed: () => onChanged(stepEffort(kind, value, 1)), icon: const Icon(Icons.add))),
    ]);
  }
}
