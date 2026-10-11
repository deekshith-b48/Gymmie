// Stats → "Activity (last 12 months)": openGym's heatmap, cell for cell. One column per week, one square per
// day, shaded by time trained or volume lifted (the member's choice, kept in the log as `heatmapMetric`).
// Tap a trained day to open its workout (or the list, when there were several); press and hold any day for
// its totals, which is what hovering shows in openGym.
import 'package:flutter/material.dart';

import '../domain/activity.dart';
import '../domain/rows.dart';
import 'history_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

const _cell = 11.0;
const _gap = 3.0;

/// openGym colours a level by mixing the accent into the card's second surface (index.css .hm-c.lN).
Color _levelColor(int level) {
  if (level <= 0) return OG.card2;
  const mixes = [0.0, 0.30, 0.55, 0.78, 1.0];
  return Color.lerp(OG.card2, OG.acc, mixes[level.clamp(0, 4)])!;
}

class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key, this.today});

  /// Fixed in tests; the real clock otherwise.
  final DateTime? today;

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open on the most recent weeks, as openGym does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _title(HeatCell c, NativeScope sc) {
    final t = c.totals;
    if (t == null) return c.iso;
    return '${c.iso} · ${t.workouts} workout${t.workouts == 1 ? '' : 's'} · ${t.minutes} min · ${fmtNum(t.volume)} ${sc.unit()}';
  }

  void _openDay(BuildContext context, NativeScope sc, String iso) {
    final day = [for (final w in asRows(sc.state['workouts'])) if (workoutDay(w) == iso) w];
    if (day.isEmpty) return;
    if (day.length == 1) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkoutDetail(workout: day.first)));
      return;
    }
    showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(iso, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        for (final w in day) ListTile(
          title: Text('${w['name'] ?? 'Workout'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${fmtNum(workoutDuration(w) / 60000)} min', style: TextStyle(color: OG.dim)),
          trailing: Icon(Icons.chevron_right, color: OG.dim),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkoutDetail(workout: w)));
          },
        ),
      ])),
    );
  }

  // A const widget inside a rebuilding parent is not rebuilt with it, so this one listens to the log itself:
  // a setting changed on another screen shows here at once.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: NativeScope.of(context).store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final sc = NativeScope.of(context);
    final prefs = sc.prefs;
    final metric = prefs.heatmapMetric;
    final data = buildHeatmap(sc.state, today: widget.today ?? DateTime.now(), metric: metric, weekStart: prefs.weekStart);
    final less = metric == 'vol' ? 'Less volume' : 'Less time';
    final more = metric == 'vol' ? 'More volume' : 'More time';
    return OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Activity (last 12 months)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [ButtonSegment(value: 'time', label: Text('Time')), ButtonSegment(value: 'vol', label: Text('Volume'))],
        selected: {metric},
        onSelectionChanged: (v) => sc.store.update((s) => s['heatmapMetric'] = v.first),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        controller: _scroll, scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 30, bottom: 5),
            child: Row(children: [
              for (final m in data.months) SizedBox(width: _cell + _gap, child: Text(m, softWrap: false, overflow: TextOverflow.visible, style: TextStyle(color: OG.dim, fontSize: 11))),
            ]),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 30, child: Column(children: [
              for (final l in data.dayLabels) SizedBox(height: _cell + _gap, child: Align(alignment: Alignment.centerLeft, child: Text(l ?? '', style: TextStyle(color: OG.dim, fontSize: 10, height: 1)))),
            ])),
            for (final col in data.columns) Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: Column(children: [
                for (final c in col) _Cell(
                  cell: c,
                  onTap: c.totals == null ? null : () => _openDay(context, sc, c.iso),
                  onLongPress: () => toast(context, _title(c, sc)),
                ),
              ]),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 3, children: [
        Text(less, style: TextStyle(color: OG.dim, fontSize: 11)), const SizedBox(width: 3),
        for (var l = 0; l <= 4; l++) Container(width: 10, height: 10, decoration: BoxDecoration(color: _levelColor(l), borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 3), Text(more, style: TextStyle(color: OG.dim, fontSize: 11)),
      ]),
    ]));
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.onTap, required this.onLongPress});
  final HeatCell cell;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    onLongPress: onLongPress,
    child: Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Opacity(
        opacity: cell.future ? 0.3 : 1,
        child: Container(
          key: ValueKey('hm-${cell.iso}'),
          width: _cell, height: _cell,
          decoration: BoxDecoration(
            color: _levelColor(cell.level), borderRadius: BorderRadius.circular(3),
            border: cell.isToday ? Border.all(color: OG.acc, width: 1.5) : null,
          ),
        ),
      ),
    ),
  );
}
