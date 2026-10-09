import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/members_repository.dart';
import 'membership_section.dart';

/// Renew / add upcoming / upgrade a membership (routes /renew, /upgrade). Plays the recovered
/// `success.mp3` after a renewal when the "Renewal Sound" preference is on.
class RenewScreen extends StatefulWidget {
  const RenewScreen({
    super.key,
    required this.memberId,
    this.kind = 'renewal',
    this.upgradeFromId,
  });
  final String memberId;
  final String kind;
  final String? upgradeFromId;

  @override
  State<RenewScreen> createState() => _RenewScreenState();
}

class _RenewScreenState extends State<RenewScreen> {
  final _form = GlobalKey<FormState>();
  final _section = GlobalKey<MembershipSectionState>();
  bool _saving = false;
  final _repo = getIt<MembershipsRepository>();

  bool get _upgrade => widget.upgradeFromId != null;

  Future<void> _submit() async {
    if (!_section.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = _section.currentState!.buildBody();
      if (_upgrade) {
        await _repo.upgrade(
          widget.upgradeFromId!,
          body
            ..remove('kind')
            ..remove('startDate'),
        );
      } else {
        await _repo.create({
          ...body,
          'memberId': widget.memberId,
          'kind': widget.kind,
        });
      }
      final s = getIt<SessionCubit>().state;
      if (s.profile?.renewalSound == true && s.feature(Feat.renewalSound)) {
        try {
          await AudioPlayer().play(AssetSource('sound/success.mp3'));
        } catch (_) {}
      }
      if (!mounted) return;
      showToast(
        context,
        _upgrade
            ? 'Membership upgraded'
            : (widget.kind == 'upcoming'
                  ? 'Upcoming membership added'
                  : 'You have added the membership.'),
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
    title: _upgrade
        ? 'Upgrade Membership'
        : (widget.kind == 'upcoming' ? 'Add Upcoming' : 'Renew Membership'),
    formKey: _form,
    submitLabel: _upgrade ? 'Confirm Upgrade' : 'Confirm Renewal',
    saving: _saving,
    onSubmit: _submit,
    child: MembershipSection(
      key: _section,
      memberId: widget.memberId,
      kind: widget.kind,
    ),
  );
}
