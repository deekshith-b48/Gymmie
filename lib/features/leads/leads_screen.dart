import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/files.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/list_toolbar.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/leads.dart';
import '../../data/repositories/leads_repository.dart';

const _sorts = <String, String>{
  'createdAtAsc': 'Created at - Asc',
  'createdAtDesc': 'Created at - Desc',
  'nameAsc': 'Name (A-Z)',
  'nameDesc': 'Name (Z-A)',
  'chanceOfJoiningAsc': 'Chance of joining - Asc',
  'chanceOfJoiningDesc': 'Chance of joining - Desc',
  'followupDateAsc': 'Follow up date - Asc',
  'followupDateDesc': 'Follow up date - Desc',
};
const _followUps = <String, String>{
  'all': 'All',
  'today': 'Today',
  'overdue': 'Overdue',
  'nextMonday': 'Next Monday',
  'nextMonth': 'Next Month',
};

Tone chanceTone(String c) => switch (c) {
  'High' => Tone.success,
  'Medium' => Tone.warning,
  _ => Tone.neutral,
};

/// "Potential Leads" (route /lead-member-list). Layout, chips and filter options follow the
/// the empty state and list layout of the leads screen.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key});
  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final _repo = getIt<LeadsRepository>();
  late final PagedCubit<Lead> _cubit = PagedCubit<Lead>(
    fetch: _repo.list,
    parse: Lead.fromJson,
    query: {'sort': 'createdAtDesc', 'status': 'active'},
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  List<String> _labels(Json q) => [
    'Sort by: ${_sorts[q['sort'] ?? 'createdAtDesc']}',
    if (q['followUp'] != null && q['followUp'] != 'all')
      'Follow Up: ${_followUps[q['followUp']]}',
    if (q['source'] != null) 'Referral: ${q['source']}',
    if (q['chance'] != null) 'Chance: ${q['chance']}',
    'Status: ${q['status'] == 'disabled'
        ? 'Disabled'
        : q['status'] == 'all'
        ? 'All'
        : 'Active'}',
  ];

  Future<void> _filter() async {
    final q = _cubit.query;
    var sort = q['sort'] as String? ?? 'createdAtDesc';
    var follow = q['followUp'] as String? ?? 'all';
    var source = q['source'] as String?;
    var chance = q['chance'] as String?;
    var status = q['status'] as String? ?? 'active';
    final res = await showFilterSheet<Json>(
      context,
      title: 'Filter',
      onReset: () {
        sort = 'createdAtDesc';
        follow = 'all';
        source = null;
        chance = null;
        status = 'active';
      },
      onSave: () => {
        'sort': sort,
        'followUp': follow == 'all' ? null : follow,
        'source': source,
        'chance': chance,
        'status': status,
        'q': q['q'],
      },
      body: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChoiceGroup<String>(
            title: 'Sort by',
            options: _sorts.keys.toList(),
            value: sort,
            labelOf: (k) => _sorts[k]!,
            onChanged: (v) => set(() => sort = v),
          ),
          ChoiceGroup<String>(
            title: 'Follow up',
            options: _followUps.keys.toList(),
            value: follow,
            labelOf: (k) => _followUps[k]!,
            onChanged: (v) => set(() => follow = v),
          ),
          ChoiceGroup<String?>(
            title: 'Referral',
            options: [null, ...leadSources],
            value: source,
            labelOf: (k) => k ?? 'All',
            onChanged: (v) => set(() => source = v),
          ),
          ChoiceGroup<String?>(
            title: 'Chance of Joining',
            options: [null, ...leadChances],
            value: chance,
            labelOf: (k) => k ?? 'All',
            onChanged: (v) => set(() => chance = v),
          ),
          ChoiceGroup<String>(
            title: 'Status',
            options: const ['all', 'active', 'disabled'],
            value: status,
            labelOf: (k) =>
                k == 'all' ? 'All' : '${k[0].toUpperCase()}${k.substring(1)}',
            onChanged: (v) => set(() => status = v),
          ),
        ],
      ),
    );
    if (res != null) {
      await _cubit.setQuery(res..removeWhere((k, v) => v == null));
    }
  }

  Future<void> _export() async {
    final ok = await confirmDialog(
      context,
      title: 'Export Leads',
      message: 'Do you want to export leads data?',
      confirmLabel: 'Export',
    );
    if (!ok || !mounted) return;
    final bytes = await runWithProgress(
      context,
      () => _repo.export(Map.of(_cubit.query)),
    );
    if (bytes != null && mounted) {
      await shareBytes(context, bytes, 'leads.csv', 'text/csv');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Potential Leads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Leads',
            onPressed: _export,
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<PagedCubit<Lead>, PagedState<Lead>>(
          bloc: _cubit,
          builder: (context, st) {
            final q = _cubit.query;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ListToolbar(
                    hint: 'Search for name or phone number',
                    onSearch: (v) => _cubit.updateQuery({'q': v}),
                    onAdd: s.can(Perm.leadsWrite)
                        ? () async {
                            await context.push('/leads/new');
                            _cubit.reload();
                          }
                        : null,
                    onFilter: _filter,
                    filterActive: true,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ActiveFilters(labels: _labels(q), onTap: _filter),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CountLine(
                      st.isLoading && st.items.isEmpty
                          ? 'Loading…'
                          : 'Showing ${st.total} members',
                    ),
                  ),
                ),
                Expanded(
                  child: PagedListBody<Lead>(
                    cubit: _cubit,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    empty: EmptyState(
                      icon: Icons.contact_phone_outlined,
                      title: 'You have not added any leads',
                      message: 'Please create a new lead to track your potential customers.',
                      actionLabel: s.can(Perm.leadsWrite)
                          ? 'Add Lead Member'
                          : null,
                      onAction: () async {
                        await context.push('/leads/new');
                        _cubit.reload();
                      },
                    ),
                    itemBuilder: (context, l) =>
                        _LeadCard(lead: l, onChanged: _cubit.reload),
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

class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead, required this.onChanged});
  final Lead lead;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = lead;
    final overdue =
        l.followUpDate != null &&
        l.followUpDate!.compareTo(Fmt.ymd(DateTime.now())) < 0;
    return AppCard(
      onTap: () => _actions(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: l.name, url: l.photoUrl, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l.phone,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (l.disabled) const Tag('Disabled', tone: Tone.danger),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tag(l.source),
              Tag(l.chanceOfJoining, tone: chanceTone(l.chanceOfJoining)),
              if (l.followUpDate != null)
                Tag(
                  'Follow up on: ${Fmt.date(l.followUpDate)}',
                  tone: overdue ? Tone.danger : Tone.neutral,
                ),
              for (final x in l.labels) Tag(x.name, icon: Icons.label_outline),
            ],
          ),
        ],
      ),
    );
  }

  void _actions(BuildContext context) {
    final repo = getIt<LeadsRepository>();
    final s = getIt<SessionCubit>().state;
    final canWrite = s.can(Perm.leadsWrite);
    final gym = s.profile?.name ?? '';
    final l = lead;
    Future<void> run(
      Future<void> Function() f,
      String ok,
      BuildContext ctx,
    ) async {
      Navigator.pop(ctx);
      if (await runOk(context, f, success: ok)) onChanged();
    }

    showAppSheet<void>(
      context,
      title: l.name,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow('Phone', l.phone),
          InfoRow('Referral', l.source),
          InfoRow('Chance of joining', l.chanceOfJoining),
          InfoRow(
            'Follow up date',
            l.followUpDate == null ? null : Fmt.date(l.followUpDate),
          ),
          InfoRow('Notes', l.notes),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: () => Launch.call(context, l.phone),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Call'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: () => Launch.whatsApp(
                  context,
                  l.phone,
                  text:
                      'Hi ${l.name}, following up on your enquiry with $gym. Shall we schedule a visit?',
                ),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('Send Follow Up Message'),
              ),
            ],
          ),
          if (canWrite) ...[
            const Divider(height: 28),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/leads/${l.id}/convert').then((_) => onChanged());
              },
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('Convert to Member'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _snooze(ctx),
                    child: const Text('Snooze'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context
                          .push('/leads/${l.id}/edit')
                          .then((_) => onChanged());
                    },
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final ok = await confirmDialog(
                        ctx,
                        title: l.disabled ? 'Enable Lead' : 'Disable Lead',
                        message: l.disabled
                            ? 'Do you want to enable the lead?'
                            : 'Do you want to disable the lead?',
                        confirmLabel: l.disabled ? 'Enable' : 'Disable',
                      );
                      if (ok && ctx.mounted) {
                        await run(
                          () => repo.setDisabled(l.id, !l.disabled),
                          l.disabled ? 'Lead enabled' : 'Lead Disabled',
                          ctx,
                        );
                      }
                    },
                    child: Text(l.disabled ? 'Enable Lead' : 'Disable Lead'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        ctx,
                        title: 'Delete',
                        message: 'This action cannot be undone',
                        confirmLabel: 'Delete',
                        destructive: true,
                      );
                      if (ok && ctx.mounted) {
                        await run(() => repo.delete(l.id), 'Deleted', ctx);
                      }
                    },
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _snooze(BuildContext sheetCtx) async {
    final repo = getIt<LeadsRepository>();
    final pick = await showPickerSheet<String>(
      sheetCtx,
      title: 'Snooze Until',
      items: const ['nextWeek', 'nextMonth', 'custom'],
      labelOf: (k) => switch (k) {
        'nextWeek' => 'Next Monday',
        'nextMonth' => 'Next Month',
        _ => 'Custom Date',
      },
    );
    if (pick == null || !sheetCtx.mounted) return;
    String? date;
    if (pick == 'custom') {
      final d = await showDatePicker(
        context: sheetCtx,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (d == null) return;
      date = Fmt.ymd(d);
    }
    if (!sheetCtx.mounted) return;
    Navigator.pop(sheetCtx);
    if (await runOk(
      sheetCtx,
      () => repo.snooze(lead.id, pick, date: date),
      success: 'Follow up date updated',
    )) {
      onChanged();
    }
  }
}
