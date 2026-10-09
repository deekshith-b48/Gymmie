import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'phone_input.dart';

/// Arguments handed to the OTP screen: what to verify and how to resend.
class OtpArgs {
  const OtpArgs({
    required this.challenge,
    required this.target,
    required this.verify,
    required this.resend,
    this.title = 'Verify your account',
  });

  final OtpChallenge challenge;
  final String target;
  final Future<AuthResult> Function(String requestId, String otp) verify;
  final Future<OtpChallenge> Function() resend;
  final String title;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

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
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final phone = _useEmail ? null : toE164(_phone.text, dial: _dial);
      final email = _useEmail ? _email.text.trim().toLowerCase() : null;
      final channel = _useEmail ? 'email' : _channel;
      final c = await _auth.requestLoginOtp(
        phone: phone,
        email: email,
        channel: channel,
      );
      if (!mounted) return;
      await context.push(
        R.loginOtp,
        extra: OtpArgs(
          challenge: c,
          target: phone ?? email!,
          title: 'Verify your account',
          verify: _auth.verifyLoginOtp,
          resend: () => _auth.requestLoginOtp(
            phone: phone,
            email: email,
            channel: channel,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Center(
                child: SvgPicture.asset(
                  'assets/weights-amico.svg',
                  height: 190,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome to DGymBook!'.tr,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _useEmail
                    ? 'Login with your email address'
                    : 'Login with your phone number',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              if (_useEmail)
                AppTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'Enter email',
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  validator: (v) => V.email(v, optional: false),
                  onSubmitted: (_) => _send(),
                )
              else
                PhoneInput(
                  controller: _phone,
                  dial: _dial,
                  onDialChanged: (d) => setState(() => _dial = d),
                  autofocus: true,
                  onSubmitted: (_) => _send(),
                ),
              if (!_useEmail) ...[
                const SizedBox(height: 20),
                const Text(
                  'Select OTP Method',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    PillChip(
                      label: 'SMS',
                      selected: _channel == 'sms',
                      icon: Icons.sms_outlined,
                      onTap: () => setState(() => _channel = 'sms'),
                    ),
                    PillChip(
                      label: 'WhatsApp',
                      selected: _channel == 'whatsapp',
                      icon: Icons.chat_outlined,
                      onTap: () => setState(() => _channel = 'whatsapp'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              LoadingButton(
                label: 'Send OTP'.tr,
                onPressed: _send,
                loading: _busy,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _useEmail = !_useEmail),
                  child: Text(
                    _useEmail
                        ? 'Log in with phone instead'
                        : 'Log in with your email instead',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account?",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => context.push(R.register),
                    child: Text('Sign up'.tr),
                  ),
                ],
              ),
              const Center(child: VersionFooter()),
            ],
          ),
        ),
      ),
    );
  }
}
