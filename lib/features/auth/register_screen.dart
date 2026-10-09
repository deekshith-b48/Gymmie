import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../core/config/app_config.dart';
import '../../core/data/countries.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/repositories/auth_repository.dart';
import 'login_screen.dart';
import 'phone_input.dart';

/// "Create account" for a new gym owner (backend: /v5/register/partner).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _referral = TextEditingController();
  String _dial = '+91';
  bool _busy = false;
  bool _agree = false;
  final _auth = getIt<AuthRepository>();

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _referral]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agree) {
      showToast(
        context,
        'Please accept the Terms and Conditions to continue',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    final phone = toE164(_phone.text, dial: _dial);
    final email = _email.text.trim().isEmpty
        ? null
        : _email.text.trim().toLowerCase();
    final referral = _referral.text.trim().isEmpty
        ? null
        : _referral.text.trim();
    try {
      final c = await _auth.registerPartner(
        name: _name.text.trim(),
        phone: phone,
        email: email,
        referralCode: referral,
      );
      if (!mounted) return;
      await context.push(
        R.loginOtp,
        extra: OtpArgs(
          challenge: c,
          target: phone,
          title: 'Confirm phone number',
          verify: _auth.verifyRegistration,
          resend: () => _auth.registerPartner(
            name: _name.text.trim(),
            phone: phone,
            email: email,
            referralCode: referral,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(String key) => launchUrl(
    Uri.parse(AppConfig.supportUrls[key]!),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                'Tell us about you',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create your DGymBook account, then set up your gym.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _name,
                label: 'Full name',
                hint: 'Enter name',
                textCapitalization: TextCapitalization.words,
                validator: V.name,
                textInputAction: TextInputAction.next,
              ),
              const Gap(16),
              PhoneInput(
                controller: _phone,
                dial: _dial,
                onDialChanged: (d) => setState(() => _dial = d),
              ),
              const Gap(16),
              AppTextField(
                controller: _email,
                label: 'Email (optional)',
                hint: 'Enter email',
                keyboardType: TextInputType.emailAddress,
                validator: V.email,
              ),
              const Gap(16),
              AppTextField(
                controller: _referral,
                label: 'Referral code (optional)',
                hint: 'Referral code',
                maxLength: 40,
              ),
              const Gap(16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agree,
                    onChanged: (v) => setState(() => _agree = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          children: [
                            const TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms & conditions',
                              style: const TextStyle(
                                color: AppColors.info,
                                fontWeight: FontWeight.w500,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _open('terms'),
                            ),
                            const TextSpan(text: ' and '),
                            TextSpan(
                              text: 'Privacy Policy',
                              style: const TextStyle(
                                color: AppColors.info,
                                fontWeight: FontWeight.w500,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => _open('privacy'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(20),
              LoadingButton(
                label: 'Send OTP',
                onPressed: _submit,
                loading: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
