import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';
import '../../data/models/members.dart';
import '../../data/repositories/members_repository.dart';

/// "Show At-risk Members": rule-based churn signals (attendance declining / low attendance / balance due).
class AtRiskScreen extends StatelessWidget {
  const AtRiskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit =
        AsyncCubit<List<({MemberSummary member, List<RiskReason> reasons})>>(
          () => getIt<MembersRepository>().atRisk(),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('At-Risk Members')),
      body: AsyncBody<List<({MemberSummary member, List<RiskReason> reasons})>>(
        cubit: cubit,
        isEmpty: (l) => l.isEmpty,
        empty: const EmptyState(
          icon: Icons.thumb_up_alt_outlined,
          title: 'No at-risk members',
          message: 'Everyone is attending regularly. Nice work!',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Text(
                'Signals are computed from attendance, balances and expiry dates.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              );
            }
            final e = list[i - 1];
            return AppCard(
              onTap: () => context.push('/members/${e.member.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(name: e.member.name, url: e.member.photoUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              e.member.phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.chat_outlined,
                          color: AppColors.success,
                        ),
                        onPressed: () => Launch.whatsApp(
                          context,
                          e.member.phone,
                          text:
                              'Hi ${e.member.name}, we have missed you at the gym! Is everything okay?',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final r in e.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.trending_down,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${r.label}${r.detail == null ? '' : ' · ${r.detail}'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Last attended: ${e.member.lastAttendedAt == null ? 'never' : e.member.lastAttendedAt!}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
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
