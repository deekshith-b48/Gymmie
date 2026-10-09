import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/async_cubit.dart';
import '../../core/util/files.dart';
import '../../core/util/json.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/list_toolbar.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';
import 'member_widgets.dart';

const _sortOptions = <String, String>{
  'createdAtDesc': 'Created at - Desc',
  'createdAtAsc': 'Created at - Asc',
  'nameAsc': 'Name (A-Z)',
  'nameDesc': 'Name (Z-A)',
  'joiningDateAsc': 'Joined First',
  'joiningDateDesc': 'Joined Recently',
  'admissionNoDesc': 'Admission no. (Latest first)',
  'admissionNoAsc': 'Admission no. (Oldest first)',
  'membershipExpiryAsc': 'Expiry - Asc',
  'membershipExpiryDesc': 'Expiry - Desc',
};

const memberStatusOptions = <String, String>{
  'all': 'All',
  'active': 'Active',
  'upcoming': 'Upcoming',
  'paused': 'Paused',
  'expired': 'Expired',
  'noMembership': 'No plan',
  'expiring10': 'Expiring in 10 days',
  'expiring30': 'Expiring in 30 days',
  'expiredIn10': 'Expired in last 10 days',
  'expiredIn30': 'Expired in last 30 days',
  'expiredBetween30and60': 'Expired between 30 and 60 days',
  'expiredBetween60and90': 'Expired between 60 and 90 days',
  'expiredBetween90and120': 'Expired between 90 and 120 days',
  'withBalance': 'With Balance',
  'blocked': 'Blocked',
  'birthdayToday': 'Birthday Today',
  'newThisMonth': 'New this month',
};

PagedCubit<MemberSummary> buildMembersCubit({Json query = const {}}) {
  final repo = getIt<MembersRepository>();
  return PagedCubit<MemberSummary>(
    fetch: repo.list,
    parse: MemberSummary.fromJson,
    query: query,
  );
}

