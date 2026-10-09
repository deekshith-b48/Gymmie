import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/routes.dart';
import '../../app/session_cubit.dart';
import '../../core/config/app_config.dart';
import '../../core/data/countries.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/json.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/repositories/auth_repository.dart';

/// Pincode lookup used by the original app (`api.postalpincode.in`). Only India is supported by the service;
/// if it cannot be reached we accept a well-formed pincode instead of blocking set-up.
class PincodeResult {
  const PincodeResult({
    this.city,
    this.state,
    this.verified = false,
    this.unreachable = false,
  });
  final String? city;
  final String? state;
  final bool verified;
  final bool unreachable;
}

Future<PincodeResult> lookupPincode(String pin, {Dio? dio}) async {
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) return const PincodeResult();
  try {
    final r =
        await (dio ??
                Dio(
                  BaseOptions(
                    connectTimeout: const Duration(seconds: 6),
                    receiveTimeout: const Duration(seconds: 8),
                  ),
                ))
            .get<dynamic>('${AppConfig.pincodeLookupUrl}$pin');
    final d = r.data;
    if (d is List &&
        d.isNotEmpty &&
        d.first is Map &&
        (d.first as Map)['Status'] == 'Success') {
      final po = ((d.first as Map)['PostOffice'] as List?)?.firstOrNull;
      if (po is Map) {
        return PincodeResult(
          city: (po['District'] ?? po['Block'])?.toString(),
          state: po['State']?.toString(),
          verified: true,
        );
      }
    }
    return const PincodeResult();
  } catch (_) {
    return const PincodeResult(unreachable: true);
  }
}

/// Creates the first gym after sign-up (or an additional gym for an existing owner).
class GymSetupScreen extends StatefulWidget {
  const GymSetupScreen({super.key, this.addAnother = false});
  final bool addAnother;

  @override
  State<GymSetupScreen> createState() => _GymSetupScreenState();
}

class _GymSetupScreenState extends State<GymSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  String _country = 'IN';
  bool _busy = false;
  bool _checkingPin = false;
  String? _pinNote;
  final _auth = getIt<AuthRepository>();

  @override
  void dispose() {
    for (final c in [_name, _address, _pincode, _city, _state]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyPin() async {
    final pin = _pincode.text.trim();
    if (_country != 'IN' || pin.length != 6) {
      setState(() => _pinNote = null);
      return;
    }
    setState(() => _checkingPin = true);
    final r = await lookupPincode(pin);
    if (!mounted) return;
    setState(() {
      _checkingPin = false;
      if (r.verified) {
        _city.text = r.city ?? _city.text;
        _state.text = r.state ?? _state.text;
        _pinNote = null;
      } else {
        _pinNote = r.unreachable
            ? 'Could not verify pincode right now. You can continue and edit it later.'
            : 'Pincode is not verified. Please enter a valid pincode';
      }
    });
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    if (_pinNote != null && !_pinNote!.startsWith('Could not')) {
      showToast(context, _pinNote!, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final body = compact({
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'pincode': _pincode.text.trim().isEmpty ? null : _pincode.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'state': _state.text.trim().isEmpty ? null : _state.text.trim(),
        'country': _country,
      });
      final session = getIt<SessionCubit>();
      final gym = widget.addAnother
          ? await _auth.addGym(body)
          : await _auth.createFirstGym(body);
      await session.afterGymCreated(gym);
      if (mounted) context.go(R.home);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!widget.addAnother)
            TextButton(
              onPressed: () => getIt<SessionCubit>().signOut(),
              child: const Text('Log out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(
                widget.addAnother ? 'Add new gym' : 'Set up your gym',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                "Your gym name can't be changed later without contacting support.",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const Gap(24),
              AppTextField(
                controller: _name,
                label: 'Gym Name',
                hint: 'Enter name',
                textCapitalization: TextCapitalization.words,
                validator: (v) => V.name(v, label: 'a valid gym name'),
              ),
              const Gap(16),
              AppTextField(
                controller: _address,
                label: 'Gym Address',
                hint: 'Enter your gym address',
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v ?? '').trim().length < 5
                    ? 'Please enter a valid gym address'
                    : null,
              ),
              const Gap(16),
              DropdownField<String>(
                label: 'Select your Country',
                value: _country,
                items: countries.map((c) => c.code).toList(),
                labelOf: (c) => countries.firstWhere((x) => x.code == c).name,
                onChanged: (v) => setState(() {
                  _country = v ?? 'IN';
                  _pinNote = null;
                }),
              ),
              const Gap(16),
              AppTextField(
                controller: _pincode,
                label: 'Pin Code',
                hint: 'Enter pincode',
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
                ],
                onChanged: (v) {
                  if (v.length == 6) _verifyPin();
                },
                suffix: _checkingPin
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                errorText:
                    _pinNote != null && !_pinNote!.startsWith('Could not')
                    ? _pinNote
                    : null,
              ),
              if (_pinNote != null && _pinNote!.startsWith('Could not'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _pinNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              const Gap(16),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _city,
                      label: 'City',
                      hint: 'City',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: _state,
                      label: 'State',
                      hint: 'State',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const Gap(28),
              LoadingButton(
                label: 'Create my gym',
                onPressed: _create,
                loading: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
