import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/auth/permissions.dart';
import '../../core/data/countries.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';
import '../auth/phone_input.dart';
import '../../app/session_cubit.dart';

const _roleHelp = {
  'manager': 'Runs the gym day to day: members, plans, finance, broadcasts. Cannot manage staff.',
  'staff': 'Front desk: members, payments, attendance and sales. No settings.',
  'trainer': 'Sees only assigned members; manages plans, working hours and session bookings.',
};

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _repo = getIt<StaffRepository>();
  late final AsyncCubit<List<StaffMember>> _cubit = AsyncCubit(
    () => _repo.staff(),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.staffWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Staff')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/staff/new');
                _cubit.refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add New Staff'),
            )
          : null,
      body: AsyncBody<List<StaffMember>>(
        cubit: _cubit,
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final m = list[i];
            return AppCard(
              onTap: canWrite && m.role != 'owner' ? () => _actions(m) : null,
              child: Row(
                children: [
                  UserAvatar(name: m.name, url: m.photoUrl, radius: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          m.phone ?? m.email ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            Tag(
                              roleLabel(m.role),
                              tone: m.role == 'owner' ? Tone.navy : Tone.info,
                            ),
                            if (m.invited)
                              const Tag(
                                'Invitation Pending',
                                tone: Tone.warning,
                              ),
                            if (m.memberCount != null)
                              Tag('${m.memberCount} members'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _actions(StaffMember m) {
    showAppSheet<void>(
      context,
      title: m.name,
      builder: (ctx) => Column(
        children: [
          if (m.invited)
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Resent Invite'),
              onTap: () async {
                Navigator.pop(ctx);
                if (!mounted) return;
                if (await runOk(
                  context,
                  () => _repo.resendInvite(m.userId),
                  success: 'Invite sent successfully',
                )) {
                  _cubit.refresh();
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit Staff'),
            onTap: () async {
              Navigator.pop(ctx);
              if (!mounted) return;
              await context.push('/staff/${m.userId}/edit', extra: m);
              _cubit.refresh();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.danger),
            title: Text(
              'Delete Staff',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              if (!mounted) return;
              if (!await confirmDialog(
                    context,
                    title: 'Delete Staff',
                    message: 'They will lose access to this gym. This action cannot be undone.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  ) ||
                  !mounted) {
                return;
              }
              if (await runOk(
                context,
                () => _repo.delete(m.userId),
                success: 'Staff deleted',
              )) {
                _cubit.refresh();
              }
            },
          ),
        ],
      ),
    );
  }
}

class StaffFormScreen extends StatefulWidget {
  const StaffFormScreen({super.key, this.existing});
  final StaffMember? existing;
  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<StaffRepository>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(
    text: widget.existing?.phone?.replaceFirst('+91', ''),
  );
  late final _email = TextEditingController(text: widget.existing?.email);
  late String _role = widget.existing?.role ?? 'staff';
  String _dial = '+91';
  bool _saving = false;
  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repo.update(widget.existing!.userId, {
          'name': _name.text.trim(),
          'role': _role,
        });
      } else {
        await _repo.create(
          name: _name.text.trim(),
          phone: toE164(_phone.text, dial: _dial),
          role: _role,
          email: _email.text.trim().isEmpty
              ? null
              : _email.text.trim().toLowerCase(),
        );
      }
      if (!mounted) return;
      showToast(
        context,
        _isEdit ? 'Edited successfully' : 'Invite sent successfully',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormScaffold(
    title: _isEdit ? 'Edit Staff' : 'Add New Staff',
    formKey: _form,
    submitLabel: _isEdit ? 'Save' : 'Add Staff',
    saving: _saving,
    onSubmit: _save,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _name,
          label: 'Name (Required)',
          hint: 'Please enter Staff name',
          textCapitalization: TextCapitalization.words,
          validator: (v) => V.name(v, label: 'Staff name'),
        ),
        const Gap(16),
        if (_isEdit)
          AppTextField(
            initialValue: widget.existing!.phone,
            label: 'Number',
            enabled: false,
          )
        else
          PhoneInput(
            controller: _phone,
            dial: _dial,
            label: 'Number (Required)',
            onDialChanged: (d) => setState(() => _dial = d),
          ),
        if (!_isEdit) ...[
          const Gap(16),
          AppTextField(
            controller: _email,
            label: 'Email (optional)',
            hint: 'Enter email',
            keyboardType: TextInputType.emailAddress,
            validator: V.email,
          ),
        ],
        const Gap(20),
        const Text(
          'Please select role',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const Gap(8),
        for (final r in _roleHelp.keys)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: _role == r ? AppColors.chip : null,
            child: RadioListTile<String>(
              value: r,
              // ignore: deprecated_member_use
              groupValue: _role,
              // ignore: deprecated_member_use
              onChanged: (v) => setState(() => _role = v!),
              title: Text(
                roleLabel(r),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _roleHelp[r]!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        if (!_isEdit)
          const InfoBanner(
            'They will receive an invitation and can sign in with their phone number (OTP).',
          ),
      ],
    ),
  );
}
