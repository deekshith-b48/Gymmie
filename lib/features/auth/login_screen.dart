import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../core/data/countries.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/auth_repository.dart';
import '../system/system_screens.dart';
import 'signin_flow.dart';
import 'phone_input.dart';

/// Arguments handed to the OTP screen: what to verify and how to resend.
class OtpArgs {
  const OtpArgs({
    required this.challenge,
    required this.target,
    required this.verify,
    required this.resend,
    this.title = 'Verify your account',
    this.onVerified,
  });

  final OtpChallenge challenge;
  final String target;

  /// Returns what a successful check produced: an [AuthResult] for staff sign-in and registration.
  final Future<Object> Function(String requestId, String otp) verify;
  final Future<OtpChallenge> Function() resend;
  final String title;

  /// What to do with the result of [verify]. Unset means the staff default: sign the user in with
  /// the [AuthResult]. The gym-member flow passes its own.
  final Future<void> Function(BuildContext context, Object result)? onVerified;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// One door for everyone. Owners, staff and gym members all start here with their phone number; after the code the
/// server says who the number is and the app opens the right place (asking only when there is more than one).
class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _useEmail = false;
  String _dial = '+91';
  String _channel = 'sms';
  bool _busy = false;
  final _auth = getIt<AuthRepository>();

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_useEmail) {
        // Email is a staff-only way in (members have a phone number on file, not an email login).
        final email = _email.text.trim().toLowerCase();
        final c = await _auth.requestLoginOtp(email: email, channel: 'email');
        if (!mounted) return;
        await context.push(
          R.loginOtp,
          extra: OtpArgs(
            challenge: c,
            target: email,
            title: 'Check your email',
            verify: _auth.verifyLoginOtp,
            resend: () => _auth.requestLoginOtp(email: email, channel: 'email'),
          ),
        );
      } else {
        final phone = toE164(_phone.text, dial: _dial);
        final channel = _channel;
        final c = await _auth.requestSignin(phone: phone, channel: channel);
        if (!mounted) return;
        await context.push(
          R.loginOtp,
          extra: OtpArgs(
            challenge: c,
            target: phone,
            title: 'Enter your code',
            verify: verifySignin,
            resend: () => _auth.requestSignin(phone: phone, channel: channel),
            onVerified: finishSignin,
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = cs.onSurface.withValues(alpha: 0.62);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // the page opens on a navy header, so the clock and battery are drawn light
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                children: [
                  _Hero(top: MediaQuery.paddingOf(context).top),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -26),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  22,
                                  20,
                                  20,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: dark
                                        ? AppColors.darkBorder
                                        : AppColors.border,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.navy.withValues(
                                        alpha: dark ? 0.0 : 0.10,
                                      ),
                                      blurRadius: 32,
                                      offset: const Offset(0, 14),
                                    ),
                                  ],
                                ),
                                child: Form(
                                  key: _form,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Sign in'.tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _useEmail
                                            ? 'Use the email on your owner or staff account.'
                                            : 'Gym owners, staff and members all sign in with the phone number their gym has on file.',
                                        style: TextStyle(
                                          color: muted,
                                          height: 1.45,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: _useEmail
                                            ? AppTextField(
                                                key: const ValueKey('email'),
                                                controller: _email,
                                                label: 'Email',
                                                hint: 'you@example.com',
                                                keyboardType:
                                                    TextInputType.emailAddress,
                                                autofocus: true,
                                                validator: (v) =>
                                                    V.email(v, optional: false),
                                                onSubmitted: (_) => _send(),
                                              )
                                            : PhoneInput(
                                                key: const ValueKey('phone'),
                                                controller: _phone,
                                                dial: _dial,
                                                onDialChanged: (d) =>
                                                    setState(() => _dial = d),
                                                autofocus: true,
                                                onSubmitted: (_) => _send(),
                                              ),
                                      ),
                                      if (!_useEmail) ...[
                                        const SizedBox(height: 14),
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Text(
                                              'Send code by',
                                              style: TextStyle(
                                                color: muted,
                                                fontSize: 13,
                                              ),
                                            ),
                                            PillChip(
                                              label: 'SMS',
                                              selected: _channel == 'sms',
                                              icon: Icons.sms_outlined,
                                              onTap: () => setState(
                                                () => _channel = 'sms',
                                              ),
                                            ),
                                            PillChip(
                                              label: 'WhatsApp',
                                              selected: _channel == 'whatsapp',
                                              icon: Icons.chat_outlined,
                                              onTap: () => setState(
                                                () => _channel = 'whatsapp',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 22),
                                      LoadingButton(
                                        label: 'Continue'.tr,
                                        onPressed: _send,
                                        loading: _busy,
                                      ),
                                      const SizedBox(height: 6),
                                      Center(
                                        child: TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => setState(
                                                  () => _useEmail = !_useEmail,
                                                ),
                                          child: Text(
                                            _useEmail
                                                ? 'Use my phone number instead'
                                                : 'Owner or staff? Use email instead',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _Trust(),
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'New to Gymmie?',
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: AppColors.border,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _PathTile(
                                    icon: Icons.storefront_outlined,
                                    title: 'I run a gym',
                                    subtitle: 'Create your gym and start managing members',
                                    onTap: () => context.push(R.register),
                                  ),
                                  const SizedBox(height: 10),
                                  _PathTile(
                                    icon: Icons.fitness_center,
                                    title: 'I am a gym member',
                                    subtitle: 'Sign in with the access code your gym gave you',
                                    onTap: () => context.push(R.memberLogin),
                                  ),
                                  const SizedBox(height: 18),
                                  const Center(child: VersionFooter()),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The branded top of the page: the Gymmie logo over a soft glow of the accent colour.
class _Hero extends StatelessWidget {
  const _Hero({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(24, top + 20, 24, 56),
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.9),
        radius: 1.1,
        colors: [AppColors.accent.withValues(alpha: AppColors.isDark ? 0.22 : 0.16), Colors.transparent],
      ),
    ),
    child: Column(
      children: [
        Image.asset('assets/brand/logo_title.png', height: 170, fit: BoxFit.contain, semanticLabel: 'Gymmie'),
        Text(
          'Run your gym or train at one, in a single app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
      ],
    ),
  );
}

class _Trust extends StatelessWidget {
  const _Trust();
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    Widget item(IconData i, String t) => Expanded(
      child: Column(
        children: [
          Icon(i, size: 18, color: muted),
          const SizedBox(height: 4),
          Text(
            t,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11.5, height: 1.3),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(Icons.password_rounded, 'No password to remember'),
        item(Icons.lock_outline_rounded, 'One-time code to your phone'),
        item(Icons.verified_user_outlined, 'Only the right account opens'),
      ],
    );
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
