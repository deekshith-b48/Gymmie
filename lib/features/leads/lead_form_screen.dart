import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/data/countries.dart';
import '../../core/state/async_cubit.dart';
import '../../core/util/images.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/leads.dart';
import '../../data/models/members.dart';
import '../../data/models/plans.dart';
import '../../data/repositories/leads_repository.dart';
import '../../data/repositories/members_repository.dart';
import '../auth/phone_input.dart';

/// Add / edit a lead (routes /new-lead-member, /edit-lead-member).
class LeadFormScreen extends StatefulWidget {
  const LeadFormScreen({super.key, this.leadId});
  final String? leadId;
  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<LeadsRepository>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  String _dial = '+91';
  String _source = 'Walk-in';
  String _chance = 'Medium';
  String? _follow;
  String? _planId;
  String? _gender;
  Set<String> _labelIds = {};
  List<Plan> _plans = [];
  List<LabelRef> _labels = [];
  PickedImage? _photo;
  bool _saving = false;
  bool _loading = false;
  Object? _error;
  late final bool _isEdit = widget.leadId != null;

  @override
  void initState() {
    super.initState();
    getIt<PlansRepository>()
        .plans()
        .then((p) => mounted ? setState(() => _plans = p) : null)
        .catchError((Object _) {});
    getIt<MembersRepository>()
        .labels(scope: 'member')
        .then((l) => mounted ? setState(() => _labels = l) : null)
        .catchError((Object _) {});
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await _repo.get(widget.leadId!);
      if (!mounted) return;
      setState(() {
        _name.text = l.name;
        _phone.text = l.phone.replaceFirst('+91', '');
        _email.text = l.email ?? '';
        _notes.text = l.notes ?? '';
        _source = l.source;
        _chance = l.chanceOfJoining;
        _follow = l.followUpDate;
        _gender = l.gender;
        _planId = l.interestedPlanId;
        _labelIds = l.labels.map((x) => x.id).toSet();
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
    for (final c in [_name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = compact({
        'name': _name.text.trim(),
        'phone': toE164(_phone.text, dial: _dial),
        'email': _email.text.trim().isEmpty
            ? null
            : _email.text.trim().toLowerCase(),
        'gender': _gender,
        'source': _source,
        'chanceOfJoining': _chance,
        'followUpDate': _follow,
        'interestedPlanId': _planId,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'labelIds': _labelIds.toList(),
        if (_photo != null) 'photo': _photo!.toJson(),
      });
      if (_isEdit) {
        await _repo.update(widget.leadId!, body);
      } else {
        await _repo.create(body);
      }
      if (!mounted) return;
      showToast(
        context,
        _isEdit ? 'Edited successfully' : 'Added successfully',
      );
      context.pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Lead Member')),
        body: const LoadingBox(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: toApiException(_error!), onRetry: _load),
      );
    }
    return FormScaffold(
      title: _isEdit ? 'Edit Lead Member' : 'Add Lead Member',
      formKey: _form,
      submitLabel: _isEdit ? 'Save' : 'Add Lead Member',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            'Referral',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in leadSources)
                PillChip(
                  label: s,
                  selected: _source == s,
                  onTap: () => setState(() => _source = s),
                ),
            ],
          ),
          const Gap(16),
          const Text(
            'Chance of Joining',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in leadChances)
                PillChip(
                  label: c,
                  selected: _chance == c,
                  onTap: () => setState(() => _chance = c),
                ),
            ],
          ),
          const Gap(16),
          DateField(
            label: 'Follow Up Date',
            value: _follow,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            clearable: true,
            onChanged: (v) => setState(() => _follow = v),
          ),
          const Gap(16),
          if (_plans.isNotEmpty)
            DropdownField<String?>(
              label: 'Interested plan',
              value: _planId,
              items: [null, ..._plans.map((p) => p.id)],
              hint: 'Not decided',
              labelOf: (id) => id == null
                  ? 'Not decided'
                  : _plans.firstWhere((p) => p.id == id).name,
              onChanged: (v) => setState(() => _planId = v),
            ),
          if (_labels.isNotEmpty) ...[
            const Gap(16),
            const Text(
              'Labels',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
          const Gap(16),
          AppTextField(
            controller: _notes,
            label: 'Notes (optional)',
            hint: 'Add some quick notes here',
            maxLines: 3,
            maxLength: 500,
          ),
        ],
      ),
    );
  }
}
