import 'package:flutter/material.dart';

import '../../member_models.dart';
import '../domain/visits.dart';
import 'async_section.dart';
import 'gym_section.dart';
import 'profile_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// The gym side of Stats: the membership and how often the member actually comes in.
class GymStats extends StatelessWidget {
  const GymStats({super.key});

  // A const widget inside a rebuilding parent is not rebuilt with it, so this one listens to the log itself:
  // a setting changed on another screen shows here at once.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: NativeScope.of(context).store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final sc = NativeScope.of(context);
    final o = sc.overview;
    final m = o.membership;
    final today = DateTime.now();
    final ws = sc.prefs.weekStart;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('Your gym'),
      OgCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
        child: m == null
            ? Text('No membership right now. Ask the front desk to add a plan.', style: TextStyle(color: OG.dim))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(m.planName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  StatusPill(m.status),
                ]),
                const SizedBox(height: 4),
                Text('${m.startDate} → ${m.endDate}${m.daysLeft != null && (m.status == 'active' || m.status == 'paused') ? ' · ${m.daysLeft} days left' : ''}', style: TextStyle(color: OG.dim)),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: periodElapsed(m.startDate, m.endDate, today), color: statusColor(m.status), backgroundColor: OG.line, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                if (m.sessionsTotal != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${m.sessionsLeft ?? 0} of ${m.sessionsTotal} sessions left', style: TextStyle(color: OG.dim))),
                if (m.balance > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Balance due: ${o.currencySymbol}${fmtNum(m.balance)}', style: TextStyle(color: OG.orange, fontWeight: FontWeight.w700))),
              ]),
      ),
      AsyncSection<AttendanceSummary>(
        load: () => sc.gymApi.attendance(days: 90),
        builder: (context, a) {
          final weeks = visitsPerWeek(a.visits, today, weekStart: ws);
          final maxW = weeks.fold(0, (x, y) => y > x ? y : x);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _Tile('Visits (30 days)', '${a.last30}')),
              const SizedBox(width: 10),
              Expanded(child: _Tile('Day streak', '${a.streakDays}')),
              const SizedBox(width: 10),
              Expanded(child: _Tile('All visits', '${a.total}')),
            ]),
            const SizedBox(height: 12),
            OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Gym visits per week', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(a.lastAttendedAt == null ? 'No visits recorded yet' : 'Last visit ${a.lastAttendedAt}', style: TextStyle(color: OG.dim, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(height: 80, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < weeks.length; i++) Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    height: maxW == 0 ? 3 : (weeks[i] / maxW * 80).clamp(3, 80).toDouble(),
                    decoration: BoxDecoration(color: i == weeks.length - 1 ? OG.blue : OG.blue.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
                  ),
                )),
              ])),
            ])),
            if (a.visits.isNotEmpty) OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recent visits', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final v in a.visits.take(5)) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                Icon(Icons.check_circle, size: 16, color: OG.acc), const SizedBox(width: 8),
                Expanded(child: Text(v.date)),
                Text(_time(v.checkIn) + (v.checkOut != null ? ' – ${_time(v.checkOut!)}' : ''), style: TextStyle(color: OG.dim, fontSize: 12)),
              ])),
            ])),
          ]);
        },
      ),
    ]);
  }

  static String _time(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => OgCard(
    margin: EdgeInsets.zero, padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: OG.dim, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
    ]),
  );
}
