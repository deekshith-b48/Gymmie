// The member's membership in full, from the gym's own records (never placeholders): the plan and its status, start and expiry,
// where they are in the month, renewal, and payment status, with "Pay online" when the gym has connected its payment account
// and "Request renewal" when the end is near.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exception.dart';
import '../../member_models.dart';
import 'account_pages.dart' show NewRequestScreen, failure, pushPage;
import 'gym_section.dart' show StatusPill;
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Days between two yyyy-mm-dd dates (b - a), whole days.
int daysBetween(String a, String b) {
  final x = DateTime.parse(a), y = DateTime.parse(b);
  return DateTime.utc(y.year, y.month, y.day).difference(DateTime.utc(x.year, x.month, x.day)).inDays;
}

/// How far through a plan a member is, as "Month 2 of 3" (a month is 30 days, as plans are sold). Null for plans under a month.
({int month, int months})? monthOfPlan(String start, String end, String today) {
  final total = daysBetween(start, end) + 1;
  if (total <= 31) return null;
  final months = (total / 30).ceil();
  final elapsed = daysBetween(start, today).clamp(0, total - 1);
  return (month: (elapsed ~/ 30 + 1).clamp(1, months), months: months);
}

class MembershipDetailsCard extends StatefulWidget {
  const MembershipDetailsCard({super.key, this.today});

  /// yyyy-mm-dd; the real date unless a test fixes it.
  final String? today;

  @override
  State<MembershipDetailsCard> createState() => _MembershipDetailsCardState();
}

class _MembershipDetailsCardState extends State<MembershipDetailsCard> {
  Future<(MemberProfile, AttendanceSummary, bool)>? _f;
  bool _paying = false;

  Future<(MemberProfile, AttendanceSummary, bool)> _load(NativeScope sc) async {
    final p = await sc.gymApi.profile();
    final a = await sc.gymApi.attendance(days: 40).catchError((Object _) => const AttendanceSummary());
    final online = await sc.gymApi.paymentsOnline().catchError((Object _) => false);
    return (p, a, online);
  }

