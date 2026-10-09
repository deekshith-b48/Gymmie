import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/plans.dart';
import '../../data/repositories/members_repository.dart';

class _PlansData {
  const _PlansData(this.plans, this.groups);
  final List<Plan> plans;
  final List<PlanGroup> groups;
}

/// Manage Plans (route /plans): list with group filter, enable/disable, duplicate, delete.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _repo = getIt<PlansRepository>();
  bool _showDisabled = false;
  String? _groupId;
  late AsyncCubit<_PlansData> _cubit = _make();

  AsyncCubit<_PlansData> _make() => AsyncCubit(() async {
    final r = await Future.wait([
      _repo.plans(includeDisabled: _showDisabled),
      _repo.groups(),
    ]);
    return _PlansData(r[0] as List<Plan>, r[1] as List<PlanGroup>);
  });

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    if (await runOk(context, f, success: ok)) _cubit.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.plansWrite);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Plans'),
        actions: [
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.folder_open_outlined),
              tooltip: 'Manage Plan Groups',
              onPressed: () async {
                await context.push('/plans/groups');
                _cubit.refresh();
              },
            ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/plans/new');
                _cubit.refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add New Plan'),
            )
          : null,
      body: AsyncBody<_PlansData>(
        cubit: _cubit,
        builder: (context, d) {
          final list = d.plans
              .where((p) => _groupId == null || p.groupId == _groupId)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              if (d.groups.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      PillChip(
                        label: 'All Plan Groups',
                        selected: _groupId == null,
                        onTap: () => setState(() => _groupId = null),
                      ),
                      for (final g in d.groups)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: PillChip(
                            label: '${g.name} (${g.planCount})',
                            selected: _groupId == g.id,
                            onTap: () => setState(() => _groupId = g.id),
                          ),
                        ),
                    ],
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Show Disabled Plans',
                  style: TextStyle(fontSize: 14),
                ),
                value: _showDisabled,
                onChanged: (v) {
                  setState(() {
                    _showDisabled = v;
                    _cubit.close();
                    _cubit = _make();
                  });
                },
              ),
              if (list.isEmpty)
                const SizedBox(
                  height: 320,
                  child: EmptyState(
                    icon: Icons.event_repeat,
                    title: 'No plans yet',
                    message: 'Tap the quick button to create your first plan. Plans hold your price and duration. Members get assigned to them.',
                  ),
                )
              else
                for (final p in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      onTap: canWrite
                          ? () async {
                              await context.push('/plans/${p.id}/edit');
                              _cubit.refresh();
                            }
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (!p.active)
                                const Tag('Disabled', tone: Tone.danger),
                              if (canWrite)
                                PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'edit') {
                                      await context.push('/plans/${p.id}/edit');
                                      _cubit.refresh();
                                    } else if (v == 'dup') {
                                      if (await confirmDialog(
                                        context,
                                        title: 'Duplicate Plan',
                                        message:
                                            'Create a copy of "${p.name}"?',
                                        confirmLabel: 'Duplicate',
                                      )) {
                                        await _run(
                                          () => _repo
                                              .duplicate(p.id)
                                              .then((_) {}),
                                          'Plan created successfully',
                                        );
                                      }
                                    } else if (v == 'toggle') {
                                      if (await confirmDialog(
                                        context,
                                        title: p.active
                                            ? 'Disable plan'
                                            : 'Enable plan',
                                        message: p.active
                                            ? 'Members on this plan are not affected, but it can no longer be sold.'
                                            : 'This plan can be sold again.',
                                        confirmLabel: p.active
                                            ? 'Disable'
                                            : 'Enable',
                                      )) {
                                        await _run(
                                          () => _repo
                                              .setActive(p.id, !p.active)
                                              .then((_) {}),
                                          p.active
                                              ? 'Plan disabled'
                                              : 'Plan enabled',
                                        );
                                      }
                                    } else if (v == 'del') {
                                      if (await confirmDialog(
                                        context,
                                        title: 'Delete Plan',
                                        message: 'Do you want to delete this plan? Existing memberships keep their history. This action cannot be undone.',
                                        confirmLabel: 'Delete',
                                        destructive: true,
                                      )) {
                                        await _run(
                                          () => _repo.delete(p.id),
                                          'Deleted',
                                        );
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'dup',
                                      child: Text('Duplicate plan'),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(
                                        p.active
                                            ? 'Disable plan'
                                            : 'Enable plan',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'del',
                                      child: Text(
                                        'Delete plan',
                                        style: TextStyle(
                                          color: AppColors.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          Text(
                            Fmt.money(p.price),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Tag(p.durationLabel, icon: Icons.schedule),
                              if (p.hasSessions)
                                Tag(
                                  '${p.sessionCount} sessions',
                                  tone: Tone.info,
                                  icon: Icons.fitness_center,
                                ),
                              if (p.groupName != null)
                                Tag(p.groupName!, icon: Icons.folder_outlined),
                              Tag(
                                '${p.activeMembers} active',
                                tone: p.activeMembers > 0
                                    ? Tone.success
                                    : Tone.neutral,
                              ),
                            ],
                          ),
                          if (p.description != null &&
                              p.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                p.description!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Add / edit plan (routes /new-plan, /edit-plan).
class PlanFormScreen extends StatefulWidget {
  const PlanFormScreen({super.key, this.planId});
  final String? planId;
  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = getIt<PlansRepository>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _days = TextEditingController();
  final _desc = TextEditingController();
  final _sessions = TextEditingController(text: '10');
  bool _sessionPlan = false;
  String? _groupId;
  List<PlanGroup> _groups = [];
  bool _saving = false;
  bool _loading = false;
  late final bool _isEdit = widget.planId != null;

  @override
  void initState() {
    super.initState();
    _repo
        .groups()
        .then((g) => mounted ? setState(() => _groups = g) : null)
        .catchError((Object _) {});
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = (await _repo.plans(includeDisabled: true))
          .firstWhere((x) => x.id == widget.planId);
      if (!mounted) return;
      setState(() {
        _name.text = p.name;
        _price.text = p.price == p.price.roundToDouble()
            ? p.price.toInt().toString()
            : '${p.price}';
        _days.text = '${p.durationDays}';
        _desc.text = p.description ?? '';
        _groupId = p.groupId;
        _sessionPlan = p.hasSessions;
        if (p.hasSessions) _sessions.text = '${p.sessionCount}';
      });
    } catch (_) {
      if (mounted) showToast(context, 'Plan not found', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _days, _desc, _sessions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addGroup() async {
    final n = await promptText(
      context,
      title: 'Add New Group',
      label: 'Enter Group Name',
      hint: 'Enter group name',
      required: true,
      maxLength: 40,
    );
    if (n == null || !mounted) return;
    try {
      final g = await _repo.createGroup(n);
      setState(() {
        _groups = [..._groups, g];
        _groupId = g.id;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'price': double.parse(_price.text.trim()),
        'durationDays': int.parse(_days.text.trim()),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'groupId': _groupId,
        'sessions': _sessionPlan
            ? {'enabled': true, 'count': int.parse(_sessions.text.trim())}
            : null,
      };
      if (_isEdit) {
        await _repo.update(widget.planId!, body);
      } else {
        await _repo.create(
          body..removeWhere((k, v) => v == null && k != 'sessions'),
        );
      }
      if (!mounted) return;
      showToast(
        context,
        _isEdit ? 'Edited successfully' : 'Plan created successfully',
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
        appBar: AppBar(title: const Text('Edit Plan')),
        body: const LoadingBox(),
      );
    }
    return FormScaffold(
      title: _isEdit ? 'Edit Plan' : 'Add New Plan',
      formKey: _form,
      submitLabel: _isEdit ? 'Save' : 'Create Plan',
      saving: _saving,
      onSubmit: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _name,
            label: 'Plan Name',
            hint: 'Enter the plan name. e.g. 1 Month',
            validator: (v) => V.required(v, 'Please enter a plan name'),
            maxLength: 60,
          ),
          const Gap(16),
          AmountField(
            controller: _price,
            label: 'Plan Price',
            hint: 'Enter the plan amount. e.g. 1000',
            validator: (v) => V.amount(v, allowZero: true),
            symbol: getIt<SessionCubit>().state.profile?.currencySymbol,
          ),
          const Gap(16),
          AppTextField(
            controller: _days,
            label: 'Duration(in days)',
            hint: 'Enter the duration in days. e.g. 30',
            keyboardType: TextInputType.number,
            validator: (v) => V.integer(
              v,
              min: 1,
              max: 3650,
              label: 'plan duration (1-3650 days)',
            ),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            children: [
              for (final (l, d) in [
                ('1 month', 30),
                ('3 months', 90),
                ('6 months', 180),
                ('1 year', 365),
              ])
                ActionChip(
                  label: Text(l),
                  onPressed: () => setState(() => _days.text = '$d'),
                ),
            ],
          ),
          const Gap(16),
          AppTextField(
            controller: _desc,
            label: 'Description (optional)',
            hint: 'Enter a short description',
            maxLines: 2,
            maxLength: 300,
          ),
          const Gap(16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: DropdownField<String?>(
                  label: 'Plan Group',
                  value: _groupId,
                  items: [null, ..._groups.map((g) => g.id)],
                  hint: 'No group',
                  labelOf: (id) => id == null
                      ? 'No group'
                      : _groups.firstWhere((g) => g.id == id).name,
                  onChanged: (v) => setState(() => _groupId = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addGroup,
                icon: const Icon(Icons.add),
                tooltip: 'Add New Group',
              ),
            ],
          ),
          const Gap(8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Enable Sessions',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Track a fixed number of sessions (e.g. personal training). Members mark sessions as they attend.',
              style: TextStyle(fontSize: 12),
            ),
            value: _sessionPlan,
            onChanged: (v) => setState(() => _sessionPlan = v),
          ),
          if (_sessionPlan)
            AppTextField(
              controller: _sessions,
              label: 'Enter Number of Sessions',
              hint: 'Enter number of sessions',
              keyboardType: TextInputType.number,
              validator: (v) => V.integer(
                v,
                min: 1,
                max: 1000,
                label: 'a number of sessions (1-1000)',
              ),
            ),
        ],
      ),
    );
  }
}

/// Manage Plan Groups (route /plan-groups).
class PlanGroupsScreen extends StatefulWidget {
  const PlanGroupsScreen({super.key});
  @override
  State<PlanGroupsScreen> createState() => _PlanGroupsScreenState();
}

class _PlanGroupsScreenState extends State<PlanGroupsScreen> {
  final _repo = getIt<PlansRepository>();
  late final AsyncCubit<List<PlanGroup>> _cubit = AsyncCubit(_repo.groups);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _add() async {
    final n = await promptText(
      context,
      title: 'Add New Group',
      label: 'Enter Group Name',
      hint: 'Enter group name',
      required: true,
      maxLength: 40,
    );
    if (n != null &&
        mounted &&
        await runOk(
          context,
          () => _repo.createGroup(n).then((_) {}),
          success: 'Added successfully',
        )) {
      _cubit.refresh();
    }
  }

  Future<void> _delete(PlanGroup g, List<PlanGroup> all) async {
    String? moveTo;
    if (g.planCount > 0) {
      final others = all.where((x) => x.id != g.id).toList();
      if (others.isEmpty) {
        showToast(
          context,
          'Create another plan group first, then move the existing plans to it.',
          error: true,
        );
        return;
      }
      final target = await showPickerSheet<PlanGroup>(
        context,
        title: 'Move existing plans to',
        items: others,
        labelOf: (x) => x.name,
        subtitleOf: (x) => 'Please select the plan group where you would like to move the exiting plans to.',
      );
      if (target == null || !mounted) return;
      moveTo = target.id;
    }
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Delete group',
      message:
          'Do you want to delete "${g.name}"? This action cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok &&
        mounted &&
        await runOk(
          context,
          () => _repo.deleteGroup(g.id, moveTo: moveTo),
          success: 'Plans moved successfully',
        )) {
      _cubit.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage Plan Groups')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add),
      label: const Text('Add New Group'),
    ),
    body: AsyncBody<List<PlanGroup>>(
      cubit: _cubit,
      isEmpty: (l) => l.isEmpty,
      empty: const EmptyState(
        icon: Icons.folder_open_outlined,
        title: 'No plan groups',
        message: 'Groups help you organise plans, e.g. "Gym Access" and "Personal Training".',
      ),
      builder: (context, list) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final g = list[i];
          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${g.planCount} plan${g.planCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final n = await promptText(
                      context,
                      title: 'Edit Label',
                      label: 'Enter Group Name',
                      initial: g.name,
                      required: true,
                      maxLength: 40,
                    );
                    if (n != null &&
                        context.mounted &&
                        await runOk(
                          context,
                          () => _repo.renameGroup(g.id, n),
                          success: 'Edited successfully',
                        )) {
                      _cubit.refresh();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                  onPressed: () => _delete(g, list),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
