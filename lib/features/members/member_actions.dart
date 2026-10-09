import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';

/// Membership lifecycle + money actions shared by the member detail screen and list shortcuts.
/// Every function returns true when something changed (so the caller refreshes).
class MemberActions {
  MemberActions(this.context);
  final BuildContext context;

  final _ms = getIt<MembershipsRepository>();
  final _fin = getIt<FinanceRepository>();
  final _members = getIt<MembersRepository>();

  Future<bool> extend(Membership m) async {
    final days = await promptNumber(
      context,
      title: 'Extend',
      label: 'Enter no of days',
      hint: 'Enter no of days',
      max: 365,
      confirmLabel: 'Extend',
    );
    if (days == null || !context.mounted) return false;
    final reason = await promptText(
      context,
      title: 'Reason (optional)',
      hint: 'Enter reason',
      confirmLabel: 'Done',
    );
    if (!context.mounted) return false;
    final r = await runWithProgress(
      context,
      () => _ms.extend(
        m.id,
        days,
        reason: (reason ?? '').isEmpty ? null : reason,
      ),
      success: 'Extended for $days day${days == 1 ? '' : 's'}',
    );
    return r != null;
  }

  Future<bool> freeze(Membership m) async {
    final ok = await confirmDialog(
      context,
      title: 'Freeze Membership',
      message: 'Are you sure you want to freeze this membership?',
      confirmLabel: 'Freeze',
    );
    if (!ok || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _ms.freeze(m.id),
          success: 'Membership frozen',
        ) !=
        null;
  }

  Future<bool> resume(Membership m) async {
    final r = await runWithProgress(
      context,
      () => _ms.resume(m.id),
      success: 'Membership resumed',
    );
    return r != null;
  }

  Future<bool> end(Membership m) async {
    final ok = await confirmDialog(
      context,
      title: 'End Membership',
      message: 'Are you sure you want to end this membership? This action cannot be undone.',
      confirmLabel: 'End Membership',
      destructive: true,
    );
    if (!ok || !context.mounted) return false;
    final reason = await promptText(
      context,
      title: 'Reason (optional)',
      hint: 'Enter reason',
      confirmLabel: 'Done',
    );
    if (!context.mounted) return false;
    return await runWithProgress(
          context,
          () => _ms.end(m.id, reason: (reason ?? '').isEmpty ? null : reason),
          success: 'Membership ended',
        ) !=
        null;
  }

  Future<bool> startNow(Membership m) async {
    final ok = await confirmDialog(
      context,
      title: 'Start Membership Now?',
      message: 'This action cannot be undone.',
      confirmLabel: 'Start Now',
    );
    if (!ok || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _ms.startNow(m.id),
          success: 'Membership started',
        ) !=
        null;
  }

  Future<bool> markSession(Membership m) async {
    final note = await promptText(
      context,
      title: 'Mark Session',
      label: 'Session note',
      hint: 'Add a short note',
      confirmLabel: 'Mark Session',
    );
    if (note == null || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _ms.markSession(m.id, note: note.isEmpty ? null : note),
          success: 'Session marked successfully',
        ) !=
        null;
  }

  Future<bool> unmarkSession(Membership m, String logId) async {
    final ok = await confirmDialog(
      context,
      title: 'Unmark Session',
      message: 'Do you want to delete this log?',
      confirmLabel: 'Unmark',
      destructive: true,
    );
    if (!ok || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _ms.unmarkSession(m.id, logId),
        ) !=
        null;
  }

  Future<bool> block(MemberSummary m) async {
    if (m.blocked) {
      final ok = await confirmDialog(
        context,
        title: 'Unblock Now?',
        message: 'Do you want to unblock the member?',
        confirmLabel: 'Unblock Now',
      );
      if (!ok || !context.mounted) return false;
      return await runWithProgress(
            context,
            () => _members.unblock(m.id),
            success: 'Member unblocked',
          ) !=
          null;
    }
    final reason = await promptText(
      context,
      title: 'Block Member',
      message: 'Do you want to block the member?',
      hint: 'Enter reason',
      confirmLabel: 'Block',
    );
    if (reason == null || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _members.block(m.id, reason: reason.isEmpty ? null : reason),
          success: 'Member blocked',
        ) !=
        null;
  }

