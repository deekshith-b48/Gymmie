// Shown once after an owner or manager signs in: an invitation to ask the person who built Gymmie for a complete walkthrough.
// Entirely optional ("Skip" is the first thing on the screen). The contact details come from the server's configuration
// (COMPANY_WHATSAPP_NUMBER, SUPPORT_EMAIL, SUPPORT_NAME); if none are configured the screen offers no contact, it never makes one up.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/forms.dart';

/// Remembers, per account on this device, that the walkthrough invitation was answered.
class WalkthroughStore {
  static String _key(String userId) => 'walkthrough_seen:$userId';
  static bool seen(String userId) => getIt<SharedPreferences>().getBool(_key(userId)) ?? false;
  static Future<void> markSeen(String userId) => getIt<SharedPreferences>().setBool(_key(userId), true);
}

class WalkthroughScreen extends StatelessWidget {
  const WalkthroughScreen({super.key});

  Future<void> _done(BuildContext context) async {
    final s = getIt<SessionCubit>().state;
    if (s.user != null) await WalkthroughStore.markSeen(s.user!.id);
    if (context.mounted) context.go(R.home);
  }

  @override
  Widget build(BuildContext context) {
    final settings = getIt<SessionCubit>().state.settings;
    final whatsapp = (settings.companyWhatsappNumber ?? '').trim();
    final email = (settings.supportEmail ?? '').trim();
    final name = (settings.supportName ?? '').trim();
    final hasContact = whatsapp.isNotEmpty || email.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _done(context), child: const Text('Skip')),
              ),
              const Spacer(),
              Center(child: Image.asset('assets/brand/logo_mark.png', height: 90)),
              const SizedBox(height: 28),
              Text('Want a full walkthrough?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(
                hasContact
                    ? '${name.isEmpty ? 'The person who built Gymmie' : name} can take you through the whole app: members, plans, payments, reminders and the member app. It is optional and free to ask.'
                    : 'Gymmie can be explained step by step by the person who built it. Contact details have not been set up on this server yet, so there is nothing to message from here. You can carry on and explore.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              if (whatsapp.isNotEmpty)
                LoadingButton(
                  label: 'Message on WhatsApp',
                  icon: Icons.chat_outlined,
                  onPressed: () async {
                    await Launch.whatsApp(context, whatsapp, text: 'Hi, I would like a walkthrough of Gymmie for my gym.');
                  },
                ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 10),
                LoadingButton(
                  label: 'Send an email',
                  icon: Icons.mail_outline,
                  outlined: whatsapp.isNotEmpty,
                  onPressed: () async {
                    await launchUrl(Uri(scheme: 'mailto', path: email, query: 'subject=${Uri.encodeComponent('Gymmie walkthrough')}'));
                  },
                ),
              ],
              const SizedBox(height: 10),
              LoadingButton(label: hasContact ? 'Continue to Gymmie' : 'Continue', outlined: hasContact, onPressed: () => _done(context)),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
