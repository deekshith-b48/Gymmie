import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/period_filter.dart';
import '../../core/widgets/states.dart';
import '../../data/models/dashboard.dart';
import '../../data/models/finance.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/dashboard_repository.dart';

/// Reports tab ("Quick Reports"): revenue, expenses and breakdowns for a chosen period.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  PeriodSel _period = PeriodSel.thisMonth;
  late AsyncCubit<QuickReport> _cubit = _make();

  AsyncCubit<QuickReport> _make() => AsyncCubit(
    () => getIt<DashboardRepository>().report(
      period: _period.key,
      from: _period.from,
      to: _period.to,
    ),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    if (!s.feature(Feat.quickReports)) {
      return Scaffold(
        appBar: AppBar(title: Text('Reports'.tr)),
        body: const EmptyState(
          icon: Icons.insights_outlined,
          title: 'Quick Reports is off',
          message: 'Turn it on under Settings > App Features.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Reports'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule_send_outlined),
            tooltip: 'Report schedule',
            onPressed: () => context.push('/settings/report-schedule'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  PeriodButton(
                    value: _period,
                    allowAll: false,
                    onChanged: (p) {
                      setState(() {
                        _period = p;
                        _cubit.close();
                        _cubit = _make();
                      });
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<QuickReport>(
                key: ValueKey(_cubit),
                cubit: _cubit,
                builder: (context, r) => _Content(r: r, period: _period),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.r, required this.period});
  final QuickReport r;
  final PeriodSel period;

  String _delta(double now, double before) {
    if (before == 0) return now == 0 ? 'no change' : 'new';
    final p = ((now - before) / before * 100).round();
    return '${p >= 0 ? '+' : ''}$p% vs previous';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Text(
          '${Fmt.date(r.from)} – ${Fmt.date(r.to)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Revenue',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              Text(
                Fmt.money(r.revenue),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _delta(r.revenue, r.prevRevenue),
                style: TextStyle(
                  fontSize: 12,
                  color: r.revenue >= r.prevRevenue
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Total Revenue breaks down memberships, sales, and expenses.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _Mini(
                      'Memberships',
                      Fmt.money(r.membershipRevenue, compact: true),
                      AppColors.info,
                    ),
                  ),
                  Expanded(
                    child: _Mini(
                      'Sales',
                      Fmt.money(r.salesRevenue, compact: true),
                      AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: _Mini(
                      'Expenses',
                      Fmt.money(r.expenses, compact: true),
                      AppColors.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Net Month'.replaceFirst('Month', 'profit'),
                value: Fmt.money(r.net, compact: true),
                icon: Icons.trending_up,
                tone: r.net >= 0 ? Tone.success : Tone.danger,
                caption: _delta(r.net, r.prevNet),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: 'New members',
                value: '${r.newMembers}',
                icon: Icons.person_add_alt_1_outlined,
                caption: _delta(
                  r.newMembers.toDouble(),
                  r.prevNewMembers.toDouble(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StatTile(
          label: 'Outstanding balance (all time)',
          value: Fmt.money(r.outstanding),
          icon: Icons.account_balance_wallet_outlined,
          tone: Tone.danger,
          onTap: () => context.push('/transactions/balance'),
        ),
        if (r.revenue > 0) _Pie(r: r),
        _Breakdown(
          title: 'Membership By Plans',
          rows: [
            for (final p in r.byPlan)
              (
                label: '${p['plan']}',
                value: (p['revenue'] as num).toDouble(),
                sub: '${p['count']} sold',
              ),
          ],
          color: AppColors.info,
        ),
        _Breakdown(
          title: 'Sales by product',
          rows: [
            for (final p in r.byProduct)
              (
                label: '${p['product']}',
                value: (p['revenue'] as num).toDouble(),
                sub: '${p['units']} units',
              ),
          ],
          color: AppColors.success,
        ),
        _Breakdown(
          title: 'Expenses by types',
          rows: [
            for (final p in r.byCategory)
              (
                label: '${p['category']}',
                value: (p['amount'] as num).toDouble(),
                sub: null,
              ),
          ],
          color: AppColors.danger,
        ),
        _Breakdown(
          title: 'Payment methods',
          rows: [
            for (final p in r.byPayment)
              (
                label: paymentTypeLabel('${p['paymentType']}'),
                value: (p['amount'] as num).toDouble(),
                sub: null,
              ),
          ],
          color: AppColors.navy,
        ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _Pie extends StatelessWidget {
  const _Pie({required this.r});
  final QuickReport r;
  @override
  Widget build(BuildContext context) {
    final parts = [
      (r.membershipRevenue, AppColors.info),
      (r.salesRevenue, AppColors.success),
    ].where((e) => e.$1 > 0).toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 32,
                  sections: [
                    for (final p in parts)
                      PieChartSectionData(
                        value: p.$1,
                        color: p.$2,
                        radius: 24,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revenue mix',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _Legend(
                    'Memberships',
                    r.membershipRevenue / r.revenue,
                    AppColors.info,
                  ),
                  _Legend(
                    'Product sales',
                    r.salesRevenue / r.revenue,
                    AppColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.share, this.color);
  final String label;
  final double share;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(
          '${(share * 100).round()}%',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.rows,
    required this.color,
  });
  final String title;
  final List<({String label, double value, String? sub})> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows
        .map((e) => e.value)
        .fold<double>(1, (a, b) => b > a ? b : a);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 10),
            for (final e in rows.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (e.sub != null)
                          Text(
                            '${e.sub}  ',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        Text(
                          Fmt.money(e.value),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 6,
                        backgroundColor: AppColors.neutralTint,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