/// Members tab (route /members). Accepts `?status=` from dashboard tiles.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, this.initialStatus});
  final String? initialStatus;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late PagedCubit<MemberSummary> _cubit;
  String? _appliedStatus;

  @override
  void initState() {
    super.initState();
    _cubit = buildMembersCubit(
      query: {
        'sort': 'createdAtDesc',
        if (widget.initialStatus != null) 'status': widget.initialStatus,
      },
    );
    _appliedStatus = widget.initialStatus;
  }

  @override
  void didUpdateWidget(covariant MembersScreen old) {
    super.didUpdateWidget(old);
    // Tapping a different dashboard tile re-enters this tab with another status.
    if (widget.initialStatus != _appliedStatus) {
      _appliedStatus = widget.initialStatus;
      _cubit.updateQuery({'status': widget.initialStatus ?? 'all'});
    }
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  List<String> _activeLabels(Json q, Map<String, String> labelNames) => [
    'Sort by: ${_sortOptions[q['sort'] ?? 'createdAtDesc']}',
    if (q['status'] != null && q['status'] != 'all')
      'Status: ${memberStatusOptions[q['status']] ?? q['status']}',
    if (q['labelIds'] != null)
      'Labels: ${'${q['labelIds']}'.split(',').map((i) => labelNames[i] ?? '').where((e) => e.isNotEmpty).join(', ')}',
    if (q['trainerId'] != null)
      'Trainer: ${labelNames['t:${q['trainerId']}'] ?? ''}',
    if (q['q'] != null) 'Search: "${q['q']}"',
  ];

  Future<void> _filter() async {
    final repo = getIt<MembersRepository>();
    final labels = await repo.labels().catchError((Object _) => <LabelRef>[]);
    final trainers = await getIt<StaffRepository>().trainers().catchError(
      (Object _) => <StaffMember>[],
    );
    if (!mounted) return;
    var sort = _cubit.query['sort'] as String? ?? 'createdAtDesc';
    var status = _cubit.query['status'] as String? ?? 'all';
    final selLabels = <String>{
      ...('${_cubit.query['labelIds'] ?? ''}')
          .split(',')
          .where((e) => e.isNotEmpty),
    };
    String? trainer = _cubit.query['trainerId'] as String?;
    final result = await showFilterSheet<Json>(
      context,
      title: 'Filter'.tr,
      onReset: () {
        sort = 'createdAtDesc';
        status = 'all';
        selLabels.clear();
        trainer = null;
      },
      onSave: () => {
        'sort': sort,
        'status': status == 'all' ? null : status,
        'labelIds': selLabels.isEmpty ? null : selLabels.join(','),
        'trainerId': trainer,
      },
      body: (ctx, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChoiceGroup<String>(
            title: 'Sort by'.tr,
            options: _sortOptions.keys.toList(),
            value: sort,
            labelOf: (k) => _sortOptions[k]!,
            onChanged: (v) => set(() => sort = v),
          ),
          ChoiceGroup<String>(
            title: 'Membership Status',
            options: memberStatusOptions.keys.toList(),
            value: status,
            labelOf: (k) => memberStatusOptions[k]!,
            onChanged: (v) => set(() => status = v),
          ),
          if (labels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              child: Text(
                'Member Labels',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final l in labels)
                  PillChip(
                    label: l.name,
                    selected: selLabels.contains(l.id),
                    onTap: () => set(
                      () => selLabels.contains(l.id)
                          ? selLabels.remove(l.id)
                          : selLabels.add(l.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
          ],
          if (trainers.isNotEmpty)
            ChoiceGroup<String?>(
              title: 'Trainer',
              options: [null, ...trainers.map((t) => t.userId)],
              value: trainer,
              labelOf: (id) => id == null
                  ? 'All'
                  : trainers.firstWhere((t) => t.userId == id).name,
              onChanged: (v) => set(() => trainer = v),
            ),
        ],
      ),
    );
    if (result != null) {
      final names = {
        for (final l in labels) l.id: l.name,
        for (final t in trainers) 't:${t.userId}': t.name,
      };
      _names = names;
      await _cubit.setQuery(
        {...result, 'q': _cubit.query['q']}..removeWhere((k, v) => v == null),
      );
    }
  }

  Map<String, String> _names = {};

  Future<void> _export() async {
    final ok = await confirmDialog(
      context,
      title: 'Do you want to export members data?',
      confirmLabel: 'Export',
    );
    if (!ok || !mounted) return;
    final bytes = await runWithProgress(
      context,
      () => getIt<MembersRepository>().exportCsv(Map.of(_cubit.query)),
    );
    if (bytes == null || !mounted) return;
    await shareBytes(context, bytes, 'members.csv', 'text/csv');
  }

  @override
  Widget build(BuildContext context) {
    final session = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(
        title: Text('Members'.tr),
        actions: [
          if (session.can(Perm.membersRead))
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export Members',
              onPressed: _export,
            ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<PagedCubit<MemberSummary>, PagedState<MemberSummary>>(
          bloc: _cubit,
          builder: (context, s) {
            final q = _cubit.query;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: ListToolbar(
                    hint: 'Search members by name or ID',
                    initialQuery: (q['q'] as String?) ?? '',
                    onSearch: (v) => _cubit.updateQuery({'q': v}),
                    onAdd: session.can(Perm.membersWrite)
                        ? () => context.push('/members/new')
                        : null,
                    onFilter: _filter,
                    filterActive:
                        q['status'] != null ||
                        q['labelIds'] != null ||
                        q['trainerId'] != null ||
                        (q['sort'] ?? 'createdAtDesc') != 'createdAtDesc',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: ActiveFilters(
                    labels: _activeLabels(q, _names),
                    onTap: _filter,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CountLine(
                      s.isLoading && s.items.isEmpty
                          ? 'Loading…'
                          : 'Showing ${s.total} member${s.total == 1 ? '' : 's'}',
                    ),
                  ),
                ),
                Expanded(
                  child: PagedListBody<MemberSummary>(
                    cubit: _cubit,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    empty: EmptyState(
                      icon: Icons.groups_2_outlined,
                      title: q['q'] != null || q['status'] != null
                          ? 'No members match'
                          : 'Add your first member',
                      message: q['q'] != null || q['status'] != null
                          ? 'Try changing the search or filters.'
                          : 'Use search to quickly find a member by name or phone number.',
                      actionLabel:
                          session.can(Perm.membersWrite) &&
                              q['q'] == null &&
                              q['status'] == null
                          ? 'Add new member'
                          : null,
                      onAction: () => context.push('/members/new'),
                    ),
                    itemBuilder: (context, m) => MemberCard(
                      member: m,
                      onTap: () async {
                        await context.push('/members/${m.id}');
                        if (mounted) _cubit.reload();
                      },
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) {
                          if (v == 'call') Launch.call(context, m.phone);
                          if (v == 'wa') Launch.whatsApp(context, m.phone);
                          if (v == 'renew') {
                            context.push('/members/${m.id}/renew');
                          }
                          if (v == 'mark') _mark(m);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'call',
                            child: Text('Call'),
                          ),
                          const PopupMenuItem(
                            value: 'wa',
                            child: Text('Chat on WhatsApp'),
                          ),
                          if (session.can(Perm.membersWrite))
                            const PopupMenuItem(
                              value: 'renew',
                              child: Text('Renew Membership'),
                            ),
                          if (session.can(Perm.attendanceWrite))
                            const PopupMenuItem(
                              value: 'mark',
                              child: Text('Mark attendance'),
                            ),
                        ],
                      ),
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

  Future<void> _mark(MemberSummary m) async {
    final r = await runWithProgress(
      context,
      () => getIt<AttendanceRepository>().mark(m.id),
      success: 'Attendance marked successfully',
    );
    if (r != null && mounted) _cubit.reload();
  }
}
