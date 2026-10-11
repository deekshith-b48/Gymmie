import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/states.dart';

/// "Select your gym" (route /gym-selection): shown when a user belongs to several gyms.
class GymSelectionScreen extends StatelessWidget {
  const GymSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = getIt<SessionCubit>();
    return BlocBuilder<SessionCubit, SessionState>(
      bloc: cubit,
      builder: (context, s) {
        final canAdd = s.gyms.any((g) => g.role == 'owner');
        return Scaffold(
          appBar: AppBar(
            title: Text('Select your gym'.tr),
            actions: [
              if (s.hasGym)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go(R.home),
                ),
            ],
          ),
          body: SafeArea(
            child: s.gyms.isEmpty
                ? const EmptyState(
                    icon: Icons.fitness_center,
                    title: 'NO Gyms found',
                    message: 'Create your gym to get started.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (s.profileError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            s.profileError!.message,
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      for (final g in s.gyms)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            onTap: () async {
                              await cubit.selectGym(g.id);
                              if (context.mounted && cubit.state.hasGym) {
                                context.go(R.home);
                              }
                            },
                            child: Row(
                              children: [
                                UserAvatar(
                                  name: g.name,
                                  url: g.logoUrl,
                                  radius: 26,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        g.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (g.city != null)
                                        Text(
                                          g.city!,
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          Tag(
                                            roleLabel(g.role),
                                            tone: Tone.info,
                                          ),
                                          if (g.subscriptionStatus == 'expired')
                                            const Tag(
                                              'Subscription expired',
                                              tone: Tone.danger,
                                            ),
                                          Tag('Code ${g.code}'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (g.id == s.profile?.id)
                                  Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right,
                                    color: AppColors.textMuted,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (canAdd)
                        OutlinedButton.icon(
                          onPressed: () => context.push('${R.gymSetup}?add=1'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add new gym'),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: cubit.signOut,
                        child: Text('Log out'.tr),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
