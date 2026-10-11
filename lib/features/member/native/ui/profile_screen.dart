import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../member_guide.dart';
import '../../member_models.dart';
import 'account_pages.dart';
import 'async_section.dart';
import 'gym_section.dart';
import 'scope.dart';
import 'theme.dart';
import 'widgets.dart';

const _openGymSource = String.fromEnvironment('OPENGYM_SOURCE_URL', defaultValue: 'https://github.com/DuarteSantos8/openGym');

/// The member's profile at their gym: who they are on the gym's books, their membership and its history,
/// the plans the gym offers, the gym's details and their trainer.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = NativeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: AsyncSection<MemberProfile>(load: sc.gymApi.profile, builder: (context, p) => _Body(p: p, o: sc.overview)),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.p, required this.o});
  final MemberProfile p;
  final MemberOverview o;

  @override
  Widget build(BuildContext context) {
    final cur = p.current;
    final hist = p.memberships.where((m) => m != cur).toList();
    final sym = p.currencySymbol;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OgCard(child: Row(children: [
        CircleAvatar(radius: 30, backgroundColor: OG.acc.withValues(alpha: 0.2), child: Text(_initials(p.name), style: TextStyle(color: OG.acc, fontWeight: FontWeight.w800, fontSize: 20))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text([if (p.admissionNo != null) 'Member #${p.admissionNo}', if (p.joinedAt != null) 'since ${p.joinedAt}'].join(' · '), style: TextStyle(color: OG.dim, fontSize: 12)),
        ])),
        IconButton(onPressed: () => showCheckInCode(context, o), icon: Icon(Icons.qr_code_2, color: OG.acc)),
      ])),
      const SectionLabel('Membership'),
      if (cur == null)
        OgCard(child: Text('No membership yet. Ask the front desk to add a plan.', style: TextStyle(color: OG.dim)))
      else
        _MembershipCard(m: cur, sym: sym, highlight: true),
      for (final m in hist) _MembershipCard(m: m, sym: sym),
      if (p.gymPlans.isNotEmpty) ...[
        const SectionLabel('Plans at your gym'),
        OgCard(child: Column(children: [
          for (var i = 0; i < p.gymPlans.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.gymPlans[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text([_duration(p.gymPlans[i].durationDays), if (p.gymPlans[i].sessionsTotal != null) '${p.gymPlans[i].sessionsTotal} sessions'].join(' · '), style: TextStyle(color: OG.dim, fontSize: 12)),
                if ((p.gymPlans[i].description ?? '').isNotEmpty) Text(p.gymPlans[i].description!, style: TextStyle(color: OG.dim, fontSize: 12)),
                if (p.gymPlans[i].benefits.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 12, runSpacing: 2, children: [for (final b in p.gymPlans[i].benefits) Text('✓ $b', style: TextStyle(color: OG.acc, fontSize: 12))])),
              ])),
              Text('$sym${fmtNum(p.gymPlans[i].price)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ],
          const SizedBox(height: 10),
          Text('Your gym approves renewals and plan changes.', style: TextStyle(color: OG.dim, fontSize: 12)),
        ])),
      ],
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: () => pushPage(context, const NewRequestScreen(initialType: 'renew')), icon: const Icon(Icons.autorenew, size: 18), label: const Text('Request renewal')),
        OutlinedButton.icon(onPressed: () => pushPage(context, const NewRequestScreen(initialType: 'change_plan')), icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Change plan')),
        TextButton(onPressed: () => pushPage(context, const RequestsScreen()), child: const Text('My requests')),
      ]),
      if (p.payments.isNotEmpty) ...[
        const SectionLabel('Payments & invoices'),
        OgCard(child: Column(children: [
          for (var i = 0; i < p.payments.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.payments[i].planName ?? (p.payments[i].kind == 'refund' ? 'Refund' : 'Payment'), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text([p.payments[i].date, p.payments[i].paymentType, p.payments[i].invoiceNo].whereType<String>().join(' · '), style: TextStyle(color: OG.dim, fontSize: 12)),
              ])),
              Text('${p.payments[i].kind == 'refund' ? '−' : ''}$sym${fmtNum(p.payments[i].amount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ],
        ])),
      ],
      const SectionLabel('Your gym'),
      OgCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.gymName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (p.gymAddress != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text([p.gymAddress, p.gymCity].whereType<String>().join(', '), style: TextStyle(color: OG.dim))),
        if (p.trainerName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Your trainer: ${p.trainerName}')),
        if (p.gymPhone != null) _link(Icons.call_outlined, p.gymPhone!, 'tel:${p.gymPhone}'),
        if (p.gymEmail != null) _link(Icons.mail_outline, p.gymEmail!, 'mailto:${p.gymEmail}'),
      ])),
      const SectionLabel('About you'),
      OgCard(child: Column(children: [
        _row('Phone', p.phone), _row('Email', p.email), _row('Gender', p.gender), _row('Date of birth', p.birthDate),
        _row('Blood group', p.bloodGroup), _row('Height', p.heightCm == null ? null : '${fmtNum(p.heightCm!)} cm'),
        _row('Weight at joining', p.weightKg == null ? null : '${fmtNum(p.weightKg!)} kg'), _row('Address', p.address),
        _row('Emergency contact', [p.emergencyName, p.emergencyPhone].whereType<String>().join(' · ')),
      ])),
      Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 0), child: Text('Edit these in Settings → My account → Edit profile. Your plan, dates and payments are managed by your gym.', style: TextStyle(color: OG.dim, fontSize: 12))),
      const SectionLabel('Help'),
      OgCard(onTap: () => showMemberGuide(context), child: Row(children: [Icon(Icons.help_outline, color: OG.acc), SizedBox(width: 12), Expanded(child: Text('How the member app works')), Icon(Icons.chevron_right, color: OG.dim)])),
      OgCard(
        onTap: () => launchUrl(Uri.parse(_openGymSource), mode: LaunchMode.externalApplication),
        child: Row(children: [Icon(Icons.code, color: OG.dim), SizedBox(width: 12), Expanded(child: Text('Training log based on openGym (AGPL-3.0) and GymMane. View source', style: TextStyle(fontSize: 13))), Icon(Icons.open_in_new, size: 18, color: OG.dim)]),
      ),
    ]);
  }

  static String _initials(String n) => n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  static String _duration(int d) => d % 365 == 0 ? '${d ~/ 365} year${d ~/ 365 == 1 ? '' : 's'}' : d % 30 == 0 ? '${d ~/ 30} month${d ~/ 30 == 1 ? '' : 's'}' : '$d days';

  static Widget _row(String k, String? v) => (v == null || v.isEmpty)
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: OG.dim, fontSize: 13))),
          Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]));

  static Widget _link(IconData i, String t, String url) => InkWell(
    onTap: () => launchUrl(Uri.parse(url)),
    child: Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Icon(i, size: 18, color: OG.acc), const SizedBox(width: 8), Text(t, style: TextStyle(color: OG.acc))])),
  );
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.m, required this.sym, this.highlight = false});
  final MembershipRecord m;
  final String sym;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final total = m.total <= 0 ? 0.0 : (m.amountReceived / m.total).clamp(0.0, 1.0);
    return OgCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.planName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: highlight ? 18 : 15))),
          StatusPill(m.status),
        ]),
        const SizedBox(height: 4),
        Text('${m.startDate} → ${m.endDate}${m.daysLeft != null && m.isCurrent ? ' · ${m.daysLeft} days left' : ''}', style: TextStyle(color: OG.dim)),
        if (m.sessionsTotal != null) Text('${m.sessionsLeft ?? 0} of ${m.sessionsTotal} sessions left', style: TextStyle(color: OG.dim)),
        if (m.benefits.isNotEmpty && (highlight || m.isCurrent)) ...[
          const SizedBox(height: 10),
          Text('INCLUDED', style: TextStyle(color: OG.dim, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final b in m.benefits)
            Padding(padding: const EdgeInsets.only(top: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_circle, size: 16, color: OG.acc),
              const SizedBox(width: 8),
              Expanded(child: Text(b)),
            ])),
        ],
        if (m.total > 0) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: total, color: m.balance > 0 ? OG.orange : OG.acc, backgroundColor: OG.line, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 6),
          Text('Paid $sym${fmtNum(m.amountReceived)} of $sym${fmtNum(m.total)}${m.balance > 0 ? ' · $sym${fmtNum(m.balance)} due' : ' · paid in full'}${m.invoiceNo == null ? '' : ' · ${m.invoiceNo}'}', style: TextStyle(color: m.balance > 0 ? OG.orange : OG.dim, fontSize: 12)),
        ],
      ]),
    );
  }
}
