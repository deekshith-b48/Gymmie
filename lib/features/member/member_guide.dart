import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/sheets.dart';

/// The short "role descriptor" for gym members: who they are in the system, what they can do and what
/// they cannot. Shown from the login page ("How it works") and from My Gym.
Future<void> showMemberGuide(BuildContext context) => showAppSheet<void>(
  context,
  title: 'Using Gymmie as a gym member'.tr,
  builder: (_) => const MemberGuide(),
);

class MemberGuide extends StatelessWidget {
  const MemberGuide({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You are a member of your gym. Sign in with the phone number your gym has on file.'.tr,
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        row(
          Icons.fitness_center,
          'Train'.tr,
          'Log workouts and rest timers, follow progressive overload, and see your strength, records and body weight.'.tr,
        ),
        row(
          Icons.badge_outlined,
          'My gym'.tr,
          'See your plan, expiry date, balance and trainer, and show your QR code at the desk to check in.'.tr,
        ),
        row(
          Icons.lock_outline,
          'Private'.tr,
          'Your training log is yours. Your gym’s staff cannot read it.'.tr,
        ),
        row(
          Icons.support_agent,
          'Not here'.tr,
          'Payments, renewals and plan changes are handled by the front desk. Trainers, staff, managers and owners use the staff login.'.tr,
        ),
      ],
    );
  }
}
