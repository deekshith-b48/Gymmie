import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';
import 'member_actions.dart';
import 'member_widgets.dart';

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => AsyncCubit<MemberDetail>(
      () => getIt<MembersRepository>().detail(memberId),
    ),
    child: _DetailView(memberId: memberId),
  );
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.memberId});
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AsyncCubit<MemberDetail>>();
    final session = getIt<SessionCubit>().state;
    return BlocBuilder<AsyncCubit<MemberDetail>, AsyncState<MemberDetail>>(
      builder: (context, state) {
        final d = state.data;
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(d?.summary.name ?? 'Member Details'),
              actions: [
                if (d != null && session.can(Perm.membersWrite))
                  _Menu(detail: d, onChanged: cubit.refresh),
              ],
              bottom: d == null
                  ? null
                  : const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: 'Overview'),
                        Tab(text: 'Memberships'),
                        Tab(text: 'Health'),
                        Tab(text: 'Plans'),
                        Tab(text: 'Documents'),
                      ],
                    ),
            ),
            body: state.isLoading
                ? const LoadingBox()
                : (d == null
                      ? ErrorState(error: state.error!, onRetry: cubit.load)
                      : TabBarView(
                          children: [
                            _Overview(
                              detail: d,
                              onChanged: cubit.refresh,
                              session: session,
                            ),
                            _MembershipsTab(
                              detail: d,
                              onChanged: cubit.refresh,
                              session: session,
                            ),
                            _HealthTab(
                              detail: d,
                              onChanged: cubit.refresh,
                              session: session,
                            ),
                            _PlansTab(detail: d, session: session),
                            _DocumentsTab(detail: d, session: session),
                          ],
                        )),
          ),
        );
      },
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.detail, required this.onChanged});
  final MemberDetail detail;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final m = detail.summary;
    final a = MemberActions(context);
    Future<void> run(Future<bool> f) async {
      if (await f) await onChanged();
    }

    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await context.push('/members/${m.id}/edit');
            await onChanged();
          case 'block':
            await run(a.block(m));
          case 'labels':
            await run(a.editLabels(m));
          case 'trainer':
            await run(a.assignTrainer(m));
          case 'contact':
            await _saveContact(context, m);
          case 'reminder':
            await run(a.setReminder(m));
          case 'qr':
            await _showQr(context, m);
          case 'idcard':
            await context.push('/members/${m.id}/id-card');
          case 'delete':
            await _delete(context, m);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit Member')),
        PopupMenuItem(
          value: 'block',
          child: Text(m.blocked ? 'Unblock Member' : 'Block Member'),
        ),
        const PopupMenuItem(value: 'labels', child: Text('Assign Labels')),
        const PopupMenuItem(value: 'trainer', child: Text('Assign Trainer')),
        if (m.balance > 0)
          const PopupMenuItem(
            value: 'reminder',
            child: Text('Set a Balance Reminder'),
          ),
        const PopupMenuItem(value: 'contact', child: Text('Save Contact')),
        const PopupMenuItem(value: 'qr', child: Text('Show member QR')),
        const PopupMenuItem(value: 'idcard', child: Text('Generate ID card')),
        if (getIt<SessionCubit>().state.can(Perm.settingsWrite))
          const PopupMenuItem(
            value: 'delete',
            child: Text(
              'Delete member',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
      ],
    );
  }

  Future<void> _saveContact(BuildContext context, MemberSummary m) async {
    try {
      if (!await FlutterContacts.permissions
          .request(PermissionType.readWrite)
          .then(
            (s) =>
                s == PermissionStatus.granted || s == PermissionStatus.limited,
          )) {
        if (context.mounted) {
          showToast(
            context,
            'Contacts permission is needed to save the contact',
            error: true,
          );
        }
        return;
      }
      await FlutterContacts.create(
        Contact(
          name: Name(first: m.name),
          phones: [Phone(number: m.phone)],
          emails: [if (m.email != null) Email(address: m.email!)],
        ),
      );
      if (context.mounted) showToast(context, 'Member Contact Saved');
    } catch (_) {
      if (context.mounted) {
        showToast(context, 'Could not save the contact', error: true);
      }
    }
  }

  Future<void> _showQr(BuildContext context, MemberSummary m) async {
    final gym = getIt<SessionCubit>().state.profile!;
    await showAppSheet<void>(
      context,
      title: 'Member QR',
      builder: (ctx) => Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(
                data: 'dgymbook://member/${gym.code}/${m.id}',
                size: 220,
              ),
            ),
            const Gap(12),
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '#${m.admissionNo}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const Gap(6),
            const Text(
              'Scan with "Scan member QR" to mark attendance.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, MemberSummary m) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete member?',
      message:
          'This removes ${m.name} from your gym. Their payment history is kept for your records.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final done = await runOk(
      context,
      () => getIt<MembersRepository>().delete(m.id),
      success: 'Member deleted',
    );
    if (done && context.mounted) context.pop();
  }
}

