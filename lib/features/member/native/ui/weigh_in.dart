// "Weigh in before workouts" (Settings → Workout): Start asks for the body weight first, as openGym does.
// The weight goes on the day's weigh-in and on the session. "Start without weighing in" skips it, and so does
// the setting being off.
import 'package:flutter/material.dart';

import '../domain/plan.dart' show isoOf;
import '../domain/rows.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// The answer to the weigh-in prompt: go on ([start]) with a weight ([bw], null when skipped), or not at all.
class WeighIn {
  const WeighIn.start(this.bw) : start = true;
  const WeighIn.cancel() : start = false, bw = null;
  final bool start;
  final num? bw;
}

/// Saves [w] as today's weigh-in (replacing one already logged today).
void logBodyWeight(NativeScope sc, num w) {
  final day = isoOf(DateTime.now());
  sc.store.update((s) {
    final list = asRows(s['bodyweight']).where((e) => e['d'] != day).toList()..add({'d': day, 'w': w, 't': DateTime.now().millisecondsSinceEpoch});
    list.sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
    s['bodyweight'] = list;
  });
}

/// Asks for the weigh-in unless the setting is off. Never asks when [sc] has a workout running.
Future<WeighIn> askWeighIn(BuildContext context, NativeScope sc) async {
  if (!sc.prefs.weighIn) return const WeighIn.start(null);
  final unit = sc.unit();
  final bw = asRows(sc.state['bodyweight']);
  var value = (numOrNull(bw.isEmpty ? null : bw.last['w']) ?? (unit == 'lb' ? 154 : 70)).toDouble();
  final max = unit == 'lb' ? 1500 : 700;
  final r = await showDialog<WeighIn>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: const Text('Weigh in'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Your body weight today ($unit)', style: TextStyle(color: OG.dim)),
        const SizedBox(height: 12),
        StepperField(value: value, step: 0.1, min: 1, max: max, width: 96, onChanged: (v) => setState(() => value = (v * 10).round() / 10)),
      ]),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowButtonSpacing: 4,
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx, WeighIn.start((value * 10).round() / 10)), child: const Text('Save and start')),
        TextButton(onPressed: () => Navigator.pop(ctx, const WeighIn.start(null)), child: const Text('Start without weighing in')),
        TextButton(onPressed: () => Navigator.pop(ctx, const WeighIn.cancel()), child: Text('Cancel', style: TextStyle(color: OG.dim))),
      ],
    )),
  );
  final answer = r ?? const WeighIn.cancel();
  if (answer.start && answer.bw != null) logBodyWeight(sc, answer.bw!);
  return answer;
}
