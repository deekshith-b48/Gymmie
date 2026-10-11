import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../data/models/members.dart';

Color parseHex(String hex, [Color? fallbackColor]) {
  final fallback = fallbackColor ?? AppColors.navy;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

({String label, Tone tone}) membershipTag(MembershipInfo? m) {
  if (m == null) return (label: 'No plan', tone: Tone.neutral);
  switch (m.status) {
    case 'active':
      final d = m.daysLeft ?? 0;
      return (
        label: d <= 0 ? 'Expires today' : '$d day${d == 1 ? '' : 's'} left',
        tone: d <= 10 ? Tone.warning : Tone.success,
      );
    case 'paused':
      return (label: 'Paused', tone: Tone.warning);
    case 'upcoming':
      return (label: 'Starts ${Fmt.dateShort(m.startDate)}', tone: Tone.info);
    case 'ended':
      return (label: 'Ended', tone: Tone.neutral);
    default:
      return (label: 'Expired ${Fmt.dateShort(m.endDate)}', tone: Tone.danger);
  }
}

String statusTitle(String status) => switch (status) {
  'active' => 'Active',
  'upcoming' => 'Upcoming',
  'paused' => 'Paused',
  'expired' => 'Expired',
  'ended' => 'Ended',
  _ => status,
};

Tone statusTone(String status) => switch (status) {
  'active' => Tone.success,
  'upcoming' => Tone.info,
  'paused' => Tone.warning,
  'expired' => Tone.danger,
  _ => Tone.neutral,
};

/// Row in the members list (and search pickers).
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    this.onTap,
    this.trailing,
    this.showTags = true,
  });

  final MemberSummary member;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final tag = membershipTag(member.membership);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: member.name, url: member.photoUrl, radius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (member.blocked)
                          Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.block,
                              size: 16,
                              color: AppColors.danger,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${member.admissionNo}  ·  ${member.phone}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (showTags) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (member.membership != null) Tag(member.membership!.planName),
                Tag(tag.label, tone: tag.tone),
                if (member.balance > 0)
                  Tag('Due ${Fmt.money(member.balance)}', tone: Tone.danger),
                if (member.membership?.sessionsLeft != null)
                  Tag(
                    '${member.membership!.sessionsLeft} sessions left',
                    tone: Tone.info,
                  ),
                for (final l in member.labels.take(2))
                  Tag(l.name, tone: Tone.neutral, icon: Icons.label_outline),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
