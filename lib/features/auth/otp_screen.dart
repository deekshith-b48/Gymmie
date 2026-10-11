import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/models/user_gym.dart';
import 'login_screen.dart';
import 'otp_field.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.args});
  final OtpArgs args;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  late OtpChallenge _challenge = widget.args.challenge;
  Timer? _timer;
  late int _left = _challenge.resendIn;
  bool _busy = false;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _left = _challenge.resendIn;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _left = (_left - 1).clamp(0, 9999));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify([String? value]) async {
    final otp = (value ?? _code.text).trim();
    if (otp.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    try {
      final r = await widget.args.verify(_challenge.requestId, otp);
      if (!mounted) return;
      final done = widget.args.onVerified;
      if (done != null) {
        await done(context, r); // e.g. the gym-member flow
      } else {
        await getIt<SessionCubit>().signedIn(
          r as AuthResult,
        ); // the router redirects off the new session state
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _wrong = true);
      _code.clear();
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      final c = await widget.args.resend();
      if (!mounted) return;
      setState(() {
        _challenge = c;
        _wrong = false;
      });
      _code.clear();
      _startTimer();
      showToast(context, 'OTP sent successfully');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _challenge.maskedTarget ?? widget.args.target;
    final isEmail = _challenge.channel == 'email';
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              widget.args.title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isEmail
                  ? 'Enter the code sent to your email'
                  : 'Enter the 6-digit code we sent to $target',
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (isEmail)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  target,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 28),
            OtpField(controller: _code, onCompleted: _verify, error: _wrong),
            const SizedBox(height: 16),
            if (_challenge.devOtp != null)
              // Only a development backend returns the code; production servers never do.
              InfoBanner(
                'Development backend: your code is ${_challenge.devOtp}. Tap to fill it in.',
                icon: Icons.developer_mode,
                warning: true,
              ).withTap(() {
                _code.text = _challenge.devOtp!;
                HapticFeedback.selectionClick();
              }),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Verify & continue',
              onPressed: _verify,
              loading: _busy,
            ),
            const SizedBox(height: 16),
            Center(
              child: _left > 0
                  ? Text(
                      'Resend in 00:${_left.toString().padLeft(2, '0')}',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  : Column(
                      children: [
                        Text(
                          "Didn't receive OTP?",
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        TextButton(
                          onPressed: _resend,
                          child: const Text('Resend OTP'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on Widget {
  Widget withTap(VoidCallback f) => GestureDetector(onTap: f, child: this);
}
