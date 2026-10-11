// The gym's inbox for what members ask in their app: renew, change plan, cancel. Approving or rejecting records the
// gym's answer (the member sees it); changing the membership or taking payment is still done as usual from the member.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart' show toApiException;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../data/models/members.dart';
import '../../data/repositories/members_repository.dart';

class MembershipRequestsScreen extends StatefulWidget {
  const MembershipRequestsScreen({super.key});
  @override
  State<MembershipRequestsScreen> createState() =>
      _MembershipRequestsScreenState();
}

class _MembershipRequestsScreenState extends State<MembershipRequestsScreen> {
  final _repo = getIt<MembersRepository>();
  bool _pendingOnly = true;
  bool _loading = true;
  Object? _error;
  List<MembershipRequestRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _repo.membershipRequests(
        status: _pendingOnly ? 'pending' : null,
      );
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _decide(MembershipRequestRow q, bool approve) async {
    String? note;
    if (approve) {
      if (!await confirmDialog(
        context,
        title: 'Approve ${q.typeLabel.toLowerCase()}?',
        message: 'The member is told it is approved. Add or change their membership from their profile as usual.',
        confirmLabel: 'Approve',
      )) {
        return;
      }
    } else {
      note = await promptText(
        context,
        title: 'Reject ${q.typeLabel.toLowerCase()}',
        label: 'Reason for the member (optional)',
        maxLength: 300,
        maxLines: 2,
        confirmLabel: 'Reject',
      );
      if (note == null) {
        return;
      }
    }
    if (!mounted) return;
    final done = await runWithProgress(context, () async {
      await _repo.decideRequest(q.id, approve: approve, note: note);
      return true;
    }, success: approve ? 'Approved' : 'Rejected');
    if (done == true && mounted) _load();
  }

  Color _tint(String s) => switch (s) {
    'approved' => AppColors.success,
    'rejected' => AppColors.danger,
    'pending' => AppColors.warning,
    _ => AppColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final canDecide = getIt<SessionCubit>().state.can(Perm.requestsWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Member requests')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Pending'),
                    selected: _pendingOnly,
                    onSelected: (_) {
                      _pendingOnly = true;
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !_pendingOnly,
                    onSelected: (_) {
                      _pendingOnly = false;
                      _load();
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _body(canDecide)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool canDecide) {
    if (_loading) return const LoadingBox();
    if (_error != null) return ErrorState(error: toApiException(_error!), onRetry: _load);
    if (_rows.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: _pendingOnly ? 'No pending requests' : 'No requests yet',
        message: 'When a member asks to renew, change plan or cancel in their app, it shows up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final q = _rows[i];
          return AppCard(
            onTap: () => context.push('/members/${q.memberId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        q.memberName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _tint(q.status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        q.status[0].toUpperCase() + q.status.substring(1),
                        style: TextStyle(
                          color: _tint(q.status),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    q.typeLabel,
                    if (q.planName != null) q.planName!,
                  ].join(' · '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (q.currentPlan != null)
                  Text(
                    'Now on ${q.currentPlan}${q.currentEnd == null ? '' : ' until ${q.currentEnd}'}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if ((q.note ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('“${q.note}”'),
                  ),
                if ((q.decisionNote ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Reply: ${q.decisionNote}',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    q.createdAt.length >= 10
                        ? q.createdAt.substring(0, 10)
                        : q.createdAt,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (q.pending && canDecide)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _decide(q, false),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _decide(q, true),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
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
