import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../members/member_actions.dart';

/// "Members with balance": outstanding dues, with settle / remind shortcuts.
class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key});
  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  late final AsyncCubit<BalanceSummary> _cubit = AsyncCubit(
    () => getIt<FinanceRepository>().balance(),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _settle(BalanceItem b) async {
    final detail = await runWithProgress(
      context,
      () => getIt<MembersRepository>().detail(b.memberId),
    );
    if (detail == null || !mounted) return;
    if (await MemberActions(context).settle(detail.summary)) _cubit.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final gym = s.profile?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Members with Balance')),
      body: AsyncBody<BalanceSummary>(
        cubit: _cubit,
        isEmpty: (d) => d.items.isEmpty,
        empty: const EmptyState(
          icon: Icons.verified_outlined,
          title: 'No outstanding dues',
          message: 'Everyone is paid up.',
        ),
        builder: (context, d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              color: AppColors.dangerTint,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All Time Balance',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          Fmt.money(d.total),
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${d.members} members',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final b in d.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => context.push('/members/${b.memberId}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  b.phone,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Fmt.money(b.balance),
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (b.oldestDueDate != null)
                            Tag(
                              'Due since ${Fmt.dateShort(b.oldestDueDate)}',
                              tone: Tone.warning,
                            ),
                          if (b.reminderDate != null)
                            Tag(
                              'Reminder ${Fmt.dateShort(b.reminderDate)}',
                              tone: Tone.info,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => Launch.whatsApp(
                              context,
                              b.phone,
                              text:
                                  'Hi ${b.name}, a balance of ${Fmt.money(b.balance)} is pending at $gym. Please clear it at your earliest.',
                            ),
                            icon: const Icon(Icons.chat_outlined, size: 18),
                            label: const Text('Remind'),
                          ),
                          if (s.can(Perm.financeWrite))
                            TextButton.icon(
                              onPressed: () => _settle(b),
                              icon: const Icon(
                                Icons.payments_outlined,
                                size: 18,
                              ),
                              label: const Text('Settle'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Balance reminder list: due / overdue / upcoming + done.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _repo = getIt<FinanceRepository>();
  late final AsyncCubit<List<BalanceReminder>> _cubit = AsyncCubit(
    () => _repo.reminders(),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gym = getIt<SessionCubit>().state.profile?.name ?? '';
    final canWrite = getIt<SessionCubit>().state.can(Perm.financeWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Balance reminders')),
      body: AsyncBody<List<BalanceReminder>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          icon: Icons.notifications_none,
          title: 'No reminders',
          message: 'Set a reminder from a member with a pending balance to get alerted later.',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = list[i];
            return AppCard(
              onTap: () => context.push('/members/${r.memberId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Tag(
                        r.overdue
                            ? 'Overdue ${Fmt.dateShort(r.reminderDate)}'
                            : Fmt.date(r.reminderDate),
                        tone: r.overdue ? Tone.danger : Tone.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Balance ${Fmt.money(r.balance)}',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (r.overdue)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Biometric check-in is blocked until this is cleared.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Launch.whatsApp(
                          context,
                          r.phone,
                          text:
                              'Hi ${r.name}, a balance of ${Fmt.money(r.balance)} is pending at $gym.',
                        ),
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('Send Reminder'),
                      ),
                      if (canWrite)
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Mark as Done',
                              message: 'Mark this balance reminder as done? You can set a new reminder later if the member still has a pending balance.',
                              confirmLabel: 'Mark as Done',
                            );
                            if (!ok || !context.mounted) return;
                            if (await runOk(
                              context,
                              () => _repo.markReminderDone(r.id),
                              success: 'Reminder marked as done successfully.',
                            )) {
                              _cubit.refresh();
                            }
                          },
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Done'),
                        ),
                      if (canWrite)
                        TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 1),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (d == null || !context.mounted) return;
                            if (await runOk(
                              context,
                              () =>
                                  _repo.updateReminder(r.id, date: Fmt.ymd(d)),
                              success: 'Balance Reminder updated successfully.',
                            )) {
                              _cubit.refresh();
                            }
                          },
                          child: const Text('Reschedule'),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