  Future<bool> settle(MemberSummary m) async {
    final gym = getIt<SessionCubit>().state.profile!;
    final amount = TextEditingController(
      text: m.balance.toStringAsFixed(
        m.balance == m.balance.roundToDouble() ? 0 : 2,
      ),
    );
    var type = gym.activePaymentTypes.contains(gym.defaultPaymentType)
        ? gym.defaultPaymentType
        : gym.activePaymentTypes.first;
    final key = GlobalKey<FormState>();
    final res = await showAppSheet<Json>(
      context,
      title: 'Settle Balance',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balance due: ${Fmt.money(m.balance)}',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(16),
              AmountField(
                controller: amount,
                label: 'Amount received',
                validator: (v) => V.amount(v, max: m.balance),
              ),
              const Gap(16),
              DropdownField<String>(
                label: 'Payment type',
                value: type,
                items: gym.activePaymentTypes,
                labelOf: paymentTypeLabel,
                onChanged: (v) => set(() => type = v ?? type),
              ),
              const Gap(20),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) {
                    Navigator.pop(ctx, {
                      'amount': double.parse(amount.text.trim()),
                      'type': type,
                    });
                  }
                },
                child: const Text('Settle Balance'),
              ),
              const Gap(8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                onPressed: () => Navigator.pop(ctx, {'writeOff': true}),
                child: const Text('Write-off Balance'),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null || !context.mounted) return false;
    if (res['writeOff'] == true) {
      final ok = await confirmDialog(
        context,
        title: 'Write-off Balance?',
        message: 'Do you want to write-off the balance. This action cannot be undone',
        confirmLabel: 'Write Off',
        destructive: true,
      );
      if (!ok || !context.mounted) return false;
      return await runWithProgress(
            context,
            () => _fin.writeOff(m.id),
            success: 'Balance cleared',
          ) !=
          null;
    }
    return await runWithProgress(
          context,
          () => _fin.settle(
            m.id,
            amount: res['amount'] as double,
            paymentType: res['type'] as String,
          ),
          success: 'Payment received',
        ) !=
        null;
  }

  /// Presets match the original ("1 month / 3 days / 7 days / tomorrow") plus a custom date.
  Future<bool> setReminder(MemberSummary m) async {
    final today = DateTime.now();
    final choice = await showPickerSheet<(String, DateTime?)>(
      context,
      title: 'Set a Balance Reminder',
      items: [
        ('Tomorrow', today.add(const Duration(days: 1))),
        ('In 3 days', today.add(const Duration(days: 3))),
        ('In 7 days', today.add(const Duration(days: 7))),
        ('In 1 month', DateTime(today.year, today.month + 1, today.day)),
        ('Custom date', null),
      ],
      labelOf: (e) => e.$1,
      subtitleOf: (e) =>
          e.$2 == null ? 'Pick any date' : Fmt.date(Fmt.ymd(e.$2!)),
    );
    if (choice == null || !context.mounted) return false;
    var date = choice.$2;
    if (date == null) {
      date = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
      );
      if (date == null) return false;
    }
    final picked = date;
    if (!context.mounted) return false;
    return runOk(
      context,
      () => _fin.createReminder(m.id, Fmt.ymd(picked)),
      success: 'Balance Reminder created successfully.',
    );
  }

  Future<bool> editLabels(MemberSummary m) async {
    final all = await _members.labels();
    if (!context.mounted) return false;
    final sel = {...m.labels.map((l) => l.id)};
    final res = await showAppSheet<Set<String>>(
      context,
      title: 'Assign Labels',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (all.isEmpty)
              const Text(
                'No labels yet. Create one below.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final l in all)
                  PillChip(
                    label: l.name,
                    selected: sel.contains(l.id),
                    onTap: () => set(
                      () =>
                          sel.contains(l.id) ? sel.remove(l.id) : sel.add(l.id),
                    ),
                  ),
              ],
            ),
            const Gap(12),
            TextButton.icon(
              onPressed: () async {
                final name = await promptText(
                  ctx,
                  title: 'Add new label',
                  label: 'Label name',
                  hint: 'Enter name',
                  required: true,
                  maxLength: 40,
                );
                if (name == null) return;
                try {
                  final l = await _members.createLabel(name);
                  set(() {
                    all.add(l);
                    sel.add(l.id);
                  });
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add new label'),
            ),
            const Gap(8),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, sel),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (res == null || !context.mounted) return false;
    return await runWithProgress(
          context,
          () => _members.setLabels(m.id, res.toList()),
          success: 'Edited successfully',
        ) !=
        null;
  }

  Future<bool> assignTrainer(MemberSummary m) async {
    final trainers = await getIt<StaffRepository>().trainers();
    if (!context.mounted) return false;
    if (trainers.isEmpty) {
      showToast(context, 'Failed to load trainers', error: true);
      return false;
    }
    // Records distinguish "chose Unassign" from "dismissed the sheet" (null).
    final choice = await showPickerSheet<({StaffMember? t})>(
      context,
      title: 'Select Trainer',
      items: [(t: null), for (final t in trainers) (t: t)],
      selected: (t: trainers.where((t) => t.userId == m.trainerId).firstOrNull),
      labelOf: (c) => c.t?.name ?? 'Unassign Trainer',
      subtitleOf: (c) => c.t == null ? '' : '${c.t!.memberCount ?? 0} members',
    );
    if (choice == null || !context.mounted) return false;
    final picked = choice.t;
    if (picked == null && m.trainerId == null) return false;
    final r = await runWithProgress(
      context,
      () => _members.setTrainer(m.id, picked?.userId),
      success: picked == null
          ? 'Trainer unassigned successfully'
          : 'Trainer assigned successfully',
    );
    return r != null;
  }

  Future<void> copyToClipboard(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showToast(context, toast);
  }
}
