import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/data/countries.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/images.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/finance.dart';
import '../../data/models/members.dart';
import '../../data/repositories/finance_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../auth/phone_input.dart';
import 'membership_section.dart';

const bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Add / edit member (routes /new-member and /edit-member).
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({super.key, this.memberId});
  final String? memberId;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _form = GlobalKey<FormState>();
  final _membership = GlobalKey<MembershipSectionState>();
  final _repo = getIt<MembersRepository>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _emName = TextEditingController();
  final _emPhone = TextEditingController();
  final _referral = TextEditingController();
  String _dial = '+91';
  String? _gender;
  String? _birth;
  String? _joined;
  String? _blood;
  String? _trainerId;
  Set<String> _labelIds = {};
  PickedImage? _photo;
  String? _existingPhoto;
  bool _addMembership = true;
  bool _saving = false;
  bool _loading = false;
  Object? _error;
  List<LabelRef> _labels = [];
  List<StaffMember> _trainers = [];
  late final bool _isEdit = widget.memberId != null;

  @override
  void initState() {
    super.initState();
    _loadRefs();
    if (_isEdit) _loadMember();
  }

  Future<void> _loadRefs() async {
    try {
      final r = await Future.wait([
        _repo.labels(),
        getIt<StaffRepository>().trainers().catchError(
          (Object _) => <StaffMember>[],
        ),
      ]);
      if (mounted) {
        setState(() {
          _labels = r[0] as List<LabelRef>;
          _trainers = r[1] as List<StaffMember>;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMember() async {
    setState(() => _loading = true);
    try {
      final d = await _repo.detail(widget.memberId!);
      final m = d.summary;
      if (!mounted) return;
      setState(() {
        _name.text = m.name;
        _phone.text = m.phone.replaceFirst(RegExp(r'^\+91'), '');
        _dial = m.phone.startsWith('+91')
            ? '+91'
            : (countries
                  .firstWhere(
                    (c) => m.phone.startsWith(c.dial),
                    orElse: () => countries.first,
                  )
                  .dial);
        if (_dial != '+91') _phone.text = m.phone.substring(_dial.length);
        _email.text = m.email ?? '';
        _address.text = d.address ?? '';
        _notes.text = d.notes ?? '';
        _gender = m.gender;
        _birth = m.birthDate;
        _joined = m.joinedAt;
        _blood = m.bloodGroup;
        _trainerId = m.trainerId;
        _labelIds = m.labels.map((l) => l.id).toSet();
        _existingPhoto = m.photoUrl;
        _emName.text = d.emergencyName ?? '';
        _emPhone.text = d.emergencyPhone?.replaceFirst('+91', '') ?? '';
        _height.text = d.health.heightCm?.toString() ?? '';
        _weight.text = d.health.weightKg?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _address,
      _notes,
      _height,
      _weight,
      _emName,
      _emPhone,
      _referral,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final includeMembership = !_isEdit && _addMembership;
    if (includeMembership && !(_membership.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        'phone': toE164(_phone.text, dial: _dial),
        'email': _email.text.trim().isEmpty
            ? null
            : _email.text.trim().toLowerCase(),
        'gender': _gender,
        'birthDate': _birth,
        'bloodGroup': _blood,
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'joinedAt': _joined,
        'labelIds': _labelIds.toList(),
        'trainerId': _trainerId,
        'heightCm': double.tryParse(_height.text.trim()),
        'weightKg': double.tryParse(_weight.text.trim()),
        if (_emName.text.trim().isNotEmpty || _emPhone.text.trim().isNotEmpty)
          'emergencyContact': compact({
            'name': _emName.text.trim().isEmpty ? null : _emName.text.trim(),
            'phone': _emPhone.text.trim().isEmpty
                ? null
                : toE164(_emPhone.text, dial: _dial),
          }),
        if (_photo != null) 'photo': _photo!.toJson(),
        if (!_isEdit && _referral.text.trim().isNotEmpty)
          'referralCode': _referral.text.trim(),
      };
      if (_isEdit) {
        // PATCH only carries values the user can clear explicitly.
        body['trainerId'] = _trainerId;
        final saved = await _repo.update(
          widget.memberId!,
          compact(body)..['trainerId'] = _trainerId,
        );
        if (!mounted) return;
        showToast(context, 'Edited successfully');
        context.pop(saved);
      } else {
        if (includeMembership) {
          body['membership'] = _membership.currentState!.buildBody();
        }
        final saved = await _repo.create(compact(body));
        if (!mounted) return;
        showToast(context, 'Added successfully');
        context.pushReplacement('/members/${saved.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Member')),
        body: const LoadingBox(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Member')),
        body: ErrorState(error: toApiException(_error!), onRetry: _loadMember),
      );
    }
    return FormScaffold(
      title: _isEdit ? 'Edit Member' : 'Add new member',
      formKey: _form,
      submitLabel: _isEdit ? 'Save' : 'Add new member',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: GestureDetector(
              onTap: () async {
                final p = await pickImage(context);
                if (p != null) setState(() => _photo = p);
              },
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: AppColors.chip,
                    backgroundImage: _photo != null
                        ? MemoryImage(Uint8List.fromList(_photo!.bytes))
                        : null,
                    child: _photo != null
                        ? null
                        : (_existingPhoto != null
                              ? ClipOval(
                                  child: UserAvatar(
                                    name: _name.text,
                                    url: _existingPhoto,
                                    radius: 46,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_outline,
                                  size: 40,
                                  color: AppColors.textMuted,
                                )),
                  ),
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
              'Add profile image',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const Gap(20),
          AppTextField(
            controller: _name,
            label: 'Name (Required)',
            hint: 'Enter name',
            textCapitalization: TextCapitalization.words,
            validator: (v) => V.name(v, label: 'Member name'),
          ),
          const Gap(16),
          PhoneInput(
            controller: _phone,
            dial: _dial,
            label: 'Number (Required)',
            onDialChanged: (d) => setState(() => _dial = d),
          ),
          const Gap(16),
          AppTextField(
            controller: _email,
            label: 'Email',
            hint: 'Enter email',
            keyboardType: TextInputType.emailAddress,
            validator: V.email,
          ),
          const Gap(16),
          const Text(
            'Gender',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Gap(8),
          Wrap(
            spacing: 10,
            children: [
              for (final g in ['male', 'female', 'other'])
                PillChip(
                  label: '${g[0].toUpperCase()}${g.substring(1)}',
                  selected: _gender == g,
                  onTap: () =>
                      setState(() => _gender = _gender == g ? null : g),
                ),
            ],
          ),
          const Gap(16),
          DateField(
            label: 'Date of birth',
            value: _birth,
            lastDate: DateTime.now(),
            clearable: true,
            onChanged: (v) => setState(() => _birth = v),
          ),
          const Gap(16),
          DateField(
            label: 'Joining date',
            value: _joined,
            lastDate: DateTime.now().add(const Duration(days: 1)),
            hint: 'Today',
            clearable: true,
            onChanged: (v) => setState(() => _joined = v),
          ),
          const Gap(16),
          DropdownField<String>(
            label: 'Blood Group',
            value: _blood,
            items: bloodGroups,
            onChanged: (v) => setState(() => _blood = v),
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _height,
                  label: 'Height (cm)',
                  hint: 'Enter your height',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d?)?'),
                    ),
                  ],
                  validator: (v) => (v == null || v.isEmpty)
                      ? null
                      : ((double.tryParse(v) ?? 0) < 50 ||
                                (double.tryParse(v) ?? 0) > 260
                            ? 'Please enter a valid height.'
                            : null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _weight,
                  label: 'Weight (kg)',
                  hint: 'Enter your weight',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d?)?'),
                    ),
                  ],
                  validator: (v) => (v == null || v.isEmpty)
                      ? null
                      : ((double.tryParse(v) ?? 0) < 10 ||
                                (double.tryParse(v) ?? 0) > 500
                            ? 'Please enter a valid weight.'
                            : null),
                ),
              ),
            ],
          ),
          const Gap(16),
          AppTextField(
            controller: _address,
            label: 'Address',
            hint: 'Enter address',
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_labels.isNotEmpty) ...[
            const Gap(16),
            const Text(
              'Member Labels',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Gap(8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final l in _labels)
                  PillChip(
                    label: l.name,
                    selected: _labelIds.contains(l.id),
                    onTap: () => setState(
                      () => _labelIds.contains(l.id)
                          ? _labelIds.remove(l.id)
                          : _labelIds.add(l.id),
                    ),
                  ),
              ],
            ),
          ],
          if (_trainers.isNotEmpty && s.can(Perm.membersWrite)) ...[
            const Gap(16),
            DropdownField<String?>(
              label: 'Assign Trainer',
              value: _trainerId,
              items: [null, ..._trainers.map((t) => t.userId)],
              hint: 'No trainer',
              labelOf: (id) => id == null
                  ? 'No trainer'
                  : _trainers.firstWhere((t) => t.userId == id).name,
              onChanged: (v) => setState(() => _trainerId = v),
            ),
          ],
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _emName,
                  label: 'Emergency contact',
                  hint: 'Name',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  controller: _emPhone,
                  label: ' ',
                  hint: 'Phone',
                  keyboardType: TextInputType.phone,
                  validator: (v) => V.phone(v, dial: _dial, optional: true),
                ),
              ),
            ],
          ),
          if (!_isEdit) ...[
            const Gap(16),
            AppTextField(
              controller: _referral,
              label: 'Referral code (optional)',
              hint: 'Referral code',
            ),
          ],
          const Gap(16),
          AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Add some quick notes here',
            maxLines: 3,
            maxLength: 500,
          ),
          if (!_isEdit) ...[
            const Gap(8),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Add their membership',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Skip to add the member now and assign a plan later.',
                style: TextStyle(fontSize: 12),
              ),
              value: _addMembership,
              onChanged: (v) => setState(() => _addMembership = v),
            ),
            if (_addMembership) MembershipSection(key: _membership),
          ],
        ],
      ),
    );
  }
}
