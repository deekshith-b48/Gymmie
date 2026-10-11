import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/network/api_exception.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/util/json.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/members.dart';
import '../../data/models/messaging.dart';
import '../../data/repositories/members_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../members/member_picker.dart';
import '../members/members_screen.dart' show memberStatusOptions;

Tone _statusTone(String s) => switch (s) {
  'sent' => Tone.success,
  'scheduled' => Tone.info,
  _ => Tone.neutral,
};

class BroadcastsScreen extends StatefulWidget {
  const BroadcastsScreen({super.key});
  @override
  State<BroadcastsScreen> createState() => _BroadcastsScreenState();
}

class _BroadcastsScreenState extends State<BroadcastsScreen> {
  final _repo = getIt<MessagingRepository>();
  late final AsyncCubit<List<Broadcast>> _cubit = AsyncCubit(_repo.broadcasts);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final canWrite = s.can(Perm.broadcastsWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcasts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Message history',
            onPressed: () => context.push('/messages'),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Credits',
            onPressed: () => context.push('/credits'),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/broadcasts/new');
                _cubit.refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Create new broadcast'),
            )
          : null,
      body: AsyncBody<List<Broadcast>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: EmptyState(
          icon: Icons.campaign_outlined,
          title: 'Bulk / Broadcast messages',
          message: 'Create your first broadcast to start messaging your members via WhatsApp. Reach everyone instantly with updates and news.',
          actionLabel: canWrite ? 'Create new broadcast' : null,
          onAction: () async {
            await context.push('/broadcasts/new');
            _cubit.refresh();
          },
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final b = list[i];
            return AppCard(
              onTap: () async {
                await context.push('/broadcasts/${b.id}');
                _cubit.refresh();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          b.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Tag(
                        b.status[0].toUpperCase() + b.status.substring(1),
                        tone: _statusTone(b.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      Tag(
                        '${b.recipientCount} recipients',
                        icon: Icons.people_outline,
                      ),
                      if (b.status == 'scheduled' && b.scheduleAt != null)
                        Tag(
                          'Scheduled for ${Fmt.dateTime(b.scheduleAt)}',
                          tone: Tone.info,
                        )
                      else if (b.sentAt != null)
                        Tag(Fmt.dateTime(b.sentAt)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class BroadcastDetailScreen extends StatefulWidget {
  const BroadcastDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<BroadcastDetailScreen> createState() => _BroadcastDetailScreenState();
}

class _BroadcastDetailScreenState extends State<BroadcastDetailScreen> {
  final _repo = getIt<MessagingRepository>();
  late final AsyncCubit<Broadcast> _cubit = AsyncCubit(
    () => _repo.broadcast(widget.id),
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.broadcastsWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Broadcast'),
        actions: [
          BlocBuilder<AsyncCubit<Broadcast>, AsyncState<Broadcast>>(
            bloc: _cubit,
            builder: (context, st) {
              final b = st.data;
              if (b == null || b.status != 'scheduled' || !canWrite) {
                return const SizedBox.shrink();
              }
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Update Broadcast',
                    onPressed: () async {
                      await context.push('/broadcasts/${b.id}/edit', extra: b);
                      _cubit.refresh();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.cancel_outlined,
                      color: AppColors.danger,
                    ),
                    tooltip: 'Cancel broadcast',
                    onPressed: () async {
                      if (!await confirmDialog(
                            context,
                            title: 'Cancel broadcast',
                            message: 'Do you want to cancel this broadcast? Reserved credits are refunded.',
                            confirmLabel: 'Cancel broadcast',
                            cancelLabel: 'Keep',
                            destructive: true,
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      final r = await runWithProgress(
                        context,
                        () => _repo.cancelBroadcast(b.id),
                        success: 'Broadcast cancelled',
                      );
                      if (r != null) _cubit.refresh();
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: AsyncBody<Broadcast>(
        cubit: _cubit,
        builder: (context, b) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          b.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Tag(b.status, tone: _statusTone(b.status)),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(b.body, style: const TextStyle(height: 1.5)),
                  const Divider(height: 24),
                  InfoRow('Recipients', '${b.recipientCount}'),
                  InfoRow('Credits', '${b.creditsReserved}'),
                  if (b.delivered != null)
                    InfoRow('Delivered', '${b.delivered}'),
                  if (b.failed != null && b.failed! > 0)
                    InfoRow('Failed members', '${b.failed}'),
                  InfoRow('Created', Fmt.dateTime(b.createdAt)),
                  if (b.scheduleAt != null)
                    InfoRow('Scheduled for', Fmt.dateTime(b.scheduleAt)),
                  if (b.sentAt != null) InfoRow('Sent', Fmt.dateTime(b.sentAt)),
                ],
              ),
            ),
            const InfoBanner(
              'Messages are recorded in the development outbox; no real WhatsApp/SMS provider is connected.',
              icon: Icons.developer_mode,
              warning: true,
            ),
            const SectionTitle(
              'Recipients',
              padding: EdgeInsets.fromLTRB(2, 20, 2, 8),
            ),
            for (final r in b.recipients.take(100))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(name: r.name, radius: 16),
                title: Text(r.name),
                subtitle: Text(r.phone ?? ''),
              ),
          ],
        ),
      ),
    );
  }
}

/// Create / update a broadcast.
class BroadcastFormScreen extends StatefulWidget {
  const BroadcastFormScreen({super.key, this.existing});
  final Broadcast? existing;
  @override
  State<BroadcastFormScreen> createState() => _BroadcastFormScreenState();
}

class _BroadcastFormScreenState extends State<BroadcastFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<MessagingRepository>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _body = TextEditingController(text: widget.existing?.body);
  late String _status = (widget.existing?.filter['status'] as String?) ?? 'all';
  late final Set<String> _exclude = {...?widget.existing?.excludeMemberIds};
  final Map<String, String> _excludeNames = {};
  List<LabelRef> _labels = [];
  late final Set<String> _labelIds = {
    ...('${widget.existing?.filter['labelIds'] ?? ''}')
        .split(',')
        .where((e) => e.isNotEmpty),
  };
  List<BroadcastTemplate> _templates = [];
  List<String> _vars = const [];
  RecipientPreview? _preview;
  String? _previewText;
  DateTime? _schedule;
  bool _saving = false;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing?.scheduleAt != null) {
      _schedule = DateTime.tryParse(widget.existing!.scheduleAt!)?.toLocal();
    }
    getIt<MembersRepository>()
        .labels()
        .then((l) => mounted ? setState(() => _labels = l) : null)
        .catchError((Object _) {});
    _repo
        .broadcastTemplates()
        .then((t) => mounted ? setState(() => _templates = t) : null)
        .catchError((Object _) {});
    _repo
        .variables('broadcast')
        .then(
          (v) => mounted
              ? setState(() => _vars = [...v.common, ...v.member])
              : null,
        )
        .catchError((Object _) {});
    _refreshPreview();
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Json get _filter => {
    if (_status != 'all') 'status': _status,
    if (_labelIds.isNotEmpty) 'labelIds': _labelIds.join(','),
  };

  Future<void> _refreshPreview() async {
    try {
      final p = await _repo.previewRecipients(_filter, _exclude.toList());
      if (mounted) setState(() => _preview = p);
    } catch (_) {}
  }

  Future<void> _renderPreview() async {
    if (_body.text.trim().isEmpty) return;
    try {
      final t = await _repo.preview(_body.text);
      if (mounted) setState(() => _previewText = t);
    } catch (_) {}
  }

  void _insert(String v) {
    final sel = _body.selection;
    final t = _body.text;
    final i = sel.isValid ? sel.start : t.length;
    _body.text = '${t.substring(0, i)}{{$v}}${t.substring(i)}';
    _body.selection = TextSelection.collapsed(offset: i + v.length + 4);
    _renderPreview();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_preview != null && _preview!.count == 0) {
      return showToast(
        context,
        'Please select at least one recipient',
        error: true,
      );
    }
    if (_preview != null && _preview!.tooMany) {
      return showToast(
        context,
        'A broadcast can include at most 5,000 recipients. Narrow your filters or exclude fewer members.',
        error: true,
      );
    }
    if (_schedule != null &&
        _schedule!.isBefore(
          DateTime.now().subtract(const Duration(minutes: 1)),
        )) {
      return showToast(
        context,
        'Selected date and time cannot be in the past.',
        error: true,
      );
    }
    final ok = await confirmDialog(
      context,
      title: _isEdit ? 'Update Broadcast' : 'Create new broadcast',
      message: _isEdit
          ? 'Do you want to update this broadcast?'
          : 'Do you want to broadcast this to your members? ${_preview == null ? '' : '${_preview!.count} recipients · ${_preview!.creditsRequired} credits'}',
      confirmLabel: _schedule == null ? 'Send now' : 'Schedule',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'body': _body.text.trim(),
        'filter': _filter,
        'excludeMemberIds': _exclude.toList(),
        if (_schedule != null)
          'scheduleAt': _schedule!.toUtc().toIso8601String(),
      };
      if (_isEdit) {
        await _repo.updateBroadcast(widget.existing!.id, body);
      } else {
        await _repo.createBroadcast(body);
      }
      if (!mounted) return;
      showToast(
        context,
        _isEdit
            ? 'Broadcast updated successfully'
            : 'Broadcast created successfully',
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isInsufficientCredits) {
        final recharge = await confirmDialog(
          context,
          title: 'Not enough credits',
          message: "You don't have enough credits. Please recharge.",
          confirmLabel: 'Recharge now',
        );
        if (recharge && mounted) context.push('/credits');
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final low =
        _preview != null && _preview!.creditsRequired > _preview!.balance;
    return FormScaffold(
      title: _isEdit ? 'Update Broadcast' : 'New Broadcast',
      formKey: _form,
      submitLabel: _schedule == null
          ? (_isEdit ? 'Update Broadcast' : 'Send now')
          : 'Schedule for later',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _name,
            label: 'Broadcast Name',
            hint: 'Enter broadcast name',
            maxLength: 80,
            validator: (v) => V.required(v, 'Please enter a broadcast name'),
          ),
          const Gap(16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Message',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              if (_templates.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final t = await showPickerSheet<BroadcastTemplate>(
                      context,
                      title: 'Select Template',
                      items: _templates,
                      labelOf: (t) => t.title,
                      subtitleOf: (t) => t.body,
                    );
                    if (t != null) {
                      _body.text = t.body;
                      _renderPreview();
                    }
                  },
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Select Template'),
                ),
            ],
          ),
          AppTextField(
            controller: _body,
            hint: 'Click # to activate the variable picker. Select a variable to add to the text',
            maxLines: 5,
            maxLength: 1000,
            validator: (v) => V.required(v, 'Message cannot be empty'),
            onChanged: (_) => setState(() => _previewText = null),
          ),
          if (_vars.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in _vars)
                  ActionChip(
                    label: Text('#$v', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _insert(v),
                  ),
              ],
            ),
          TextButton.icon(
            onPressed: _renderPreview,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Message Preview'),
          ),
          if (_previewText != null)
            AppCard(
              color: const Color(0xFFDCF8C6),
              child: Text(
                _previewText!,
                style: const TextStyle(color: Colors.black87, height: 1.5),
              ),
            ),
          const Gap(16),
          const Text(
            'Recipients',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in [
                'all',
                'active',
                'expiring10',
                'expiring30',
                'expired',
                'withBalance',
                'birthdayToday',
              ])
                PillChip(
                  label: memberStatusOptions[k]!,
                  selected: _status == k,
                  onTap: () {
                    setState(() => _status = k);
                    _refreshPreview();
                  },
                ),
            ],
          ),
          if (_labels.isNotEmpty) ...[
            const Gap(12),
            const Text(
              'Member Labels',
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
                    onTap: () {
                      setState(
                        () => _labelIds.contains(l.id)
                            ? _labelIds.remove(l.id)
                            : _labelIds.add(l.id),
                      );
                      _refreshPreview();
                    },
                  ),
              ],
            ),
          ],
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _exclude.isEmpty
                      ? 'No members excluded'
                      : 'Excluded members: ${_exclude.map((i) => _excludeNames[i] ?? 'member').join(', ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final m = await pickMember(
                    context,
                    title: 'Excluded members',
                  );
                  if (m != null) {
                    setState(() {
                      _exclude.add(m.id);
                      _excludeNames[m.id] = m.name;
                    });
                    _refreshPreview();
                  }
                },
                child: const Text('Exclude'),
              ),
              if (_exclude.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(_exclude.clear);
                    _refreshPreview();
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (_preview != null)
            AppCard(
              color: low ? AppColors.dangerTint : AppColors.successTint,
              child: Row(
                children: [
                  Icon(
                    low
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: low ? AppColors.danger : AppColors.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_preview!.count} recipients · Credits required ${_preview!.creditsRequired} · Credits left ${_preview!.balance}${_preview!.optedOut > 0 ? '\n${_preview!.optedOut} member${_preview!.optedOut == 1 ? '' : 's'} turned promotions off in the app and ${_preview!.optedOut == 1 ? 'is' : 'are'} left out.' : ''}',
                      style: TextStyle(
                        color: low ? AppColors.danger : AppColors.success,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Gap(16),
          Text(
            'SENDING OPTION',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: PillChip(
                  label: 'Send Now',
                  selected: _schedule == null,
                  onTap: () => setState(() => _schedule = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillChip(
                  label: _schedule == null
                      ? 'Schedule for later'
                      : Fmt.dateTime(_schedule!.toUtc().toIso8601String()),
                  selected: _schedule != null,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(hours: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d == null || !context.mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        DateTime.now().add(const Duration(hours: 1)),
                      ),
                    );
                    if (t != null) {
                      setState(
                        () => _schedule = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t.hour,
                          t.minute,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
