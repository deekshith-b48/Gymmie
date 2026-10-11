// Member Login: the access code the gym gave the member. The server finds the gym and the member from the code, so nothing else
// is asked. A wrong, revoked or expired code gets one plain answer. After a good code the member app opens with a welcome.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/forms.dart';
import 'member_guide.dart';
import 'member_repository.dart';
import 'member_session_cubit.dart';

/// Upper-cases what is typed and keeps only letters, digits and hyphens.
class AccessCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    final t = v.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    return v.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length), composing: TextRange.empty);
  }
}

class MemberLoginScreen extends StatefulWidget {
  const MemberLoginScreen({super.key});
  @override
  State<MemberLoginScreen> createState() => _MemberLoginScreenState();
}

class _MemberLoginScreenState extends State<MemberLoginScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// True when the text could be a code: 6-digit gym code then 8 letters/digits (with or without hyphens).
  static bool looksLikeCode(String t) => RegExp(r'^\d{6}[A-Z2-9]{8}$').hasMatch(t.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));

  Future<void> _submit() async {
    if (_busy) return;
    if (!looksLikeCode(_code.text)) {
      setState(() => _error = 'Enter the full code your gym gave you, like 123456-ABCD-EFGH.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await getIt<MemberRepository>().loginWithCode(_code.text);
      await getIt<MemberSessionCubit>().signedIn(); // the root swaps to the member app, which opens with the welcome
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'You need to be online to sign in.' : (e.status == 429 ? 'Too many tries. Wait a few minutes and try again.' : e.message));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign you in. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(R.login))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/brand/logo_mark.png', height: 80)),
                  const SizedBox(height: 24),
                  Text('Member login', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Enter the access code your gym gave you.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [AccessCodeFormatter(), LengthLimitingTextInputFormatter(24)],
                    style: const TextStyle(fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                    decoration: InputDecoration(hintText: '123456-ABCD-EFGH', errorText: _error, errorMaxLines: 3),
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) { if (_error != null) setState(() => _error = null); },
                  ),
                  const SizedBox(height: 20),
                  LoadingButton(label: 'Sign in', onPressed: _submit, loading: _busy),
                  const SizedBox(height: 16),
                  Text(
                    'No code yet? Ask the front desk at your gym: they can give you one from your member page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Center(child: TextButton(onPressed: _busy ? null : () => context.go(R.login), child: const Text('Sign in with my phone number instead'))),
                  Center(child: TextButton(onPressed: () => showMemberGuide(context), child: const Text('What can I do in the member app?'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
