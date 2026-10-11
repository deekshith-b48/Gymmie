// What happens after the single sign-in code is proven: the server says the number is staff, a member, or several
// (then the person picks), and the matching session is started. The two kinds of session stay separate underneath.
import 'package:flutter/material.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/util/json.dart';
import '../../core/widgets/sheets.dart';
import '../../data/repositories/auth_repository.dart';
import '../member/member_repository.dart';
import '../member/member_session_cubit.dart';

/// One way in offered after the code: manage a gym, or open one gym as a member.
class SigninOption {
  const SigninOption({required this.id, required this.kind, required this.title, this.subtitle});
  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  bool get isStaff => kind == 'staff';
  factory SigninOption.fromJson(Json j) =>
      SigninOption(id: j.s('id'), kind: j.s('kind'), title: j.s('title'), subtitle: j.str('subtitle'));
}

/// Verifies the code and finishes the sign-in; never returns a session for a number the server did not prove.
Future<Object> verifySignin(String requestId, String otp) => getIt<AuthRepository>().verifySignin(requestId, otp);

/// Starts the right session for a verify/choose answer, asking the person first when there is more than one way in.
Future<void> finishSignin(BuildContext context, Object result) async {
  final auth = getIt<AuthRepository>();
  var d = result as Json;
  if (d.str('status') == 'choose') {
    final options = [for (final o in d.list('options')) SigninOption.fromJson(o)];
    final pick = await chooseHow(context, options);
    if (pick == null) return;
    d = await auth.chooseSignin(d.s('selectionToken'), pick.id);
  }
  if (d.str('kind') == 'member') {
    await getIt<MemberRepository>().acceptBundle(d);
    await getIt<MemberSessionCubit>().signedIn();
  } else {
    final r = await auth.acceptStaff(d);
    await getIt<SessionCubit>().signedIn(r); // the router redirects off the new session
  }
}

/// "How do you want to continue?": a card per role, so a gym owner who also trains at another gym is never guessed at.
Future<SigninOption?> chooseHow(BuildContext context, List<SigninOption> options) => showAppSheet<SigninOption>(
  context,
  title: 'Continue as',
  builder: (ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('This number is on more than one account. You can switch any time by signing out.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), height: 1.4)),
        ),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(ctx).pop(o),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(o.isStaff ? Icons.admin_panel_settings_outlined : Icons.fitness_center, color: cs.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (o.subtitle != null) Text(o.subtitle!, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 12.5)),
                    ])),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.4)),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  },
);
