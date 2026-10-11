import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/list_toolbar.dart';
import '../../core/widgets/period_filter.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';

Tone _kindTone(String k) => switch (k) {
  'membership' => Tone.info,
  'sale' => Tone.success,
  'settlement' => Tone.warning,
  _ => Tone.neutral,
};

/// Transactions tab: every payment received (memberships, sales, settlements, write-offs).
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.memberId});
  final String? memberId;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late final PagedCubit<Txn> _cubit;
  PeriodSel _period = PeriodSel.thisMonth;
  String? _kind;
  String? _payType;

  @override
  void initState() {
    super.initState();
    final repo = getIt<FinanceRepository>();
    _cubit = PagedCubit<Txn>(
      fetch: repo.transactions,
      parse: Txn.fromJson,
      query: {
        ..._period.query,
        if (widget.memberId != null) 'memberId': widget.memberId,
      },
    );
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Map<String, dynamic> get _q => {
    ..._period.query,
    if (_kind != null) 'kind': _kind,
    if (_payType != null) 'paymentType': _payType,
    if (widget.memberId != null) 'memberId': widget.memberId,
    if (_cubit.query['q'] != null) 'q': _cubit.query['q'],
  };

  Future<void> _filter() async {
    var kind = _kind;
    var pay = _payType;
    final res = await showFilterSheet<(String?, String?)>(
      context,
      title: 'Filter',
      onReset: () {
        kind = null;
        pay = null;
      },
      onSave: () => (kind, pay),
      body: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChoiceGroup<String?>(
            title: 'Transaction Type',
            options: const [
              null,
              'membership',
              'sale',
              'settlement',
              'writeoff',
            ],
            value: kind,
            labelOf: (k) => switch (k) {
              null => 'All',
              'membership' => 'Membership',
              'sale' => 'Product Sale',
              'settlement' => 'Balance Settlement',
              _ => 'Write-off',
            },
            onChanged: (v) => set(() => kind = v),
          ),
          ChoiceGroup<String?>(
            title: 'Payment Type',
            options: [null, ...allPaymentTypes],
            value: pay,
            labelOf: (k) => k == null ? 'All' : paymentTypeLabel(k),
            onChanged: (v) => set(() => pay = v),
          ),
        ],
      ),
    );
    if (res != null) {
      setState(() {
        _kind = res.$1;
        _payType = res.$2;
      });
      await _cubit.setQuery(_q);
    }
  }

  Future<void> _export() async {
    final ok = await confirmDialog(
      context,
      title: 'Export Transactions',
      message:
          'Are you sure you want to export transactions from ${_period.label}?',
      confirmLabel: 'Export',
    );
    if (!ok || !mounted) return;
    final bytes = await runWithProgress(
      context,
      () => getIt<FinanceRepository>().exportTransactions(_q),
    );
    if (bytes != null && mounted) {
      await shareBytes(
        context,
        bytes,
        'transactions-${_period.key}.csv',
        'text/csv',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.memberId != null ? 'Member Transactions' : 'Transactions'.tr,
        ),
        actions: [
          if (widget.memberId == null)
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: 'Members with Balance',
              onPressed: () => context.push('/transactions/balance'),
            ),
          if (widget.memberId == null)
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Balance reminders',
              onPressed: () => context.push('/transactions/reminders'),
            ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Transactions',
            onPressed: _export,
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<PagedCubit<Txn>, PagedState<Txn>>(
          bloc: _cubit,
          builder: (context, st) {
            final total = (st.meta['totalAmount'] as num?)?.toDouble();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ListToolbar(
                    hint: 'Name or Phone number',
                    initialQuery: (_cubit.query['q'] as String?) ?? '',
                    onSearch: (v) => _cubit.updateQuery({'q': v}),
                    onFilter: _filter,
                    filterActive: _kind != null || _payType != null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      PeriodButton(
                        value: _period,
                        onChanged: (p) {
                          setState(() => _period = p);
                          _cubit.setQuery(_q);
                        },
                      ),
                      const Spacer(),
                      if (total != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Fmt.money(total),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                            Text(
                              '${st.total} transactions',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PagedListBody<Txn>(
                    cubit: _cubit,
                    separator: 10,
                    empty: const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions',
                      message: 'Choose "This Month" to view this month\'s transactions.',
                    ),
                    itemBuilder: (context, t) => _TxnCard(
                      txn: t,
                      canDelete:
                          s.can(Perm.financeWrite) &&
                          (s.role == 'owner' || s.role == 'manager'),
                      onChanged: _cubit.reload,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TxnCard extends StatelessWidget {
  const _TxnCard({
    required this.txn,
    required this.canDelete,
    required this.onChanged,
  });
  final Txn txn;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = txn;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _details(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.memberName ?? 'Walk-in customer',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.description ?? t.kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Tag(t.kindLabel, tone: _kindTone(t.kind)),
                    Tag(paymentTypeLabel(t.paymentType)),
                    Tag(Fmt.dateShort(t.date)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Fmt.money(t.amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.isWriteOff ? AppColors.textMuted : AppColors.success,
              decoration: t.isWriteOff ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  void _details(BuildContext context) {
    final t = txn;
    showAppSheet<void>(
      context,
      title: 'Transaction',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow('Amount', Fmt.money(t.amount), bold: true),
          InfoRow('Type', t.kindLabel),
          InfoRow('Member', t.memberName),
          InfoRow('Description', t.description),
          InfoRow('Payment type', paymentTypeLabel(t.paymentType)),
          InfoRow('Date', Fmt.date(t.date)),
          InfoRow('Received by', t.createdByName),
          InfoRow('Invoice no', t.invoiceNo),
          if (t.notes != null) InfoRow('Notes', t.notes),
          const SizedBox(height: 12),
          if (t.invoiceNo != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/invoice/${t.invoiceNo}');
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View Invoice'),
            ),
          if (t.memberId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/members/${t.memberId}');
              },
              child: const Text('Go to Member Profile'),
            ),
          if (canDelete)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                final ok = await confirmDialog(
                  ctx,
                  title: 'Delete Transaction',
                  message: 'Do you want to delete the transaction. This action cannot be undone',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!ok || !ctx.mounted) return;
                final done = await runOk(
                  ctx,
                  () => getIt<FinanceRepository>().deleteTransaction(t.id),
                  success: 'Transaction deleted',
                );
                if (done) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  onChanged();
                }
              },
              child: const Text('Delete Transaction'),
            ),
        ],
      ),
    );
  }
}
