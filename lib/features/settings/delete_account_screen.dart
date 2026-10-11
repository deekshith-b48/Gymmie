// Closing a staff or owner account: a code to the person's own phone, and typing DELETE. Gym owners are told to contact
// support, because closing a gym deletes the business's data.
import 'package:flutter/material.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/auth_repository.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _auth = getIt<AuthRepository>();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  OtpChallenge? _challenge;
  String? _blocked;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final c = await _auth.requestAccountDeletion();
      if (mounted) setState(() => _challenge = c);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409) {
        setState(() => _blocked = e.message);
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_confirm.text.trim() != 'DELETE') {
      showToast(context, 'Type DELETE to confirm', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.deleteAccount(requestId: _challenge!.requestId, otp: _code.text.trim());
      await getIt<SessionCubit>().signOut();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Delete my account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppCard(
          child: Text(
            'Your name, phone number, email and photo are erased and you are signed out everywhere. '
            'Records you created in a gym (members, payments, attendance) stay in that gym\'s books without your name.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        if (_blocked != null)
          InfoBanner(_blocked!, icon: Icons.storefront_outlined, warning: true)
        else if (_challenge == null)
          LoadingButton(label: 'Send me a code', onPressed: _send, loading: _busy, destructive: true)
        else ...[
          Text('We sent a code to ${_challenge!.maskedTarget ?? 'you'}.', style: TextStyle(color: AppColors.textSecondary)),
          if (_challenge!.devOtp != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Development backend: code ${_challenge!.devOtp}', style: TextStyle(color: AppColors.warning, fontSize: 12))),
          const SizedBox(height: 12),
          AppTextField(controller: _code, label: 'Code', keyboardType: TextInputType.number, maxLength: 8),
          const SizedBox(height: 12),
          AppTextField(controller: _confirm, label: 'Type DELETE to confirm'),
          const SizedBox(height: 20),
          LoadingButton(label: 'Delete my account', onPressed: _delete, loading: _busy, destructive: true),
        ],
      ],
    ),
  );
}
