// The gym's OWN payment account, for collecting members' fees online (Razorpay). Optional: "Skip for now" changes nothing else,
// and everything here is separate from what the gym pays Gymmie for its subscription.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/state/async_cubit.dart' show toApiException;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/settings.dart';
import '../../data/repositories/gym_repository.dart';

class PaymentSetupScreen extends StatefulWidget {
  /// [onboarding]: shown once after the gym is set up, with "Skip for now".
  const PaymentSetupScreen({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  State<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends State<PaymentSetupScreen> {
  final _repo = getIt<GymRepository>();
  final _form = GlobalKey<FormState>();
  final _keyId = TextEditingController();
  final _secret = TextEditingController();
  final _webhook = TextEditingController();
  PaymentSetup? _setup;
  Object? _error;
  bool _busy = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyId.dispose();
    _secret.dispose();
    _webhook.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.paymentSetup();
      if (mounted) setState(() { _setup = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _afterChange() async {
    await getIt<SessionCubit>().refreshProfile(); // the router moves on from the prompt when the choice is recorded
    await _load();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _repo.connectPayments(keyId: _keyId.text.trim(), keySecret: _secret.text.trim(), webhookSecret: _webhook.text.trim());
      if (!mounted) return;
      _secret.clear();
      _webhook.clear();
      showToast(context, 'Payments connected');
      setState(() => _editing = false);
      await _afterChange();
      if (mounted && widget.onboarding) context.go(R.home);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await _repo.skipPaymentSetup();
      await getIt<SessionCubit>().refreshProfile();
      if (mounted) context.go(R.home);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (!await confirmDialog(context, title: 'Disconnect payments?', message: 'Members will no longer be able to pay online. Payments already received stay in your records.', confirmLabel: 'Disconnect', destructive: true)) return;
    if (!mounted) return;
    final ok = await runWithProgress(context, () async { await _repo.disconnectPayments(); return true; }, success: 'Payments disconnected');
    if (ok == true) await _afterChange();
  }

  Widget _copyRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        SelectableText(value, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
      ])),
      IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: 'Copy', onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (mounted) showToast(context, 'Copied');
      }),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    final canEdit = s?.canEdit ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Collect fees online' : 'Online payments'),
        automaticallyImplyLeading: !widget.onboarding,
        // the first thing on the screen, so it is never missed: this step is optional
        actions: [if (widget.onboarding) TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip for now'))],
      ),
      body: SafeArea(
        child: s == null
            ? (_error != null ? ErrorState(error: toApiException(_error!), onRetry: _load) : const LoadingBox())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.account_balance_wallet_outlined, color: AppColors.navy),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Let members pay their fees online', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Connect your own Razorpay account. Members pay you directly (UPI, cards, net banking) and Gymmie records the payment against their dues. '
                        'This is separate from your Gymmie subscription, and it is optional: cash, UPI QR and manual entry keep working without it.',
                        style: TextStyle(color: AppColors.textSecondary, height: 1.45, fontSize: 13),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (s.active && !_editing) ...[
                    AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Expanded(child: Text('Razorpay connected', style: TextStyle(fontWeight: FontWeight.w600))),
                          Tag(s.mode == 'live' ? 'Live' : 'Test mode', tone: s.mode == 'live' ? Tone.success : Tone.warning),
                        ]),
                        const SizedBox(height: 6),
                        Text('Key ${s.keyId ?? ''}', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        if (s.verifiedAt != null) Text('Verified ${s.verifiedAt!.split('T').first}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        _copyRow('Webhook URL (set in Razorpay)', s.webhookUrl),
                        const SizedBox(height: 8),
                        Text('When a member owes money, open their page and tap "Collect online" to get a payment link.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
                        if (canEdit) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: () => setState(() => _editing = true), child: const Text('Replace keys'))),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger), onPressed: _disconnect, child: const Text('Disconnect'))),
                          ]),
                        ],
                      ]),
                    ),
                  ] else if (!canEdit)
                    const InfoBanner('Only the gym owner can connect a payment account.', icon: Icons.lock_outline)
                  else
                    Form(
                      key: _form,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        AppCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('1. Create keys', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('In your Razorpay Dashboard: Account & Settings > API keys. Copy the Key ID and Key Secret.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
                            const SizedBox(height: 10),
                            const Text('2. Add a webhook', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('Account & Settings > Webhooks > Add. Use this address and the event "${s.webhookEvent}", and choose your own secret.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
                            _copyRow('Webhook URL', s.webhookUrl),
                            const SizedBox(height: 10),
                            const Text('3. Paste them below', style: TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        AppTextField(controller: _keyId, label: 'Key ID', hint: 'rzp_live_…', validator: (v) => RegExp(r'^rzp_(test|live)_[A-Za-z0-9]{6,40}$').hasMatch((v ?? '').trim()) ? null : 'Enter your Razorpay Key ID (rzp_test_… or rzp_live_…)'),
                        const SizedBox(height: 12),
                        AppTextField(controller: _secret, label: 'Key Secret', obscure: true, validator: (v) => (v ?? '').trim().length < 8 ? 'Enter your Key Secret' : null),
                        const SizedBox(height: 12),
                        AppTextField(controller: _webhook, label: 'Webhook secret', obscure: true, validator: (v) => (v ?? '').trim().length < 8 ? 'Enter the secret you chose for the webhook' : null),
                        const SizedBox(height: 16),
                        LoadingButton(label: 'Verify and connect', onPressed: _save, loading: _busy),
                        if (_editing) TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
                      ]),
                    ),
                  if (widget.onboarding) ...[
                    const SizedBox(height: 8),
                    Center(child: TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip for now'))),
                    Center(child: Text('You can set this up later in Settings > Online payments.', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                  ],
                ],
              ),
      ),
    );
  }
}
