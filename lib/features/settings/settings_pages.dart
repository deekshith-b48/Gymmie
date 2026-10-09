import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../app/settings_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/config/app_config.dart';
import '../../core/l10n/l10n.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/images.dart';
import '../../core/util/json.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/models/plans.dart';
import '../../data/models/settings.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/gym_repository.dart';
import '../../data/repositories/members_repository.dart';

// ---------------------------------------------------------------------------------------------
class GymDetailsScreen extends StatefulWidget {
  const GymDetailsScreen({super.key});
  @override
  State<GymDetailsScreen> createState() => _GymDetailsScreenState();
}

class _GymDetailsScreenState extends State<GymDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final GymProfile _g = getIt<SessionCubit>().state.profile!;
  late final _address = TextEditingController(text: _g.address);
  late final _city = TextEditingController(text: _g.city);
  late final _state = TextEditingController(text: _g.state);
  late final _pincode = TextEditingController(text: _g.pincode);
  late final _phone = TextEditingController(
    text: _g.phone?.replaceFirst('+91', ''),
  );
  late final _email = TextEditingController(text: _g.email);
  PickedImage? _logo;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_address, _city, _state, _pincode, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = getIt<GymRepository>();
      await repo.updateGym(_g.id, {
        'address': _address.text.trim(),
        if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        if (_state.text.trim().isNotEmpty) 'state': _state.text.trim(),
        if (_pincode.text.trim().isNotEmpty) 'pincode': _pincode.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': toE164New(_phone.text),
        if (_email.text.trim().isNotEmpty)
          'email': _email.text.trim().toLowerCase(),
        if (_logo != null) 'logo': _logo!.toJson(),
      });
      await getIt<SessionCubit>().refreshProfile();
      if (!mounted) return;
      showToast(context, 'Edited successfully');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String toE164New(String v) => v.trim().startsWith('+')
      ? v.trim()
      : '+91${v.replaceAll(RegExp(r'\D'), '')}';

  @override
  Widget build(BuildContext context) {
    final canEdit = getIt<SessionCubit>().state.can(Perm.settingsWrite);
    return FormScaffold(
      title: 'Change Gym Details',
      formKey: _form,
      submitLabel: 'Update Gym',
      saving: _saving,
      onSubmit: canEdit
          ? _save
          : () => showToast(
              context,
              'You do not have sufficient permissions to access this',
              error: true,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: canEdit
                  ? () async {
                      final p = await pickImage(context, maxSide: 800);
                      if (p != null) setState(() => _logo = p);
                    }
                  : null,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.chip,
                    backgroundImage: _logo != null
                        ? MemoryImage(Uint8List.fromList(_logo!.bytes))
                        : null,
                    child: _logo != null
                        ? null
                        : ClipOval(
                            child: UserAvatar(
                              name: _g.name,
                              url: _g.logoUrl,
                              radius: 48,
                            ),
                          ),
                  ),
                  if (canEdit)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.navy,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Gap(6),
          const Center(
            child: Text(
              'Add gym logo',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const Gap(20),
          AppTextField(
            initialValue: _g.name,
            label: 'Gym name',
            enabled: false,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Please contact support to change your gym name',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const Gap(16),
          AppTextField(
            initialValue: _g.code,
            label: 'Gym Code',
            enabled: false,
          ),
          const Gap(16),
          AppTextField(
            controller: _address,
            label: 'Gym Address',
            hint: 'Enter your gym address',
            maxLines: 2,
            validator: (v) => (v ?? '').trim().length < 5
                ? 'Please enter a valid gym address'
                : null,
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: AppTextField(controller: _city, label: 'City'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(controller: _state, label: 'State'),
              ),
            ],
          ),
          const Gap(16),
          AppTextField(
            controller: _pincode,
            label: 'Pin Code',
            keyboardType: TextInputType.number,
            maxLength: 10,
          ),
          const Gap(16),
          AppTextField(
            controller: _phone,
            label: 'Gym phone',
            keyboardType: TextInputType.phone,
            validator: (v) => V.phone(v, optional: true),
          ),
          const Gap(16),
          AppTextField(
            controller: _email,
            label: 'Gym email',
            keyboardType: TextInputType.emailAddress,
            validator: V.email,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class TaxScreen extends StatefulWidget {
  const TaxScreen({super.key});
  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> {
  final _repo = getIt<PlansRepository>();
  late final AsyncCubit<List<TaxConfig>> _cubit = AsyncCubit(_repo.taxes);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _edit([TaxConfig? t]) async {
    final name = TextEditingController(text: t?.name ?? 'GST');
    final rate = TextEditingController(text: t == null ? '' : '${t.rate}');
    final number = TextEditingController(text: t?.taxNumber ?? '');
    var included = t?.isIncluded ?? false;
    final key = GlobalKey<FormState>();
    final res = await showAppSheet<Map<String, dynamic>>(
      context,
      title: t == null ? 'Add tax configuration' : 'Edit Tax',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: name,
                label: 'Tax name',
                hint: 'e.g. GST',
                validator: (v) => V.required(v, 'Enter name'),
              ),
              const Gap(12),
              AppTextField(
                controller: rate,
                label: 'Rate (%)',
                hint: 'Rate cannot be less than 0 nor greater than 100',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  return n == null || n < 0 || n > 100
                      ? 'Rate cannot be less than 0 nor greater than 100'
                      : null;
                },
              ),
              const Gap(12),
              AppTextField(
                controller: number,
                label: 'Tax No',
                hint: 'GSTIN / tax registration number',
                maxLength: 30,
              ),
              const Gap(8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Is tax included'),
                subtitle: Text(
                  included
                      ? 'Plan prices already include tax'
                      : 'Tax is added on top of plan prices',
                  style: const TextStyle(fontSize: 12),
                ),
                value: included,
                onChanged: (v) => set(() => included = v),
              ),
              const Gap(8),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) {
                    Navigator.pop(ctx, {
                      'name': name.text.trim(),
                      'rate': double.parse(rate.text.trim()),
                      'isIncluded': included,
                      if (number.text.trim().isNotEmpty)
                        'taxNumber': number.text.trim(),
                    });
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null || !mounted) return;
    final ok = await runOk(
      context,
      () async => t == null
          ? await _repo.createTax(res)
          : await _repo.updateTax(t.id, res),
      success: t == null ? 'Added successfully' : 'Edited successfully',
    );
    if (ok) {
      await getIt<SessionCubit>().refreshProfile();
      _cubit.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tax Information')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add tax'),
    ),
    body: AsyncBody<List<TaxConfig>>(
      cubit: _cubit,
      isEmpty: (d) => d.isEmpty,
      empty: const EmptyState(
        icon: Icons.percent,
        title: 'You do not have a tax number added.',
        message: 'Please configure your tax information. It applies to new memberships and sales.',
      ),
      builder: (context, list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            'Manage and customize the tax rules that apply to your memberships. Sample tax breakup for plan price 1000 is shown below each rule.',
          ),
          const Gap(12),
          for (final t in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _edit(t),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t.name} · ${t.rate % 1 == 0 ? t.rate.toInt() : t.rate}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (t.isDefault)
                          const Tag('Default', tone: Tone.success),
                        const SizedBox(width: 6),
                        Tag(t.isIncluded ? 'Included' : 'Excluded'),
                      ],
                    ),
                    if (t.taxNumber != null)
                      Text(
                        'Tax No: ${t.taxNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      t.isIncluded
                          ? 'Price 1000 → tax ${Fmt.money(1000 - 1000 / (1 + t.rate / 100))}, taxable ${Fmt.money(1000 / (1 + t.rate / 100))}'
                          : 'Price 1000 + tax ${Fmt.money(1000 * t.rate / 100)} = ${Fmt.money(1000 + 1000 * t.rate / 100)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Row(
                      children: [
                        if (!t.isDefault)
                          TextButton(
                            onPressed: () async {
                              if (await runOk(
                                context,
                                () => _repo
                                    .updateTax(t.id, {'isDefault': true})
                                    .then((_) {}),
                              )) {
                                _cubit.refresh();
                              }
                            },
                            child: const Text('Make default'),
                          ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: () async {
                            if (!await confirmDialog(
                                  context,
                                  title: 'Delete Tax Config',
                                  message: 'Are you sure you want to delete this tax configuration?',
                                  confirmLabel: 'Delete',
                                  destructive: true,
                                ) ||
                                !context.mounted) {
                              return;
                            }
                            if (await runOk(
                              context,
                              () => _repo.deleteTax(t.id),
                              success: 'Tax config deleted successfully',
                            )) {
                              _cubit.refresh();
                            }
                          },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------------------
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});
  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  late final Set<String> _active = {
    ...getIt<SessionCubit>().state.profile!.activePaymentTypes,
  };
  late String _default =
      getIt<SessionCubit>().state.profile!.defaultPaymentType;
  bool _saving = false;

  Future<void> _save() async {
    if (_active.isEmpty) {
      return showToast(
        context,
        'Please select at least one payment method',
        error: true,
      );
    }
    if (!_active.contains(_default)) {
      return showToast(
        context,
        'Please select a default payment method from selected methods',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      await getIt<GymRepository>().setPaymentMethods(
        _active.toList(),
        _default,
      );
      await getIt<SessionCubit>().refreshProfile();
      if (mounted) {
        showToast(context, 'Payment methods saved successfully');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = getIt<SessionCubit>().state.can(Perm.settingsWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Methods')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Available Methods',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Gap(8),
          for (final t in allPaymentTypes)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Checkbox(
                  value: _active.contains(t),
                  onChanged: canEdit
                      ? (v) => setState(
                          () => v == true ? _active.add(t) : _active.remove(t),
                        )
                      : null,
                ),
                title: Text(paymentTypeLabel(t)),
                trailing: _active.contains(t)
                    ? (_default == t
                          ? const Tag('Default', tone: Tone.success)
                          : TextButton(
                              onPressed: canEdit
                                  ? () => setState(() => _default = t)
                                  : null,
                              child: const Text('Set default'),
                            ))
                    : null,
              ),
            ),
          const Gap(16),
          if (canEdit)
            LoadingButton(label: 'Save', onPressed: _save, loading: _saving),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class FeaturesScreen extends StatefulWidget {
  const FeaturesScreen({super.key});
  @override
  State<FeaturesScreen> createState() => _FeaturesScreenState();
}

class _FeaturesScreenState extends State<FeaturesScreen> {
  late final AsyncCubit<List<FeatureItem>> _cubit = AsyncCubit(
    getIt<GymRepository>().features,
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _toggle(FeatureItem f, bool v) async {
    final r = await runWithProgress(
      context,
      () => getIt<GymRepository>().setFeature(f.key, v),
    );
    if (r != null) {
      _cubit.set(r);
      await getIt<SessionCubit>().refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App Features')),
    body: AsyncBody<List<FeatureItem>>(
      cubit: _cubit,
      builder: (context, list) {
        final cats = {for (final f in list) f.category};
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            for (final c in cats)
              MenuGroup(
                title: c,
                children: [
                  for (final f in list.where((x) => x.category == c))
                    SwitchListTile(
                      title: Text(
                        f.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        f.adminEnabled
                            ? f.description
                            : '${f.description}\nNot available for your gym yet.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: f.enabled,
                      onChanged: f.adminEnabled ? (v) => _toggle(f, v) : null,
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      bloc: getIt<SessionCubit>(),
      builder: (context, s) {
        final g = s.profile!;
        final canEdit = s.can(Perm.settingsWrite);
        Future<void> set({bool? card, bool? sound}) async {
          if (await runOk(
            context,
            () => getIt<GymRepository>().setPreferences(
              simpleMemberCard: card,
              renewalSound: sound,
            ),
          )) {
            await getIt<SessionCubit>().refreshProfile();
          }
        }

        return Scaffold(
          appBar: AppBar(title: const Text('App Preferences')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (s.feature(Feat.simpleCard))
                Card(
                  child: SwitchListTile(
                    title: const Text('Simple Member Card'),
                    subtitle: const Text(
                      'Enable simple member card design',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: g.simpleMemberCard,
                    onChanged: canEdit ? (v) => set(card: v) : null,
                  ),
                ),
              if (s.feature(Feat.renewalSound))
                Card(
                  child: SwitchListTile(
                    title: const Text('Renewal Sound'),
                    subtitle: const Text(
                      'Enable renewal sound notification',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: g.renewalSound,
                    onChanged: canEdit ? (v) => set(sound: v) : null,
                  ),
                ),
              if (!s.feature(Feat.simpleCard) && !s.feature(Feat.renewalSound))
                const EmptyState(
                  compact: true,
                  icon: Icons.tune,
                  title: 'Nothing to configure',
                  message: 'Turn on "Simple Member Card" or "Renewal Sound" under App Features.',
                ),
            ],
          ),
        );
      },
    );
  }
}

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<SettingsCubit, AppPrefs>(
    bloc: getIt<SettingsCubit>(),
    builder: (context, p) => Scaffold(
      appBar: AppBar(title: Text('Choose your language'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const InfoBanner(
            'This will change the language of the entire app to your selected language. Screens not yet translated stay in English.',
          ),
          const Gap(12),
          for (final e in L10n.supported.entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  e.value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(e.key == 'en' ? 'English' : e.key.toUpperCase()),
                trailing: p.language == e.key
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : null,
                onTap: () async {
                  await getIt<SettingsCubit>().setLanguage(e.key);
                  final u = getIt<SessionCubit>().state.user;
                  if (u != null) {
                    try {
                      getIt<SessionCubit>().updateUser(
                        await getIt<AuthRepository>().updateProfile({
                          'language': e.key,
                        }),
                      );
                    } catch (_) {}
                  }
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<SettingsCubit, AppPrefs>(
    bloc: getIt<SettingsCubit>(),
    builder: (context, p) => Scaffold(
      appBar: AppBar(title: Text('Change Theme'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (m, l, i) in [
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
            (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
          ])
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(i),
                title: Text(l.tr),
                trailing: p.themeMode == m
                    ? const Icon(Icons.check_circle, color: AppColors.success)
                    : null,
                onTap: () => getIt<SettingsCubit>().setTheme(m),
              ),
            ),
        ],
      ),
    ),
  );
}

class TimezoneScreen extends StatefulWidget {
  const TimezoneScreen({super.key});
  @override
  State<TimezoneScreen> createState() => _TimezoneScreenState();
}

class _TimezoneScreenState extends State<TimezoneScreen> {
  late final AsyncCubit<List<String>> _cubit = AsyncCubit(
    getIt<GymRepository>().timezones,
  );
  String _q = '';

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = getIt<SessionCubit>().state.profile!.timezone;
    return Scaffold(
      appBar: AppBar(title: const Text('Time Zone')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search timezones',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: AsyncBody<List<String>>(
              cubit: _cubit,
              refreshable: false,
              builder: (context, all) {
                final list = all
                    .where((z) => z.toLowerCase().contains(_q))
                    .toList();
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(list[i]),
                    trailing: list[i] == current
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                          )
                        : null,
                    onTap: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Set Time zone',
                        message:
                            'Select the timezone you want to use for the app: ${list[i]}',
                        confirmLabel: 'Set',
                      );
                      if (!ok || !context.mounted) return;
                      if (await runOk(
                        context,
                        () => getIt<GymRepository>().updateGym(
                          getIt<SessionCubit>().state.profile!.id,
                          {'timezone': list[i]},
                        ),
                        success: 'Timezone updated to ${list[i]}',
                      )) {
                        await getIt<SessionCubit>().refreshProfile();
                        if (context.mounted) context.pop();
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _auth = getIt<AuthRepository>();
  late final _name = TextEditingController(
    text: getIt<SessionCubit>().state.user?.name,
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _verifyContact(String channel) async {
    final c = TextEditingController();
    final target = await promptText(
      context,
      title: channel == 'email'
          ? 'Please Verify your Email'
          : 'Please verify your phone',
      label: channel == 'email' ? 'Email' : 'Phone number',
      hint: channel == 'email' ? 'Enter email' : 'Enter Phone number',
      confirmLabel: 'Send OTP',
      keyboardType: channel == 'email'
          ? TextInputType.emailAddress
          : TextInputType.phone,
      validator: (v) =>
          channel == 'email' ? V.email(v, optional: false) : V.phone(v),
    );
    c.dispose();
    if (target == null || !mounted) return;
    final value = channel == 'email'
        ? target.toLowerCase()
        : (target.startsWith('+')
              ? target
              : '+91${target.replaceAll(RegExp(r'\D'), '')}');
    try {
      final ch = await _auth.requestContactOtp(channel: channel, target: value);
      if (!mounted) return;
      final code = await promptText(
        context,
        title: 'Enter the OTP',
        message: ch.devOtp != null
            ? 'Development backend: your code is ${ch.devOtp}'
            : 'Enter the 6-digit code we sent to ${ch.maskedTarget ?? value}',
        label: 'OTP',
        hint: '6-digit code',
        confirmLabel: 'Verify',
        keyboardType: TextInputType.number,
        validator: V.otp,
      );
      if (code == null || !mounted) return;
      final u = await runWithProgress(
        context,
        () => _auth.verifyContactOtp(ch.requestId, code),
        success: 'OTP verified successfully',
      );
      if (u != null) {
        getIt<SessionCubit>().updateUser(u);
        setState(() {});
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      getIt<SessionCubit>().updateUser(
        await _auth.updateProfile({'name': _name.text.trim()}),
      );
      if (mounted) showToast(context, 'Edited successfully');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _photo() async {
    final p = await pickImage(context, maxSide: 800);
    if (p == null || !mounted) return;
    final u = await runWithProgress(
      context,
      () => _auth.uploadProfilePhoto(p.bytes, p.contentType),
      success: 'Edited successfully',
    );
    if (u != null) {
      getIt<SessionCubit>().updateUser(u);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = getIt<SessionCubit>().state.user!;
    return FormScaffold(
      title: 'Edit Profile',
      formKey: _form,
      submitLabel: 'Save',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: _photo,
              child: Stack(
                children: [
                  UserAvatar(name: u.name, url: u.photoUrl, radius: 48),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.navy,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(8),
          const Center(
            child: Text(
              'Add your photo',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const Gap(20),
          AppTextField(
            controller: _name,
            label: 'Full name',
            textCapitalization: TextCapitalization.words,
            validator: V.name,
          ),
          const Gap(16),
          _Contact(
            label: 'Phone',
            value: u.phone,
            verified: u.phoneVerified,
            onTap: () => _verifyContact('sms'),
          ),
          const Gap(12),
          _Contact(
            label: 'Email',
            value: u.email,
            verified: u.emailVerified,
            onTap: () => _verifyContact('email'),
          ),
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({
    required this.label,
    required this.value,
    required this.verified,
    required this.onTap,
  });
  final String label;
  final String? value;
  final bool verified;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value ?? 'Not added',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        if (value != null && verified)
          const Tag('Verified', tone: Tone.success, icon: Icons.verified)
        else
          TextButton(
            onPressed: onTap,
            child: Text(value == null ? 'Add' : 'Verify'),
          ),
        if (value != null && verified)
          TextButton(onPressed: onTap, child: const Text('Change')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------------------------
class UpiScreen extends StatefulWidget {
  const UpiScreen({super.key});
  @override
  State<UpiScreen> createState() => _UpiScreenState();
}

class _UpiScreenState extends State<UpiScreen> {
  late final _upi = TextEditingController(
    text: getIt<SessionCubit>().state.profile?.upiId,
  );
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  static final _re = RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z]{2,64}$');

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await getIt<GymRepository>().updateGym(
        getIt<SessionCubit>().state.profile!.id,
        {'upiId': _upi.text.trim()},
      );
      await getIt<SessionCubit>().refreshProfile();
      if (mounted) showToast(context, 'UPI ID saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = getIt<SessionCubit>().state.profile!;
    final valid = _re.hasMatch(_upi.text.trim());
    return FormScaffold(
      title: 'Gym UPI QR',
      formKey: _form,
      submitLabel: 'Save',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        children: [
          AppTextField(
            controller: _upi,
            label: 'UPI ID (VPA)',
            hint: 'UPI ID or VPA (e.g. merchant@bank)',
            onChanged: (_) => setState(() {}),
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Enter a UPI ID'
                : (_re.hasMatch(v!.trim())
                      ? null
                      : 'UPI ID or VPA (e.g. merchant@bank)'),
          ),
          const Gap(24),
          if (valid) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: QrImageView(
                data:
                    'upi://pay?pa=${_upi.text.trim()}&pn=${Uri.encodeComponent(g.name)}&cu=INR',
                size: 220,
              ),
            ),
            const Gap(10),
            Text(
              'UPI payment QR for ${g.name}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const Text(
              'Shown to members when they renew. Check the amount in your UPI app before confirming a payment.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  final _repo = getIt<GymRepository>();
  late final AsyncCubit<({Json? current, List<SubscriptionPlanOption> plans})>
  _plans = AsyncCubit(_repo.subscriptions);
  late final AsyncCubit<SubscriptionUsage> _usage = AsyncCubit(_repo.usage);
  late final AsyncCubit<List<PaymentOrder>> _history = AsyncCubit(
    _repo.subscriptionHistory,
  );
  String? _pendingOrder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plans.close();
    _usage.close();
    _history.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOrder != null) {
      _checkOrder();
    }
  }

  Future<void> _checkOrder() async {
    final id = _pendingOrder;
    if (id == null) return;
    try {
      final o = await _repo.order(id);
      if (o.status == 'paid') {
        _pendingOrder = null;
        await getIt<SessionCubit>().refreshProfile();
        _plans.refresh();
        _usage.refresh();
        _history.refresh();
        if (mounted) showToast(context, 'Membership Renewal Success');
      } else if (o.status == 'failed') {
        _pendingOrder = null;
        if (mounted) {
          showToast(
            context,
            "We couldn't complete your renewal. Please try again from the app or contact support if the problem persists.",
            error: true,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _buy(SubscriptionPlanOption p) async {
    final ok = await confirmDialog(
      context,
      title: 'Confirm Plan',
      message:
          '${p.name} for ${Fmt.money(p.price)}. You will be taken to the payment page.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    final o = await runWithProgress(
      context,
      () => _repo.subscriptionOrder(p.id),
    );
    if (o == null || o.paymentUrl == null || !mounted) return;
    _pendingOrder = o.id;
    await Launch.url(context, o.paymentUrl!);
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final sub = s.profile?.subscription;
    final canBuy = s.can(Perm.settingsWrite);
    return Scaffold(
      appBar: AppBar(title: Text('Subscription'.tr)),
      body: RefreshIndicator(
        onRefresh: () async {
          await getIt<SessionCubit>().refreshProfile();
          await Future.wait([
            _plans.refresh(),
            _usage.refresh(),
            _history.refresh(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              color: sub?.expired == true ? AppColors.dangerTint : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sub?.plan ?? 'No plan',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Tag(
                        sub?.expired == true ? 'Expired' : 'Active',
                        tone: sub?.expired == true ? Tone.danger : Tone.success,
                      ),
                    ],
                  ),
                  if (sub?.endsAt != null)
                    Text(
                      sub!.expired
                          ? 'Expired on ${Fmt.date(sub.endsAt)}'
                          : 'Valid until ${Fmt.date(sub.endsAt)}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            const SectionTitle(
              'Subscription Usage',
              padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
            ),
            BlocProvider.value(
              value: _usage,
              child:
                  BlocBuilder<
                    AsyncCubit<SubscriptionUsage>,
                    AsyncState<SubscriptionUsage>
                  >(
                    builder: (context, st) {
                      final u = st.data;
                      if (u == null) {
                        return const AppCard(
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(),
                          ),
                        );
                      }
                      Widget row(String l, UsageItem i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(l)),
                                Text(
                                  '${i.used}${i.limit == null ? '' : ' / ${i.limit}'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: i.ratio,
                                minHeight: 6,
                                backgroundColor: AppColors.neutralTint,
                                color: i.ratio > 0.9
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      );
                      return AppCard(
                        child: Column(
                          children: [
                            row('Membership plans', u.plans),
                            row('Staff', u.staff),
                            row('Members', u.members),
                          ],
                        ),
                      );
                    },
                  ),
            ),
            const SectionTitle(
              'Plans',
              padding: EdgeInsets.fromLTRB(2, 20, 2, 4),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Development catalogue and a simulated payment provider. Prices are placeholders.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
            BlocProvider.value(
              value: _plans,
              child:
                  BlocBuilder<
                    AsyncCubit<
                      ({Json? current, List<SubscriptionPlanOption> plans})
                    >,
                    AsyncState<
                      ({Json? current, List<SubscriptionPlanOption> plans})
                    >
                  >(
                    builder: (context, st) {
                      final d = st.data;
                      if (d == null) return const SizedBox.shrink();
                      return Column(
                        children: [
                          for (final p in d.plans)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AppCard(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${p.limits['members'] ?? '-'} members · ${p.limits['staff'] ?? '-'} staff · ${p.limits['plans'] ?? '-'} plans',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          Fmt.money(p.price),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (canBuy)
                                          TextButton(
                                            onPressed: () => _buy(p),
                                            child: Text(
                                              sub?.plan == p.plan
                                                  ? 'Renew Now'
                                                  : 'Upgrade now',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
            ),
            const SectionTitle(
              'Subscription History',
              padding: EdgeInsets.fromLTRB(2, 12, 2, 8),
            ),
            BlocProvider.value(
              value: _history,
              child:
                  BlocBuilder<
                    AsyncCubit<List<PaymentOrder>>,
                    AsyncState<List<PaymentOrder>>
                  >(
                    builder: (context, st) {
                      final h = st.data ?? const [];
                      if (h.isEmpty) {
                        return const AppCard(
                          child: Text(
                            'No payments yet.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final o in h)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(o.description ?? 'Subscription'),
                                          Text(
                                            Fmt.dateTime(o.createdAt),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(Fmt.money(o.amount)),
                                    const SizedBox(width: 8),
                                    Tag(
                                      o.status,
                                      tone: o.status == 'paid'
                                          ? Tone.success
                                          : (o.status == 'failed'
                                                ? Tone.danger
                                                : Tone.warning),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final cfg = getIt<AppConfig>();
    return Scaffold(
      appBar: AppBar(title: Text('Help Center'.tr)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          MenuGroup(
            title: 'Support and Information',
            children: [
              MenuTile(
                icon: Icons.help_outline,
                title: 'Help Center'.tr,
                onTap: () => Launch.url(
                  context,
                  s.settings.helpCenterUrl ?? AppConfig.supportUrls['faq']!,
                ),
              ),
              MenuTile(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () =>
                    Launch.url(context, AppConfig.supportUrls['about']!),
              ),
              MenuTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy'.tr,
                onTap: () =>
                    Launch.url(context, AppConfig.supportUrls['privacy']!),
              ),
              MenuTile(
                icon: Icons.description_outlined,
                title: 'Terms and Conditions'.tr,
                onTap: () =>
                    Launch.url(context, AppConfig.supportUrls['terms']!),
              ),
              MenuTile(
                icon: Icons.currency_exchange,
                title: 'Refund and Cancellation',
                onTap: () =>
                    Launch.url(context, AppConfig.supportUrls['refund']!),
              ),
              MenuTile(
                icon: Icons.new_releases_outlined,
                title: 'Change Logs',
                onTap: () =>
                    Launch.url(context, AppConfig.supportUrls['changelogs']!),
              ),
              if ((s.settings.companyWhatsappNumber ?? '').isNotEmpty)
                MenuTile(
                  icon: Icons.chat_outlined,
                  title: 'Contact Support',
                  onTap: () => Launch.whatsApp(
                    context,
                    s.settings.companyWhatsappNumber!,
                    text:
                        'I am looking for support (gym code ${s.profile?.code ?? ''}).',
                  ),
                ),
              MenuTile(
                icon: Icons.system_update_alt,
                title: 'Check for updates',
                onTap: () async {
                  final info = await PackageInfo.fromPlatform();
                  if (!context.mounted) return;
                  final min = s.settings.minimumSuggestedAppVersion;
                  showToast(
                    context,
                    compareVersions(info.version, min) >= 0
                        ? 'Your app is up to date'
                        : 'A newer version ($min) is available',
                  );
                },
              ),
            ],
          ),
          MenuGroup(
            children: [
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) => MenuTile(
                  icon: Icons.tag,
                  title: 'Version',
                  subtitle: snap.hasData
                      ? '${snap.data!.version} (${snap.data!.buildNumber})'
                      : '',
                ),
              ),
              if (cfg.devToolsEnabled)
                MenuTile(
                  icon: Icons.developer_mode,
                  title: 'Developer tools',
                  onTap: () => context.push('/settings/dev'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DevToolsScreen extends StatelessWidget {
  const DevToolsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final cfg = getIt<AppConfig>();
    final s = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                InfoRow('Backend URL', cfg.baseUrl),
                InfoRow('Server environment', s.settings.environment),
                InfoRow(
                  'Dev OTP enabled',
                  s.settings.devOtpEnabled ? 'yes' : 'no',
                ),
                InfoRow(
                  'Firebase',
                  AppConfig.firebaseConfigured
                      ? 'configured'
                      : 'not configured',
                ),
                InfoRow(
                  'Sentry',
                  AppConfig.sentryDsn.isNotEmpty ? 'enabled' : 'off',
                ),
                InfoRow('Gym id', s.profile?.id),
              ],
            ),
          ),
          const Gap(12),
          FilledButton.icon(
            onPressed: () => context.push('/backend-setup'),
            icon: const Icon(Icons.dns_outlined),
            label: const Text('Change URL'),
          ),
          const Gap(8),
          OutlinedButton(
            onPressed: () async {
              await cfg.setDevToolsEnabled(false);
              if (context.mounted) context.pop();
            },
            child: const Text('Hide developer tools'),
          ),
        ],
      ),
    );
  }
}

// Blood donors: members who share a blood group ("Find Blood Donors").
class BloodDonorsScreen extends StatefulWidget {
  const BloodDonorsScreen({super.key});
  @override
  State<BloodDonorsScreen> createState() => _BloodDonorsScreenState();
}

class _BloodDonorsScreenState extends State<BloodDonorsScreen> {
  String? _group;
  late final AsyncCubit<List<Json>> _cubit = AsyncCubit(
    () async => (await getIt<MembersRepository>().list(1, 200, {
      'sort': 'nameAsc',
    })).list,
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find Blood Donors')),
    body: AsyncBody<List<Json>>(
      cubit: _cubit,
      builder: (context, all) {
        final groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
        final list = all
            .where(
              (m) =>
                  m['bloodGroup'] != null &&
                  (_group == null || m['bloodGroup'] == _group),
            )
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PillChip(
                    label: 'All',
                    selected: _group == null,
                    onTap: () => setState(() => _group = null),
                  ),
                  for (final g in groups)
                    PillChip(
                      label: g,
                      selected: _group == g,
                      onTap: () => setState(() => _group = g),
                    ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.bloodtype_outlined,
                      title: 'No donors found',
                      message: 'Members with a blood group on their profile appear here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = list[i];
                        return AppCard(
                          onTap: () => context.push('/members/${m['id']}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              UserAvatar(
                                name: '${m['name']}',
                                url: m['photoUrl'] as String?,
                                radius: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${m['name']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${m['phone']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Tag('${m['bloodGroup']}', tone: Tone.danger),
                              IconButton(
                                icon: const Icon(Icons.call_outlined),
                                onPressed: () =>
                                    Launch.call(context, '${m['phone']}'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