// ---------------------------------------------------------------------------------------------
class _Overview extends StatelessWidget {
  const _Overview({
    required this.detail,
    required this.onChanged,
    required this.session,
  });
  final MemberDetail detail;
  final Future<void> Function() onChanged;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final m = detail.summary;
    final cur = m.membership;
    final canWrite = session.can(Perm.membersWrite);
    final gymName = session.profile?.name ?? '';
    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(name: m.name, url: m.photoUrl, radius: 34),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Member ID #${m.admissionNo}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            m.phone,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (cur != null)
                                Tag(
                                  statusTitle(cur.status),
                                  tone: statusTone(cur.status),
                                )
                              else
                                const Tag('No plan'),
                              if (m.blocked)
                                const Tag(
                                  'Blocked',
                                  tone: Tone.danger,
                                  icon: Icons.block,
                                ),
                              for (final l in m.labels)
                                Tag(l.name, icon: Icons.label_outline),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Action(
                      icon: Icons.call_outlined,
                      label: 'Call',
                      onTap: () => Launch.call(context, m.phone),
                    ),
                    _Action(
                      icon: Icons.chat_outlined,
                      label: 'WhatsApp',
                      onTap: () => _sendMessage(context, m, gymName, cur),
                    ),
                    if (session.can(Perm.attendanceWrite) &&
                        session.feature(Feat.attendance))
                      _Action(
                        icon: Icons.how_to_reg_outlined,
                        label: 'Attendance',
                        onTap: () => _mark(context, m),
                      ),
                    if (canWrite)
                      _Action(
                        icon: Icons.autorenew,
                        label: 'Renew',
                        onTap: () async {
                          await context.push('/members/${m.id}/renew');
                          await onChanged();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (m.blocked)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InfoBanner(
                'This member is blocked${m.blockedReason == null ? '' : ': ${m.blockedReason}'}',
                icon: Icons.block,
                warning: true,
              ),
            ),
          for (final r in detail.atRisk)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InfoBanner(
                '${r.label}${r.detail == null ? '' : ' · ${r.detail}'}',
                icon: Icons.trending_down,
                warning: true,
              ),
            ),
          if (cur != null)
            _CurrentMembership(
              detail: detail,
              onChanged: onChanged,
              canWrite: canWrite,
            ),
          if (cur == null && canWrite)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppCard(
                child: Column(
                  children: [
                    const Text(
                      'No membership yet',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Assign a plan to start tracking attendance and payments.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        await context.push('/members/${m.id}/renew');
                        await onChanged();
                      },
                      child: const Text('Add Membership'),
                    ),
                  ],
                ),
              ),
            ),
          if (m.balance > 0 && session.can(Perm.financeWrite))
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppCard(
                color: AppColors.dangerTint,
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Balance Due ${Fmt.money(m.balance)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          ),
                          if (m.balanceReminder != null)
                            Text(
                              'Reminder on ${Fmt.date(m.balanceReminder)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.danger,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await MemberActions(context).settle(m)) {
                          await onChanged();
                        }
                      },
                      child: const Text('Settle'),
                    ),
                  ],
                ),
              ),
            ),
          const SectionTitle(
            'Member Info',
            padding: EdgeInsets.fromLTRB(2, 20, 2, 4),
          ),
          AppCard(
            child: Column(
              children: [
                InfoRow('Joining date', Fmt.date(m.joinedAt)),
                InfoRow(
                  'Date of birth',
                  m.birthDate == null ? null : Fmt.date(m.birthDate),
                ),
                InfoRow(
                  'Gender',
                  m.gender == null
                      ? null
                      : '${m.gender![0].toUpperCase()}${m.gender!.substring(1)}',
                ),
                InfoRow('Blood group', m.bloodGroup),
                InfoRow('Email', m.email),
                InfoRow('Address', detail.address),
                InfoRow('Trainer', m.trainerName),
                if (detail.emergencyName != null ||
                    detail.emergencyPhone != null)
                  InfoRow(
                    'Emergency contact',
                    [
                      detail.emergencyName,
                      detail.emergencyPhone,
                    ].whereType<String>().join(' · '),
                  ),
                InfoRow(
                  'Last attended',
                  m.lastAttendedAt == null
                      ? 'Never'
                      : Fmt.date(m.lastAttendedAt),
                ),
                InfoRow('Visits (30 days)', '${detail.visitsLast30}'),
                if (detail.notes != null) InfoRow('Notes', detail.notes),
              ],
            ),
          ),
          if (detail.recentTransactions.isNotEmpty) ...[
            SectionTitle(
              'Recent transactions',
              padding: const EdgeInsets.fromLTRB(2, 20, 2, 4),
              trailing: TextButton(
                onPressed: () => context.push('/transactions?memberId=${m.id}'),
                child: const Text('View all'),
              ),
            ),
            for (final t in detail.recentTransactions.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kind(t['kind']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${Fmt.date(t['date'] as String?)} · ${paymentTypeLabel('${t['paymentType']}')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Fmt.money((t['amount'] as num?) ?? 0),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: t['kind'] == 'writeoff'
                              ? AppColors.textMuted
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _kind(Object? k) => switch ('$k') {
    'membership' => 'Membership',
    'sale' => 'Product Sale',
    'settlement' => 'Balance Settlement',
    'writeoff' => 'Write-off',
    _ => '$k',
  };

  Future<void> _mark(BuildContext context, MemberSummary m) async {
    final r = await runWithProgress(
      context,
      () => getIt<AttendanceRepository>().mark(m.id),
      success: 'Attendance marked successfully',
    );
    if (r != null) await onChanged();
  }

  Future<void> _sendMessage(
    BuildContext context,
    MemberSummary m,
    String gym,
    MembershipInfo? cur,
  ) async {
    final options = <(String, String)>[
      ('Send Hello Message', 'Hi ${m.name}, this is $gym.'),
      (
        'Send Welcome Message',
        'Hi ${m.name}, welcome to $gym!${cur == null ? '' : ' Your ${cur.planName} membership is valid till ${Fmt.date(cur.endDate)}.'}',
      ),
      if (cur != null)
        (
          'Send Renewal Reminder',
          'Hi ${m.name}, your ${cur.planName} membership at $gym ${cur.status == 'expired' ? 'expired on' : 'expires on'} ${Fmt.date(cur.endDate)}. Renew now to keep training.',
        ),
      if (m.balance > 0)
        (
          'Send Balance Reminder',
          'Hi ${m.name}, a balance of ${Fmt.money(m.balance)} is pending at $gym. Please clear it at your earliest.',
        ),
    ];
    final pick = await showPickerSheet<(String, String)>(
      context,
      title: 'Send Message',
      items: options,
      labelOf: (o) => o.$1,
      subtitleOf: (o) => o.$2,
    );
    if (pick != null && context.mounted) {
      Launch.whatsApp(context, m.phone, text: pick.$2);
    }
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.chip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11.5)),
          ],
        ),
      ),
    ),
  );
}

