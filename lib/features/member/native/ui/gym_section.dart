import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../member_models.dart';
import '../domain/rows.dart';
import 'async_section.dart';
import 'plan_view.dart';
import 'profile_screen.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

Color statusColor(String s) => switch (s) {
  'active' => OG.acc,
  'upcoming' => OG.blue,
  'paused' => OG.orange,
  _ => OG.red,
};

String statusLabel(String s) => switch (s) {
  'active' => 'Active',
  'upcoming' => 'Starts soon',
  'paused' => 'Frozen',
  'ended' => 'Ended',
  _ => 'Expired',
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: statusColor(status).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
    child: Text(statusLabel(status), style: TextStyle(color: statusColor(status), fontWeight: FontWeight.w700, fontSize: 12)),
  );
}

/// The member's gym at a glance, on Home: membership, trainer, check-in code, profile, assigned plans.
class MyGymSection extends StatelessWidget {
  const MyGymSection({super.key});

  // A const widget inside a rebuilding parent is not rebuilt with it, so this one listens to the log itself:
  // a setting changed on another screen shows here at once.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: NativeScope.of(context).store, builder: (context, _) => _content(context));

  Widget _content(BuildContext context) {
    final sc = NativeScope.of(context);
    final o = sc.overview;
    final m = o.membership;
    return OgCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: OG.blue, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.fitness_center, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MY GYM', style: TextStyle(color: OG.dim, fontSize: 11, letterSpacing: 1)),
            Text(o.gym.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (o.gym.city != null) Text(o.gym.city!, style: TextStyle(color: OG.dim, fontSize: 12)),
          ])),
        ]),
        // the plan, dates, month, renewal and payment are in the membership card below (MembershipDetailsCard)
        if (m == null) ...[
          const SizedBox(height: 14),
          Text('You have no membership right now. Ask the front desk to add a plan.', style: TextStyle(color: OG.dim)),
        ],
        if (o.trainerName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
          Icon(Icons.person_outline, size: 18, color: OG.dim), const SizedBox(width: 6),
          Text('Trainer: ${o.trainerName}', style: TextStyle(color: OG.dim)),
        ])),
        const SizedBox(height: 14),
        Row(children: [
          if (sc.prefs.checkInCard) ...[
            Expanded(child: OutlinedButton.icon(
              onPressed: () => showCheckInCode(context, o),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.qr_code_2), label: const Text('Check in'),
            )),
            const SizedBox(width: 10),
          ],
          Expanded(child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.badge_outlined), label: const Text('My profile'),
          )),
        ]),
        AsyncSection<AssignedPlans>(
          compact: true,
          load: sc.gymApi.plans,
          builder: (context, plans) => plans.isEmpty ? const SizedBox.shrink() : Column(children: [
            const SizedBox(height: 10),
            if (plans.workout != null) _PlanTile(icon: Icons.fitness_center, title: 'Workout plan from your trainer', subtitle: '${plans.workout!['name']} · ${asRows(plans.workout!['days']).length} days', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AssignedPlanScreen(plans: plans)))),
            if (plans.diet != null) _PlanTile(icon: Icons.restaurant_menu, title: 'Diet plan from your trainer', subtitle: '${plans.diet!['name']} · ${asRows(plans.diet!['meals']).length} meals', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AssignedPlanScreen(plans: plans, startOnDiet: true)))),
          ]),
        ),
      ]),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Material(color: OG.card2, borderRadius: BorderRadius.circular(12), child: InkWell(
      borderRadius: BorderRadius.circular(12), onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(icon, color: OG.acc), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(subtitle, style: TextStyle(color: OG.dim, fontSize: 12)),
        ])),
        Icon(Icons.chevron_right, color: OG.dim),
      ])),
    )),
  );
}

/// The QR the front desk scans (always dark on white so any scanner reads it).
Future<void> showCheckInCode(BuildContext context, MemberOverview o) => showModalBottomSheet<void>(
  context: context,
  builder: (ctx) => SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Check-in code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Show this at the desk at ${o.gym.name}. Staff scan it to mark your visit.', textAlign: TextAlign.center, style: TextStyle(color: OG.dim)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14), color: Colors.white,
        child: QrImageView(
          data: o.qrPayload, size: 220,
          eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square),
          dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square),
        ),
      ),
      const SizedBox(height: 10),
      Text('${o.name}${o.admissionNo == null ? '' : ' · #${o.admissionNo}'}', style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  )),
);
