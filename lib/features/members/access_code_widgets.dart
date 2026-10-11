// A member's access code from the gym's side: shown (once) when a member is registered or a new code is issued, with copy and
// share; and a card on the member's page to issue a new one or take it away. Only a hash is kept on the server, so a lost code is
// replaced, not looked up.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/util/format.dart';
import '../../data/models/members.dart';
import '../../data/repositories/members_repository.dart';

String accessCodeMessage({required String memberName, required String gymName, required String code}) =>
    'Hi $memberName, your member access code for $gymName is $code.\n\n'
    'Open the Gymmie app, choose "I am a gym member" and enter this code to sign in. Keep it private: anyone with it can open your account.';

/// The code, large, with Copy and Share. Not dismissible by tapping outside, so it is not lost by accident.
Future<void> showAccessCodeDialog(BuildContext context, {required String memberName, required String gymName, required String code}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (ctx) => AlertDialog(
    title: Text('Access code for $memberName'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2, fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Give this to $memberName: they sign in with it under "I am a gym member". '
          'It is shown only now. If it is lost, issue a new one from the member\'s page.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
      ],
    ),
    actionsAlignment: MainAxisAlignment.spaceBetween,
    actions: [
      TextButton.icon(
        icon: const Icon(Icons.copy, size: 18),
        label: const Text('Copy'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (ctx.mounted) showToast(ctx, 'Code copied');
        },
      ),
      TextButton.icon(
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('Share'),
        onPressed: () => SharePlus.instance.share(ShareParams(text: accessCodeMessage(memberName: memberName, gymName: gymName, code: code), subject: 'Your $gymName access code')),
      ),
      FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(80, 44)), onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
    ],
  ),
);

/// On the member's page: whether they have a code, and the two things the gym can do about it.
class AccessCodeCard extends StatelessWidget {
  const AccessCodeCard({super.key, required this.member, required this.gymName, required this.onChanged});
  final MemberSummary member;
  final String gymName;
  final Future<void> Function() onChanged;

  Future<void> _issue(BuildContext context) async {
    final replacing = member.hasAccessCode;
    if (replacing &&
        !await confirmDialog(
          context,
          title: 'Issue a new code?',
          message: "${member.name}'s current code stops working at once and they are signed out of the app.",
          confirmLabel: 'Issue new code',
        )) {
      return;
    }
    if (!context.mounted) return;
    final r = await runWithProgress(context, () => getIt<MembersRepository>().issueAccessCode(member.id));
    if (r == null || !context.mounted) return;
    await showAccessCodeDialog(context, memberName: member.name, gymName: gymName, code: r.code);
    await onChanged();
  }

  Future<void> _revoke(BuildContext context) async {
    if (!await confirmDialog(
      context,
      title: 'Revoke access code?',
      message: '${member.name} can no longer sign in with their code, and is signed out of the app. You can issue a new one later.',
      confirmLabel: 'Revoke',
      destructive: true,
    )) {
      return;
    }
    if (!context.mounted) return;
    final done = await runWithProgress(context, () async {
      await getIt<MembersRepository>().revokeAccessCode(member.id);
      return true;
    }, success: 'Access code revoked');
    if (done == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.key_rounded, color: AppColors.navy),
          const SizedBox(width: 10),
          Expanded(child: Text('Member app access code', style: const TextStyle(fontWeight: FontWeight.w600))),
          Tag(member.hasAccessCode ? 'Active' : 'None', tone: member.hasAccessCode ? Tone.success : Tone.neutral),
        ]),
        const SizedBox(height: 6),
        Text(
          member.hasAccessCode
              ? 'Issued ${member.accessCodeIssuedAt == null ? '' : member.accessCodeIssuedAt!.split('T').first}. The code is not stored, so it cannot be shown again: issue a new one if it is lost.'
              : 'Issue a code so ${member.name} can sign in to the member app.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _issue(context), child: Text(member.hasAccessCode ? 'Issue new code' : 'Issue code'))),
          if (member.hasAccessCode) ...[
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger), onPressed: () => _revoke(context), child: const Text('Revoke'))),
          ],
        ]),
      ],
    ),
  );
}

/// Creates a payment link for the member's dues through the gym's own payment account, and offers it to copy or share.
Future<void> collectOnline(BuildContext context, MemberSummary m) async {
  final link = await runWithProgress(context, () => getIt<MembersRepository>().duesPaymentLink(m.id));
  if (link == null || !context.mounted) return;
  final gym = getIt<SessionCubit>().state.profile?.name ?? 'your gym';
  final text = 'Hi ${m.name}, your balance at $gym is ${Fmt.money(link.amount)}. Pay securely here: ${link.url}';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Pay ${Fmt.money(link.amount)}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(link.url, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        Text('Send this to ${m.name}. When they pay, the payment is recorded against their balance automatically.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
      ]),
      actions: [
        TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: link.url)); if (ctx.mounted) showToast(ctx, 'Link copied'); }, child: const Text('Copy')),
        TextButton(onPressed: () => SharePlus.instance.share(ShareParams(text: text)), child: const Text('Share')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(80, 44)), onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
      ],
    ),
  );
}