class _CurrentMembership extends StatelessWidget {
  const _CurrentMembership({
    required this.detail,
    required this.onChanged,
    required this.canWrite,
  });
  final MemberDetail detail;
  final Future<void> Function() onChanged;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final info = detail.summary.membership!;
    final m = detail.memberships.where((x) => x.id == info.id).firstOrNull;
    if (m == null) return const SizedBox.shrink();
    final total =
        (DateTime.parse(m.endDate)
                    .difference(DateTime.parse(m.startDate))
                    .inDays +
                1)
            .clamp(1, 100000);
    final used = m.daysLeft == null
        ? total
        : (total - m.daysLeft!).clamp(0, total);
    final a = MemberActions(context);
    Future<void> run(Future<bool> f) async {
      if (await f) await onChanged();
    }

    final tag = membershipTag(info);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.planName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Tag(tag.label, tone: tag.tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${Fmt.date(m.startDate)}  →  ${Fmt.date(m.endDate)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (m.status == 'active' || m.status == 'paused') ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: used / total,
                  minHeight: 8,
                  backgroundColor: AppColors.neutralTint,
                  color: m.status == 'paused'
                      ? AppColors.warning
                      : ((m.daysLeft ?? 0) <= 10
                            ? AppColors.warning
                            : AppColors.success),
                ),
              ),
            ],
            if (m.hasSessions) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.fitness_center,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${m.sessionsLeft ?? 0} of ${m.sessionsTotal} sessions left',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  if (canWrite && m.isActive && (m.sessionsLeft ?? 0) > 0)
                    TextButton(
                      onPressed: () => run(a.markSession(m)),
                      child: const Text('Mark Session'),
                    ),
                ],
              ),
            ],
            const Divider(height: 24),
            InfoRow('Total', Fmt.money(m.total)),
            InfoRow('Received', Fmt.money(m.amountReceived)),
            if (m.balance > 0)
              InfoRow('Balance', Fmt.money(m.balance), bold: true),
            if (m.invoiceNo != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/invoice/${m.invoiceNo}'),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('View Invoice ${m.invoiceNo}'),
                ),
              ),
            if (canWrite) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (m.status == 'active')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => run(a.freeze(m)),
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: const Text('Freeze'),
                    ),
                  if (m.status == 'paused')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => run(a.resume(m)),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Resume'),
                    ),
                  if (m.status != 'ended' && m.status != 'expired')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => run(a.extend(m)),
                      icon: const Icon(Icons.more_time, size: 18),
                      label: const Text('Extend'),
                    ),
                  if (m.status == 'active' || m.status == 'paused')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () async {
                        await context.push(
                          '/members/${detail.summary.id}/upgrade/${m.id}',
                        );
                        await onChanged();
                      },
                      icon: const Icon(Icons.upgrade, size: 18),
                      label: const Text('Upgrade'),
                    ),
                  if (m.status == 'upcoming')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => run(a.startNow(m)),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start Now'),
                    ),
                  if (m.status == 'active' ||
                      m.status == 'paused' ||
                      m.status == 'upcoming')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      onPressed: () => run(a.end(m)),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('End'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class _MembershipsTab extends StatelessWidget {
  const _MembershipsTab({
    required this.detail,
    required this.onChanged,
    required this.session,
  });
  final MemberDetail detail;
  final Future<void> Function() onChanged;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final list = detail.memberships;
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.card_membership_outlined,
        title: 'No memberships yet',
      );
    }
    final a = MemberActions(context);
    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length + (session.can(Perm.membersWrite) ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == list.length) {
            return OutlinedButton.icon(
              onPressed: () async {
                await context.push(
                  '/members/${detail.summary.id}/renew?kind=upcoming',
                );
                await onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Upcoming'),
            );
          }
          final m = list[i];
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.planName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Tag(statusTitle(m.status), tone: statusTone(m.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${Fmt.date(m.startDate)} → ${Fmt.date(m.endDate)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (m.kind == 'upgrade' && m.previousPlanName != null)
                  Text(
                    'Upgraded from ${m.previousPlanName}',
                    style: const TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                if (m.pausedDays > 0)
                  Text(
                    'Paused for ${m.pausedDays} days',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                for (final e in m.extensions)
                  Text(
                    'Extended ${e['days']} day(s) · ${Fmt.dateShort(e['at'] as String?)}${e['reason'] == null ? '' : ' · ${e['reason']}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total ${Fmt.money(m.total)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Paid ${Fmt.money(m.amountReceived)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                    if (m.balance > 0)
                      Text(
                        'Due ${Fmt.money(m.balance)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                if (m.hasSessions) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sessions: ${m.sessionLogs.length} used · ${m.sessionsLeft ?? 0} left',
                    style: const TextStyle(fontSize: 13),
                  ),
                  for (final l in m.sessionLogs.reversed.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text(Fmt.date(l['date'] as String?)),
                      subtitle: l['note'] == null ? null : Text('${l['note']}'),
                      trailing: session.can(Perm.membersWrite)
                          ? IconButton(
                              icon: const Icon(Icons.undo, size: 18),
                              tooltip: 'Unmark Session',
                              onPressed: () async {
                                if (await a.unmarkSession(m, '${l['id']}')) {
                                  await onChanged();
                                }
                              },
                            )
                          : null,
                    ),
                ],
                if (m.invoiceNo != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.push('/invoice/${m.invoiceNo}'),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(m.invoiceNo!),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class _HealthTab extends StatelessWidget {
  const _HealthTab({
    required this.detail,
    required this.onChanged,
    required this.session,
  });
  final MemberDetail detail;
  final Future<void> Function() onChanged;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    if (!session.feature(Feat.memberHealth)) {
      return const EmptyState(
        icon: Icons.favorite_outline,
        title: 'Member Health is off',
        message: 'Turn on "Member Health" under Settings > App Features.',
      );
    }
    final h = detail.health;
    final id = detail.summary.id;
    final repo = getIt<MembersRepository>();
    final canWrite = session.can(Perm.membersWrite);
    Future<void> addMeasure(String type) async {
      final label = type == 'weight'
          ? 'Enter your weight'
          : 'Enter your height';
      final v = await promptText(
        context,
        title: type == 'weight' ? 'Update weight (kg)' : 'Update height (cm)',
        hint: label,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (s) {
          final n = double.tryParse((s ?? '').trim());
          if (n == null) {
            return 'Please enter valid ${type == 'weight' ? 'weight' : 'height'}';
          }
          if (type == 'weight' && (n < 10 || n > 500)) {
            return 'Please enter a valid weight.';
          }
          if (type == 'height' && (n < 50 || n > 260)) {
            return 'Please enter a valid height.';
          }
          return null;
        },
      );
      if (v == null || !context.mounted) return;
      final r = await runWithProgress(
        context,
        () => repo.addHealth(id, type: type, value: double.parse(v)),
        success: 'Added successfully',
      );
      if (r != null) await onChanged();
    }

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'BMI Tracker',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (canWrite)
                      TextButton(
                        onPressed: () => addMeasure('weight'),
                        child: const Text('Update weight'),
                      ),
                    if (canWrite)
                      TextButton(
                        onPressed: () => addMeasure('height'),
                        child: const Text('Height'),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        'Weight',
                        h.weightKg == null ? '—' : '${h.weightKg} kg',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        'Height',
                        h.heightCm == null ? '—' : '${h.heightCm} cm',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        'Current BMI',
                        h.bmi?.toString() ?? '—',
                        sub: h.bmiCategory,
                      ),
                    ),
                  ],
                ),
                if (h.weightTrend.length >= 2) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Weight Trend',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 130,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final (i, p) in h.weightTrend.indexed)
                                FlSpot(i.toDouble(), p.value),
                            ],
                            isCurved: true,
                            color: AppColors.navy,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.navy.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SectionTitle(
            'Health Conditions',
            padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
            trailing: canWrite
                ? TextButton.icon(
                    onPressed: () => _addCondition(context, id, repo),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  )
                : null,
          ),
          if (h.conditions.isEmpty)
            const AppCard(
              child: Text(
                'No conditions recorded.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final c in h.conditions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.monitor_heart_outlined,
                        color: AppColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (c.notes != null)
                              Text(
                                c.notes!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canWrite)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Delete',
                              message: 'This action cannot be undone',
                              destructive: true,
                              confirmLabel: 'Delete',
                            );
                            if (ok) {
                              await repo.deleteCondition(id, c.id);
                              await onChanged();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
          const SectionTitle(
            'PAR-Q',
            padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
          ),
          AppCard(
            child: Row(
              children: [
                Icon(
                  detail.summary.parqSigned
                      ? Icons.verified_outlined
                      : Icons.assignment_late_outlined,
                  color: detail.summary.parqSigned
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    detail.summary.parqSigned
                        ? 'PAR-Q Signed'
                        : 'PAR-Q Not Signed',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (session.can(Perm.membersWrite) ||
                    session.can(Perm.plansetsWrite))
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(110, 40),
                    ),
                    onPressed: () async {
                      await context.push('/members/$id/parq');
                      await onChanged();
                    },
                    child: Text(
                      detail.summary.parqSigned ? 'View / Re-sign' : 'Sign Now',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCondition(
    BuildContext context,
    String id,
    MembersRepository repo,
  ) async {
    final names = await repo.healthConditionNames().catchError(
      (Object _) => <String>[],
    );
    if (!context.mounted) return;
    final picked = await showPickerSheet<String>(
      context,
      title: 'Health Conditions',
      items: [...names, 'Other…'],
      labelOf: (s) => s,
      searchable: true,
    );
    if (picked == null || !context.mounted) return;
    var name = picked;
    if (picked == 'Other…') {
      final n = await promptText(
        context,
        title: 'Add condition',
        label: 'Condition',
        hint: 'Enter name',
        required: true,
        maxLength: 80,
      );
      if (n == null) return;
      name = n;
    }
    if (!context.mounted) return;
    final notes = await promptText(
      context,
      title: name,
      label: 'Notes (optional)',
      hint: 'Add a short note',
      confirmLabel: 'Save',
      maxLength: 300,
    );
    if (notes == null || !context.mounted) return;
    final added = await runOk(
      context,
      () => repo.addCondition(id, name, notes: notes.isEmpty ? null : notes),
      success: 'Added successfully',
    );
    if (added) await onChanged();
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.sub});
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      if (sub != null)
        Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.info)),
    ],
  );
}

// ---------------------------------------------------------------------------------------------
class _PlansTab extends StatelessWidget {
  const _PlansTab({required this.detail, required this.session});
  final MemberDetail detail;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final id = detail.summary.id;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (session.feature(Feat.workout))
          _planCard(
            context,
            icon: Icons.fitness_center,
            title: 'Workout Plan',
            subtitle:
                'Create, assign or generate a training plan for ${detail.summary.name}.',
            route: '/members/$id/workout',
          ),
        if (session.feature(Feat.diet)) ...[
          const SizedBox(height: 12),
          _planCard(
            context,
            icon: Icons.restaurant_menu,
            title: 'Diet Plan',
            subtitle: 'Meal plan tailored to this member.',
            route: '/members/$id/diet',
          ),
        ],
        if (!session.feature(Feat.workout) && !session.feature(Feat.diet))
          const EmptyState(
            icon: Icons.fitness_center,
            title: 'Plans are off',
            message: 'Turn on Workout Plans or Diet Plans under Settings > App Features.',
          ),
      ],
    );
  }

  Widget _planCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) => AppCard(
    onTap: () => context.push(route),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.chip,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.navy),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------------------------
class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab({required this.detail, required this.session});
  final MemberDetail detail;
  final SessionState session;
  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  late final AsyncCubit<List<Json>> _docs = AsyncCubit(
    () => getIt<MembersRepository>().documents(widget.detail.summary.id),
  );

  @override
  void dispose() {
    _docs.close();
    super.dispose();
  }

  Future<void> _addLink() async {
    final title = await promptText(
      context,
      title: 'Add Link',
      label: 'Title',
      hint: 'Enter your title',
      required: true,
      maxLength: 100,
    );
    if (title == null || !mounted) return;
    final url = await promptText(
      context,
      title: 'Add Link',
      label: 'URL',
      hint: 'Paste the URL here',
      validator: V.url,
    );
    if (url == null || !mounted) return;
    final added = await runOk(
      context,
      () => getIt<MembersRepository>().addUrlDocument(
        widget.detail.summary.id,
        title,
        url,
      ),
      success: 'Added successfully',
    );
    if (added) _docs.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = widget.session.can(Perm.membersWrite);
    return BlocProvider.value(
      value: _docs,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: canWrite
            ? FloatingActionButton.small(
                onPressed: _addLink,
                child: const Icon(Icons.add_link),
              )
            : null,
        body: AsyncBody<List<Json>>(
          isEmpty: (d) => d.isEmpty,
          empty: const EmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No documents',
            message:
                'Add links to ID proofs, medical certificates or invoices.',
          ),
          builder: (context, docs) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.detail.idCardUrl != null)
                AppCard(
                  onTap: () => context.push(
                    '/view-photo?url=${Uri.encodeComponent(widget.detail.idCardUrl!)}',
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.badge_outlined),
                      SizedBox(width: 12),
                      Text(
                        'ID card',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppCard(
                    onTap: () {
                      if (d['type'] == 'url') {
                        Launch.url(context, '${d['url']}');
                      } else if (d['fileUrl'] != null) {
                        context.push(
                          '/view-photo?url=${Uri.encodeComponent('${d['fileUrl']}')}',
                        );
                      }
                    },
                    child: Row(
                      children: [
                        Icon(
                          d['type'] == 'url'
                              ? Icons.link
                              : Icons.insert_drive_file_outlined,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${d['title']}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        if (canWrite)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirmDialog(
                                context,
                                title: 'Delete',
                                message: 'This action cannot be undone',
                                destructive: true,
                                confirmLabel: 'Delete',
                              )) {
                                await getIt<MembersRepository>().deleteDocument(
                                  widget.detail.summary.id,
                                  '${d['id']}',
                                );
                                _docs.refresh();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
