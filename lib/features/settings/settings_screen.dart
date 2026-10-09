import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../data/models/user_gym.dart';

typedef _Item = ({
  IconData icon,
  String title,
  String? subtitle,
  String? route,
  bool visible,
  VoidCallback? onTap,
});

/// Settings tab: the hub for everything that is not a tab of its own.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      bloc: getIt<SessionCubit>(),
      builder: (context, s) {
        final gym = s.profile;
        final user = s.user;
        if (gym == null || user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _Item item(
          IconData i,
          String t,
          String? route, {
          bool visible = true,
          String? subtitle,
          VoidCallback? onTap,
        }) => (
          icon: i,
          title: t,
          subtitle: subtitle,
          route: route,
          visible: visible,
          onTap: onTap,
        );
        final cfg = getIt<AppConfig>();

        final groups = <(String, List<_Item>)>[
          (
            'Manage Your Gym'.tr,
            [
              item(
                Icons.storefront_outlined,
                'Gym Details'.tr,
                '/settings/gym',
                visible: s.can(Perm.settingsRead),
              ),
              item(
                Icons.event_repeat,
                'Membership Plans'.tr,
                '/plans',
                visible: s.can(Perm.plansRead),
              ),
              item(
                Icons.groups_outlined,
                'Manage Staff',
                '/staff',
                visible: s.can(Perm.staffRead),
              ),
              item(
                Icons.contact_phone_outlined,
                'Leads'.tr,
                '/leads',
                visible: s.can(Perm.leadsRead),
              ),
              item(
                Icons.how_to_reg_outlined,
                'Attendance'.tr,
                '/attendance',
                visible:
                    s.can(Perm.attendanceRead) && s.feature(Feat.attendance),
              ),
              item(
                Icons.fingerprint,
                'Biometrics'.tr,
                '/biometrics',
                visible: s.can(Perm.devicesRead) && s.feature(Feat.biometrics),
              ),
              item(
                Icons.event_available_outlined,
                'Trainer Session/Class Bookings',
                '/trainer/schedule',
                visible: s.role == 'trainer' || s.can(Perm.trainersWrite),
              ),
            ],
          ),
          (
            'Sales & Finance',
            [
              item(
                Icons.inventory_2_outlined,
                'Manage Products',
                '/products',
                visible: s.can(Perm.productsRead) && s.feature(Feat.sales),
              ),
              item(
                Icons.point_of_sale,
                'Sales History',
                '/sales',
                visible: s.can(Perm.productsRead) && s.feature(Feat.sales),
              ),
              item(
                Icons.receipt_long_outlined,
                'Expenses'.tr,
                '/expenses',
                visible: s.can(Perm.expensesRead) && s.feature(Feat.sales),
              ),
              item(
                Icons.percent,
                'Tax Information'.tr,
                '/settings/tax',
                visible: s.can(Perm.settingsRead) && s.feature(Feat.tax),
              ),
              item(
                Icons.payments_outlined,
                'Payment Methods'.tr,
                '/settings/payment-methods',
                visible: s.can(Perm.financeRead),
              ),
              item(
                Icons.qr_code_2,
                'Gym UPI QR',
                '/settings/upi',
                visible: s.can(Perm.settingsRead) && s.feature(Feat.upiQr),
              ),
            ],
          ),
          (
            'Plans and Health',
            [
              item(
                Icons.fitness_center,
                'Workout Plans'.tr,
                '/workout-plans',
                visible: s.can(Perm.plansetsRead) && s.feature(Feat.workout),
              ),
              item(
                Icons.restaurant_menu,
                'Diet Plans'.tr,
                '/diet-plans',
                visible: s.can(Perm.plansetsRead) && s.feature(Feat.diet),
              ),
              item(
                Icons.sports_gymnastics,
                'Exercises'.tr,
                '/exercises',
                visible: s.can(Perm.plansetsRead),
              ),
              item(
                Icons.assignment_outlined,
                'PAR-Q Form Builder',
                '/parq-form-builder',
                visible:
                    s.can(Perm.plansetsWrite) && s.feature(Feat.memberHealth),
              ),
              item(
                Icons.bloodtype_outlined,
                'Find Blood Donors',
                '/members/blood-donors',
                visible: s.can(Perm.membersRead),
              ),
              item(
                Icons.trending_down,
                'At-risk members'.tr,
                '/members/at-risk',
                visible: s.can(Perm.membersRead) && s.feature(Feat.riskMembers),
              ),
            ],
          ),
          (
            'Communication',
            [
              item(
                Icons.campaign_outlined,
                'Broadcasts'.tr,
                '/broadcasts',
                visible: s.can(Perm.broadcastsRead) && s.feature(Feat.whatsapp),
              ),
              item(
                Icons.chat_outlined,
                'Message Templates'.tr,
                '/message-templates',
                visible: s.can(Perm.broadcastsRead) && s.feature(Feat.whatsapp),
              ),
              item(
                Icons.account_balance_wallet_outlined,
                'Credits'.tr,
                '/credits',
                visible: s.can(Perm.broadcastsRead) && s.feature(Feat.whatsapp),
              ),
              item(
                Icons.rate_review_outlined,
                'Feedback & Complaints',
                '/feedback',
                visible: s.can(Perm.feedbackRead),
              ),
              item(
                Icons.ondemand_video_outlined,
                'Video Links'.tr,
                '/video-links',
                visible: s.can(Perm.plansRead),
              ),
              item(
                Icons.image_outlined,
                'Create Poster',
                '/poster',
                visible: s.can(Perm.membersRead) && s.feature(Feat.poster),
              ),
            ],
          ),
          (
            'App',
            [
              item(
                Icons.tune,
                'App Features',
                '/settings/features',
                visible: s.can(Perm.settingsWrite),
              ),
              item(
                Icons.settings_applications_outlined,
                'App Preferences'.tr,
                '/settings/preferences',
              ),
              item(
                Icons.language,
                'Language'.tr,
                '/settings/language',
                subtitle: L10n.supported[L10n.code],
              ),
              item(Icons.brightness_6_outlined, 'Theme'.tr, '/settings/theme'),
              item(
                Icons.schedule,
                'Time Zone'.tr,
                '/settings/timezone',
                subtitle: gym.timezone,
                visible: s.can(Perm.settingsWrite),
              ),
              item(
                Icons.swap_horiz,
                'Switch Gym'.tr,
                '/gym-selection',
                subtitle: s.gyms.length > 1 ? '${s.gyms.length} gyms' : null,
              ),
            ],
          ),
          (
            'Account',
            [
              item(Icons.person_outline, 'Edit Profile', '/profile'),
              item(
                Icons.workspace_premium_outlined,
                'Subscription'.tr,
                '/settings/subscription',
                subtitle: gym.subscription == null
                    ? null
                    : '${gym.subscription!.plan} · ${gym.subscription!.status}',
                visible: s.can(Perm.settingsRead),
              ),
            ],
          ),
          (
            'Support and Information',
            [
              item(Icons.help_outline, 'Help Center'.tr, '/settings/support'),
              item(
                Icons.developer_mode,
                'Developer tools',
                '/settings/dev',
                visible: cfg.devToolsEnabled,
              ),
            ],
          ),
        ];

        return Scaffold(
          appBar: AppBar(title: Text('Settings'.tr)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: AppCard(
                  onTap: () => context.push('/profile'),
                  child: Row(
                    children: [
                      UserAvatar(
                        name: user.name,
                        url: user.photoUrl,
                        radius: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              user.phone ?? user.email ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                Tag(roleLabel(s.role), tone: Tone.info),
                                Tag(gym.name),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              for (final g in groups)
                if (g.$2.any((e) => e.visible))
                  MenuGroup(
                    title: g.$1,
                    children: [
                      for (final it in g.$2.where((e) => e.visible))
                        MenuTile(
                          icon: it.icon,
                          title: it.title,
                          subtitle: it.subtitle,
                          onTap: it.onTap ?? () => context.push(it.route!),
                        ),
                    ],
                  ),
              MenuGroup(
                children: [
                  MenuTile(
                    icon: Icons.logout,
                    title: 'Log out'.tr,
                    danger: true,
                    onTap: () async {
                      if (await confirmDialog(
                        context,
                        title: 'Log out',
                        message: 'Do you want to logout?',
                        confirmLabel: 'Log out',
                        destructive: true,
                      )) {
                        await getIt<SessionCubit>().signOut();
                      }
                    },
                  ),
                  MenuTile(
                    icon: Icons.devices_other,
                    title: 'Logout from All Devices',
                    danger: true,
                    onTap: () async {
                      if (await confirmDialog(
                        context,
                        title: 'Logout from All Devices',
                        message: 'Do you want to logout from all devices?',
                        confirmLabel: 'Log out',
                        destructive: true,
                      )) {
                        await getIt<SessionCubit>().signOut(everywhere: true);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Launch.url(context, AppConfig.supportUrls['privacy']!),
                  child: Text(
                    'Privacy Policy'.tr,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
