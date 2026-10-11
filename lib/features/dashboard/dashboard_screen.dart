import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/dashboard.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/dashboard_repository.dart';
import 'dashboard_cubit.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = getIt<SessionCubit>();
    return BlocProvider<DashboardCubit>(
      key: ValueKey(
        '${session.state.profile?.id}-${session.state.feature(Feat.attendance)}',
      ),
      create: (_) => DashboardCubit(
        getIt<DashboardRepository>(),
        wantsInsights:
            session.state.feature(Feat.aiInsights) &&
            session.state.can(Perm.reportsRead),
        wantsAttendance:
            session.state.feature(Feat.attendance) &&
            session.state.can(Perm.attendanceRead),
      ),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      bloc: getIt<SessionCubit>(),
      builder: (context, s) {
        final gym = s.profile;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: InkWell(
              onTap: () => context.push('/gym-selection'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(
                    name: gym?.name ?? '',
                    url: gym?.logoUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gym?.name ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${roleLabel(s.role)} · Code ${gym?.code ?? ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 20),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => context.read<DashboardCubit>().refresh(),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Need Help?',
                onPressed: () => context.push('/settings/support'),
              ),
            ],
          ),
          floatingActionButton: s.role == 'trainer'
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _quickActions(context, s),
                  icon: const Icon(Icons.add),
                  label: Text('Quick Actions'.tr),
                ),
          body: AsyncBody<HomeData>(
            cubit: context.read<DashboardCubit>(),
            builder: (context, d) => _Body(data: d, session: s),
          ),
        );
      },
    );
  }

  void _quickActions(BuildContext context, SessionState s) {
    final items = <(IconData, String, String, bool)>[
      (
        Icons.person_add_alt_1,
        'Add new member',
        '/members/new',
        s.can(Perm.membersWrite),
      ),
      (
        Icons.event_repeat,
        'Create a plan',
        '/plans/new',
        s.can(Perm.plansWrite),
      ),
      (
        Icons.how_to_reg,
        'Mark attendance',
        '/attendance',
        s.can(Perm.attendanceWrite) && s.feature(Feat.attendance),
      ),
      (
        Icons.contact_phone_outlined,
        'Add Lead Member',
        '/leads/new',
        s.can(Perm.leadsWrite),
      ),
      (
        Icons.shopping_bag_outlined,
        'Create Sale',
        '/sales/new',
        s.can(Perm.productsWrite) && s.feature(Feat.sales),
      ),
      (
        Icons.receipt_long_outlined,
        'Create Expense',
        '/expenses/new',
        s.can(Perm.expensesWrite) && s.feature(Feat.sales),
      ),
      (
        Icons.inbox_outlined,
        'Member requests',
        '/membership-requests',
        s.can(Perm.requestsRead),
      ),
      (
        Icons.qr_code_scanner,
        'Scan member QR',
        '/attendance/scan',
        s.can(Perm.attendanceWrite) && s.feature(Feat.attendance),
      ),
    ].where((e) => e.$4).toList();
    showAppSheet<void>(
      context,
      title: 'Quick Actions'.tr,
      builder: (ctx) => Column(
        children: [
          for (final it in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(it.$1, color: AppColors.navy),
              ),
              title: Text(
                it.$2.tr,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                context.push(it.$3);
              },
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data, required this.session});
  final HomeData data;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final d = data.summary;
    final s = session;
    final gym = s.profile!;
    return RefreshIndicator(
      onRefresh: () => context.read<DashboardCubit>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          if (gym.subscription?.plan == 'TRIAL' && d.subscriptionDaysLeft != null && !d.subscriptionExpired)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                color: AppColors.info.withValues(alpha: 0.14),
                onTap: () => context.push('/settings/subscription'),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: AppColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Free trial: ${d.subscriptionDaysLeft} day${d.subscriptionDaysLeft == 1 ? '' : 's'} left. Tap to see plans.',
                        style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.info),
                  ],
                ),
              ),
            )
          else if (d.subscriptionDaysLeft != null &&
              d.subscriptionDaysLeft! <= 7 &&
              !d.subscriptionExpired)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                color: AppColors.warningTint,
                onTap: () => context.push('/settings/subscription'),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your Subscription will expire soon. ${d.subscriptionDaysLeft} day${d.subscriptionDaysLeft == 1 ? '' : 's'} left.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      'Renew Now',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!gym.onboardingCompleted && d.allMembers == 0)
            _OnboardingCard(session: s),
          // KPI tiles
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: [
              StatTile(
                label: 'Active Members'.tr,
                value: '${d.activeMembers}',
                icon: Icons.people_alt_outlined,
                tone: Tone.success,
                onTap: s.can(Perm.membersRead)
                    ? () => context.go('/members?status=active')
                    : null,
              ),
              StatTile(
                label: 'All Members'.tr,
                value: '${d.allMembers}',
                icon: Icons.groups_2_outlined,
                onTap: s.can(Perm.membersRead)
                    ? () => context.go('/members')
                    : null,
              ),
              if (d.atRisk != null)
                StatTile(
                  label: 'At-risk members'.tr,
                  value: '${d.atRisk}',
                  icon: Icons.trending_down,
                  tone: Tone.danger,
                  onTap: () => context.push('/members/at-risk'),
                ),
              StatTile(
                label: 'Expiring in 10 days',
                value: '${d.expiring10}',
                icon: Icons.hourglass_bottom,
                tone: Tone.warning,
                onTap: s.can(Perm.membersRead)
                    ? () => context.go('/members?status=expiring10')
                    : null,
              ),
              StatTile(
                label: 'Expiring in 30 days',
                value: '${d.expiring30}',
                icon: Icons.event_busy_outlined,
                tone: Tone.warning,
                onTap: s.can(Perm.membersRead)
                    ? () => context.go('/members?status=expiring30')
                    : null,
              ),
              if (s.can(Perm.leadsRead))
                StatTile(
                  label: "Today's Leads".tr,
                  value: '${d.leadsToday}',
                  caption: '${d.leadsTotal} total',
                  icon: Icons.contact_phone_outlined,
                  tone: Tone.info,
                  onTap: () => context.push('/leads'),
                ),
            ],
          ),
          if (s.can(Perm.attendanceRead) && s.feature(Feat.membersInGym))
            _LiveCard(
              o: d.occupancy,
              onDevices: s.can(Perm.devicesRead) && s.feature(Feat.biometrics)
                  ? () => context.push('/biometrics')
                  : null,
            ),
          if (s.can(Perm.attendanceRead) && s.feature(Feat.attendance))
            _AttendanceCard(
              data: data,
              onOpen: () => context.push('/attendance'),
            ),
          if (s.can(Perm.financeRead) && d.balanceTotal > 0) _BalanceCard(d: d),
          if (d.reminders.isNotEmpty && s.can(Perm.financeRead))
            _RemindersCard(items: d.reminders, gym: gym.name),
          if (d.birthdays.isNotEmpty)
            _BirthdaysCard(items: d.birthdays, gym: gym.name),
          if (s.feature(Feat.quickReports) && s.can(Perm.reportsRead))
            const _QuickReportCard(),
          if (data.insights.isNotEmpty) _InsightsCard(items: data.insights),
          if (s.feature(Feat.whatsapp) && s.can(Perm.broadcastsRead))
            _CreditsCard(d: d),
        ],
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.session});
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Let's finish setting up",
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Plans hold your price and duration. Members get assigned to them.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => context.push('/plans/new'),
                    icon: const Icon(Icons.event_repeat, size: 18),
                    label: const Text('Create plan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => context.push('/members/new'),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Add member'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.action,
    this.onAction,
    this.icon,
  });
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (action != null)
                GestureDetector(
                  onTap: onAction,
                  child: Text(
                    action!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.info,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.o, this.onDevices});
  final OccupancySnapshot o;
  final VoidCallback? onDevices;

  @override
  Widget build(BuildContext context) {
    final peak = o.peakHour == null
        ? null
        : '${Fmt.hhmm('${o.peakHour.toString().padLeft(2, '0')}:00')} (${o.peakCheckIns} check-ins)';
    return _Section(
      title: 'MEMBERS IN GYM',
      icon: Icons.sensors,
      action: o.hasDevice ? null : 'Add device',
      onAction: onDevices,
      child: Row(
        children: [
          Text(
            '${o.liveCount}',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: o.liveCount > 0
                            ? AppColors.success
                            : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      o.liveCount > 0 ? 'Live now' : 'No one checked in',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${o.todayCount} check-ins today',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (peak != null)
                  Text(
                    'PEAK TODAY  $peak',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                if (!o.hasDevice)
                  Text(
                    'No biometric device: counts include manual and QR check-ins',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatefulWidget {
  const _AttendanceCard({required this.data, required this.onOpen});
  final HomeData data;
  final VoidCallback onOpen;
  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard> {
  int _mode = 1; // 0 today, 1 week, 2 month

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final series = _mode == 2 ? d.month : d.week;
    final total = switch (_mode) {
      0 => d.summary.attendanceToday,
      1 => d.summary.attendanceWeek,
      _ => d.summary.attendanceMonth,
    };
    final max = series
        .fold<int>(1, (m, e) => e.count > m ? e.count : m)
        .toDouble();
    return _Section(
      title: 'Attendance'.tr,
      icon: Icons.how_to_reg_outlined,
      action: 'See Attendance Logs',
      onAction: widget.onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (i, l) in ['Today', 'This Week', 'This Month'].indexed)
                PillChip(
                  label: l,
                  selected: _mode == i,
                  onTap: () => setState(() => _mode = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$total',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          Text(
            'check-ins',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (_mode != 0 && series.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  maxY: max * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= series.length) {
                            return const SizedBox.shrink();
                          }
                          if (_mode == 2 && i % 5 != 0) {
                            return const SizedBox.shrink();
                          }
                          final dt = DateTime.parse(series[i].date);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _mode == 2
                                  ? '${dt.day}'
                                  : [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ][(dt.weekday - 1) % 7],
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final (i, e) in series.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: e.count.toDouble(),
                            width: _mode == 2 ? 5 : 14,
                            color: e.date == d.summary.today
                                ? AppColors.navy
                                : AppColors.textMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
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
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.d});
  final DashboardSummary d;
  @override
  Widget build(BuildContext context) => _Section(
    title: 'Members with balance'.tr,
    icon: Icons.account_balance_wallet_outlined,
    action: 'See all',
    onAction: () => context.push('/transactions/balance'),
    child: Row(
      children: [
        Text(
          Fmt.money(d.balanceTotal),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'from ${Fmt.plural(d.balanceMembers, 'member')}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    ),
  );
}

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.items, required this.gym});
  final List<ReminderItem> items;
  final String gym;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Balance reminders',
    icon: Icons.notifications_active_outlined,
    action: 'See all',
    onAction: () => context.push('/transactions/reminders'),
    child: Column(
      children: [
        for (final r in items.take(3))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.warningTint,
              child: Icon(
                Icons.currency_rupee,
                size: 18,
                color: AppColors.warning,
              ),
            ),
            title: Text(
              r.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${Fmt.money(r.balance)} due · ${r.reminderDate == '' ? '' : Fmt.date(r.reminderDate)}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: Icon(Icons.chat_outlined, color: AppColors.success),
              tooltip: 'Send Balance Reminder',
              onPressed: () => Launch.whatsApp(
                context,
                r.phone,
                text:
                    'Hi ${r.name}, a balance of ${Fmt.money(r.balance)} is pending at $gym. Please clear it at your earliest.',
              ),
            ),
            onTap: () => context.push('/members/${r.memberId}'),
          ),
      ],
    ),
  );
}

class _BirthdaysCard extends StatelessWidget {
  const _BirthdaysCard({required this.items, required this.gym});
  final List<BirthdayItem> items;
  final String gym;
  @override
  Widget build(BuildContext context) => _Section(
    title: 'Birthdays Today'.tr,
    icon: Icons.cake_outlined,
    child: Column(
      children: [
        for (final b in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: UserAvatar(name: b.name, url: b.photoUrl, radius: 18),
            title: Text(
              b.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: b.age == null ? null : Text('Turns ${b.age}'),
            trailing: IconButton(
              icon: Icon(Icons.cake, color: AppColors.warning),
              tooltip: 'Send Birthday Message?',
              onPressed: () => Launch.whatsApp(
                context,
                b.phone,
                text:
                    'Happy Birthday ${b.name}! Team $gym wishes you a fit and healthy year.',
              ),
            ),
            onTap: () => context.push('/members/${b.id}'),
          ),
      ],
    ),
  );
}

class _QuickReportCard extends StatelessWidget {
  const _QuickReportCard();
  @override
  Widget build(BuildContext context) {
    return BlocProvider<AsyncCubit<QuickReport>>(
      create: (_) =>
          AsyncCubit<QuickReport>(() => getIt<DashboardRepository>().report()),
      child: BlocBuilder<AsyncCubit<QuickReport>, AsyncState<QuickReport>>(
        builder: (context, s) {
          final r = s.data;
          return _Section(
            title: 'Quick Reports'.tr,
            icon: Icons.insights_outlined,
            action: 'Explore reports',
            onAction: () => context.go('/reports'),
            child: r == null
                ? (s.isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          'Reports unavailable right now',
                          style: TextStyle(color: AppColors.textSecondary),
                        ))
                : Row(
                    children: [
                      Expanded(
                        child: _Kpi(
                          'Revenue',
                          Fmt.money(r.revenue, compact: true),
                          AppColors.success,
                        ),
                      ),
                      Expanded(
                        child: _Kpi(
                          'Expenses',
                          Fmt.money(r.expenses, compact: true),
                          AppColors.danger,
                        ),
                      ),
                      Expanded(
                        child: _Kpi(
                          'Net',
                          Fmt.money(r.net, compact: true),
                          r.net >= 0 ? AppColors.navy : AppColors.danger,
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

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      Text(
        label,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    ],
  );
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.items});
  final List<Insight> items;
  @override
  Widget build(BuildContext context) => _Section(
    title: 'AI Insights'.tr,
    icon: Icons.auto_awesome,
    child: Column(
      children: [
        for (final i in items.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  i.severity == 'warning'
                      ? Icons.warning_amber_rounded
                      : Icons.lightbulb_outline,
                  size: 18,
                  color: i.severity == 'warning'
                      ? AppColors.warning
                      : AppColors.info,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        i.detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text(
          'Rule-based insights computed from your data.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard({required this.d});
  final DashboardSummary d;
  @override
  Widget build(BuildContext context) {
    final low = d.credits < 50;
    return _Section(
      title: 'Your credits'.tr,
      icon: Icons.chat_bubble_outline,
      action: low ? 'Recharge now' : 'Details',
      onAction: () => context.push('/credits'),
      child: Row(
        children: [
          Text(
            '${d.credits}',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: low ? AppColors.danger : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              d.whatsappEnabled
                  ? (low ? 'Credits left - low balance' : 'Credits left')
                  : 'WhatsApp integration is off',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
