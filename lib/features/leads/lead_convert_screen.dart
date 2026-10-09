import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/states.dart';
import '../../data/models/leads.dart';
import '../../data/repositories/leads_repository.dart';
import '../members/membership_section.dart';

/// "Convert to Member": creates the member from the lead, optionally with the first membership.
class LeadConvertScreen extends StatefulWidget {
  const LeadConvertScreen({super.key, required this.leadId});
  final String leadId;
  @override
  State<LeadConvertScreen> createState() => _LeadConvertScreenState();
}

class _LeadConvertScreenState extends State<LeadConvertScreen> {
  final _form = GlobalKey<FormState>();
  final _section = GlobalKey<MembershipSectionState>();
  final _repo = getIt<LeadsRepository>();
  late final AsyncCubit<Lead> _lead = AsyncCubit(
    () => _repo.get(widget.leadId),
  );
  bool _withPlan = true;
  bool _saving = false;

  @override
  void dispose() {
    _lead.close();
    super.dispose();
  }

  Future<void> _convert() async {
    if (_withPlan && !(_section.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final id = await _repo.convert(
        widget.leadId,
        membership: _withPlan ? _section.currentState!.buildBody() : null,
      );
      if (!mounted) return;
      showToast(context, 'Lead converted to member');
      context.pushReplacement('/members/$id');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncBody<Lead>(
    cubit: _lead,
    refreshable: false,
    builder: (context, l) => FormScaffold(
      title: 'Convert to Member',
      formKey: _form,
      submitLabel: 'Convert to Member',
      saving: _saving,
      onSubmit: _convert,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Row(
              children: [
                UserAvatar(name: l.name, url: l.photoUrl, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        l.phone,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        'Enquired ${Fmt.date(l.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Add their membership',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Turn off to convert now and assign a plan later.',
              style: TextStyle(fontSize: 12),
            ),
            value: _withPlan,
            onChanged: (v) => setState(() => _withPlan = v),
          ),
          if (_withPlan)
            MembershipSection(key: _section, initialPlanId: l.interestedPlanId),
        ],
      ),
    ),
  );
}