  String _today() => widget.today ?? DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _pay(NativeScope sc, MembershipRecord m) async {
    setState(() => _paying = true);
    try {
      final url = await sc.gymApi.paymentLink();
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) toast(context, 'Could not open the payment page.');
    } catch (e) {
      if (mounted) toast(context, failure(e, 'Could not start the payment. Try again.'));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    _f ??= _load(sc);
    return FutureBuilder<(MemberProfile, AttendanceSummary, bool)>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          return OgCard(child: Row(children: [
            Icon(Icons.cloud_off, color: OG.orange), const SizedBox(width: 10),
            Expanded(child: Text(e is ApiException ? e.message : 'Could not load your membership.', style: TextStyle(color: OG.dim))),
            TextButton(onPressed: () => setState(() => _f = _load(sc)), child: const Text('Retry')),
          ]));
        }
        if (!snap.hasData) return const OgCard(child: SizedBox(height: 90, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
        final (p, att, online) = snap.data!;
        final cur = p.current;
        if (cur == null) {
          return OgCard(child: Text('No membership yet. Ask the front desk to add a plan.', style: TextStyle(color: OG.dim)));
        }
        return _card(context, sc, p, cur, att, online);
      },
    );
  }

  Widget _fact(String label, String value, {Color? color}) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: TextStyle(color: OG.dim, fontSize: 10.5, letterSpacing: 0.9)),
    const SizedBox(height: 3),
    Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color)),
  ]));

  Widget _card(BuildContext context, NativeScope sc, MemberProfile p, MembershipRecord m, AttendanceSummary att, bool online) {
    final today = _today();
    final sym = p.currencySymbol;
    final left = m.isCurrent ? daysBetween(today, m.endDate) : null;
    final totalDays = daysBetween(m.startDate, m.endDate) + 1;
    final used = daysBetween(m.startDate, today).clamp(0, totalDays);
    final monthPrefix = today.substring(0, 7);
    final visitsThisMonth = att.visits.where((v) => v.date.startsWith(monthPrefix)).map((v) => v.date).toSet().length;
    final mop = monthOfPlan(m.startDate, m.endDate, today);
    final ending = m.isCurrent && left != null && left <= 7;
    final ended = !m.isCurrent && m.status != 'upcoming';
    final pay = switch (m.paymentStatus) {
      'paid' => ('Paid in full', OG.acc),
      'partial' => ('Part paid', OG.orange),
      'unpaid' => ('Payment due', OG.red),
      _ => ('No charge', OG.dim),
    };
    return OgCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('MY MEMBERSHIP', style: TextStyle(color: OG.dim, fontSize: 11, letterSpacing: 1))),
          StatusPill(m.status),
        ]),
        const SizedBox(height: 6),
        Text(m.planName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: totalDays <= 0 ? 0 : used / totalDays, minHeight: 7, backgroundColor: OG.card2, color: ending || ended ? OG.orange : OG.acc),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _fact('Started', m.startDate),
          _fact('Expires', m.endDate, color: ending || ended ? OG.orange : null),
          _fact(left == null ? 'Status' : 'Days left', left == null ? statusLabelOf(m.status) : '${left < 0 ? 0 : left}'),
        ]),
        const SizedBox(height: 14),
        Divider(color: OG.line, height: 1),
        const SizedBox(height: 12),
        Text('THIS MONTH', style: TextStyle(color: OG.dim, fontSize: 10.5, letterSpacing: 0.9)),
        const SizedBox(height: 6),
        Row(children: [
          _fact('Visits', '$visitsThisMonth'),
          if (mop != null) _fact('Plan month', '${mop.month} of ${mop.months}'),
          if (m.sessionsTotal != null) _fact('Sessions left', '${m.sessionsLeft ?? 0} of ${m.sessionsTotal}'),
        ]),
        if (m.benefits.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 2, children: [for (final b in m.benefits) Text('✓ $b', style: TextStyle(color: OG.acc, fontSize: 12.5))]),
        ],
        const SizedBox(height: 14),
        Divider(color: OG.line, height: 1),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('PAYMENT', style: TextStyle(color: OG.dim, fontSize: 10.5, letterSpacing: 0.9))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: pay.$2.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Text(pay.$1, key: const ValueKey('payment-status'), style: TextStyle(color: pay.$2, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _fact('Plan price', '$sym${fmtNum(m.total)}'),
          _fact('Paid', '$sym${fmtNum(m.amountReceived)}'),
          _fact('Balance', '$sym${fmtNum(m.balance)}', color: m.balance > 0 ? OG.red : null),
        ]),
        if (m.invoiceNo != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Invoice ${m.invoiceNo}', style: TextStyle(color: OG.dim, fontSize: 12))),
        if (m.balance > 0 && online) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _paying ? null : () => _pay(sc, m),
            icon: _paying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_outline, size: 18),
            label: Text('Pay $sym${fmtNum(m.balance)} online'),
          ),
        ] else if (m.balance > 0)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Pay the balance at the front desk.', style: TextStyle(color: OG.dim, fontSize: 12.5))),
        const SizedBox(height: 14),
        Divider(color: OG.line, height: 1),
        const SizedBox(height: 12),
        Text('RENEWAL', style: TextStyle(color: OG.dim, fontSize: 10.5, letterSpacing: 0.9)),
        const SizedBox(height: 6),
        Text(
          ended
              ? 'Your membership ended on ${m.endDate}. Renew to keep training.'
              : left == null
                  ? 'Your plan starts on ${m.startDate}.'
                  : left <= 0
                      ? 'Your membership ends today.'
                      : 'Renews on ${DateTime.parse(m.endDate).add(const Duration(days: 1)).toIso8601String().substring(0, 10)} if you renew · $left day${left == 1 ? '' : 's'} left.',
          style: TextStyle(color: ending || ended ? OG.orange : OG.dim, fontWeight: ending || ended ? FontWeight.w700 : FontWeight.w400, height: 1.4),
        ),
        if (ending || ended) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => pushPage(context, const NewRequestScreen(initialType: 'renew')),
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('Request renewal'),
          ),
        ],
      ]),
    );
  }
}

String statusLabelOf(String s) => switch (s) {
  'active' => 'Active',
  'upcoming' => 'Starts soon',
  'paused' => 'Frozen',
  'ended' => 'Ended',
  _ => 'Expired',
};
