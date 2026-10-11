import 'package:flutter/material.dart';

import '../domain/plan.dart';
import '../domain/rows.dart';
import 'gym_section.dart';
import 'membership_card.dart';
import '../log_store.dart' show SyncStatus;
import 'scope.dart';
import 'sync_banner.dart';
import 'settings_pages.dart' show showStarterPlans;
import 'settings_screen.dart';
import 'start_screen.dart';
import 'theme.dart';
import 'widgets.dart';

const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onTab});
  final ValueChanged<int> onTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return ListenableBuilder(listenable: sc.store, builder: (context, _) {
      final s = sc.state;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final ws = (s['weekStart'] as num?)?.toInt() ?? 1;
      final start = weekStartOf(today, ws).add(Duration(days: 7 * _weekOffset));
      final done = workoutDays(s);
      final routinesToday = routinesOn(s, today);
      final active = sc.store.active;
      final doneToday = done.contains(isoOf(today));
      final bw = asRows(s['bodyweight']);
      final first = sc.memberName.trim().split(' ').first;
      return SafeArea(bottom: false, child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        const SyncBanner(),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(first.isEmpty ? 'Hi' : 'Hi $first', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            Text(_dateLine(today), style: TextStyle(color: OG.dim)),
          ])),
          // With the connection bar switched off (Settings → Look & Home) a dot still warns when syncing is stuck.
          Badge(
            isLabelVisible: !sc.prefs.connectionBar && sc.store.status == SyncStatus.error,
            backgroundColor: OG.red, smallSize: 10,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        OgCard(child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => setState(() => _weekOffset--), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Center(child: Text(_weekOffset == 0 ? 'This week' : '${_short(start)} – ${_short(start.add(const Duration(days: 6)))}', style: TextStyle(color: OG.dim, fontWeight: FontWeight.w600)))),
            IconButton(onPressed: () => setState(() => _weekOffset++), icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < 7; i++) _Day(date: start.add(Duration(days: i)), today: today, done: done, planned: routineIdsOn(s, start.add(Duration(days: i))).isNotEmpty),
          ]),
          const SizedBox(height: 14),
          _TodayRow(
            title: active != null ? '${active['name']}' : routinesToday.isEmpty ? 'Rest Day' : routinesToday.map((r) => '${r['name']}').join(' + '),
            tag: active != null ? 'Resume' : doneToday ? 'Done' : routinesToday.isNotEmpty ? 'Start' : null,
            onTap: () {
              if (active != null) {
                openWorkout(context);
              } else if (routinesToday.isNotEmpty) {
                startAndOpen(context, sc, (bw) => startRoutines(sc, routinesToday, bw: bw), emptyMessage: 'These routines have no exercises yet.', hasEntries: () => routinesHaveEntries(sc, routinesToday));
              } else {
                widget.onTab(1);
              }
            },
          ),
          if (active == null) Wrap(alignment: WrapAlignment.center, children: [
            TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StartScreen())), icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Choose a different workout')),
            TextButton.icon(onPressed: () => openFocus(context), icon: const Icon(Icons.accessibility_new, size: 18), label: const Text('Choose a focus')),
          ]),
        ])),
        const MyGymSection(),
        const SizedBox(height: 12),
        const MembershipDetailsCard(),
        if (asRows(s['routines']).isEmpty) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: OG.acc, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.calendar_month, color: OG.onAcc)),
            const SizedBox(width: 12), const Text('Welcome!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text('Set up your weekly routine to get going, or grab a ready-made starter plan.', style: TextStyle(color: OG.dim)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => showStarterPlans(context), icon: const Icon(Icons.assignment_turned_in_outlined), label: const Text('Load starter plan')),
          const SizedBox(height: 6),
          TextButton(onPressed: () => widget.onTab(1), child: const Text('Build my own plan')),
        ])),
        if (sc.prefs.weightCard) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Body weight', style: TextStyle(color: OG.dim, fontWeight: FontWeight.w600))),
            TextButton.icon(onPressed: () => _logWeight(context, sc), icon: const Icon(Icons.add, size: 18), label: const Text('Log')),
          ]),
          Text(bw.isEmpty ? 'No entries yet. Log your weight to start the curve.' : '${fmtNum(numOrNull(bw.last['w']) ?? 0)} ${sc.unit()}  ·  ${bw.last['d']}', style: TextStyle(fontSize: bw.isEmpty ? 14 : 22, fontWeight: bw.isEmpty ? FontWeight.w400 : FontWeight.w800, color: bw.isEmpty ? OG.dim : OG.text)),
        ])),
        OgCard(child: Row(children: [
          Icon(Icons.local_fire_department, color: OG.orange, size: 30), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${weekStreak(s, today)} week streak', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('${workoutsInWeek(s, today)} this week · ${asRows(s['workouts']).length} workouts total', style: TextStyle(color: OG.dim, fontSize: 13)),
          ])),
        ])),
      ]));
    });
  }

  Future<void> _logWeight(BuildContext context, NativeScope sc) async {
    final c = TextEditingController();
    final v = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Body weight (${sc.unit()})'),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), onSubmitted: (t) => Navigator.pop(ctx, num.tryParse(t.replaceAll(',', '.')))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, num.tryParse(c.text.replaceAll(',', '.'))), child: const Text('Save'))],
      ),
    );
    if (v == null || !(v > 0 && v < 700)) return;
    final day = isoOf(DateTime.now());
    sc.store.update((s) {
      final list = asRows(s['bodyweight']).where((e) => e['d'] != day).toList()..add({'d': day, 'w': v});
      list.sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
      s['bodyweight'] = list;
    });
  }

  static String _short(DateTime d) => '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
  static String _dateLine(DateTime d) => '${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1]}, ${d.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]}';
}

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.today, required this.done, required this.planned});
  final DateTime date;
  final DateTime today;
  final Set<String> done;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final isToday = isoOf(date) == isoOf(today);
    final did = done.contains(isoOf(date));
    return Expanded(child: Column(children: [
      Text(_days[date.weekday - 1], style: TextStyle(color: OG.dim, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Container(
        width: 38, height: 38, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? OG.acc : null, border: !isToday && did ? Border.all(color: OG.acc, width: 2) : null),
        child: Text('${date.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isToday ? OG.onAcc : OG.text)),
      ),
      const SizedBox(height: 4),
      Icon(did ? Icons.check : Icons.circle, size: did ? 12 : 5, color: did ? OG.acc : (planned ? OG.dim : Colors.transparent)),
    ]));
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.title, required this.tag, required this.onTap});
  final String title;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: OG.card2, borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: OG.line, borderRadius: BorderRadius.circular(10)), child: Icon(tag == null ? Icons.nightlight_round : Icons.fitness_center, color: OG.text, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TODAY', style: TextStyle(color: OG.dim, fontSize: 11, letterSpacing: 1)),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ])),
        if (tag == null) Icon(Icons.add, color: OG.text) else Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: (tag == 'Resume' ? OG.orange : OG.acc).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
          child: Text(tag!, style: TextStyle(color: tag == 'Resume' ? OG.orange : OG.acc, fontWeight: FontWeight.w700)),
        ),
      ])),
    ),
  );
}
