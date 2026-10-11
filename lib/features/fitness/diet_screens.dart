import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/network/api_exception.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/fitness.dart';
import '../../data/models/user_gym.dart';
import '../../data/repositories/fitness_repository.dart';
import '../members/member_picker.dart';

class DietPlansScreen extends StatefulWidget {
  const DietPlansScreen({super.key});
  @override
  State<DietPlansScreen> createState() => _DietPlansScreenState();
}

class _DietPlansScreenState extends State<DietPlansScreen> {
  final _repo = getIt<FitnessRepository>();
  late final AsyncCubit<List<DietPlan>> _cubit = AsyncCubit(
    _repo.dietTemplates,
  );

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final canWrite = s.can(Perm.plansetsWrite);
    return Scaffold(
      appBar: AppBar(title: const Text('Diet Plans')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => showAppSheet<void>(
                context,
                title: 'New diet plan',
                builder: (ctx) => Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: const Text('Create from scratch'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await context.push('/diet-plans/new');
                        _cubit.refresh();
                      },
                    ),
                    if (s.feature(Feat.aiWorkouts))
                      ListTile(
                        leading: const Icon(Icons.auto_awesome),
                        title: const Text('Generate Diet Plan'),
                        subtitle: const Text(
                          'Meal guidance tailored to goal, preference and calories (rule-based)',
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await context.push('/diet-plans/generate');
                          _cubit.refresh();
                        },
                      ),
                  ],
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New Diet Plan'),
            )
          : null,
      body: AsyncBody<List<DietPlan>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          icon: Icons.restaurant_menu,
          title: 'No diet plans yet',
          message: 'Create reusable diet templates and assign them to members.',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final p = list[i];
            return AppCard(
              onTap: () async {
                await context.push('/diet-plans/${p.id}');
                _cubit.refresh();
              },
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.successTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.restaurant_menu,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (p.calorieTarget != null)
                              Tag('${p.calorieTarget} kcal'),
                            Tag('${p.meals.length} meals'),
                            if (p.dietaryPreference != null)
                              Tag(p.dietaryPreference!, tone: Tone.info),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class DietEditorScreen extends StatefulWidget {
  const DietEditorScreen({super.key, this.planId, this.memberId, this.draft});
  final String? planId;
  final String? memberId;
  final DietPlan? draft;
  @override
  State<DietEditorScreen> createState() => _DietEditorScreenState();
}

class _DietEditorScreenState extends State<DietEditorScreen> {
  final _repo = getIt<FitnessRepository>();
  DietPlan? _plan;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _notes = TextEditingController();

  bool get _memberMode => widget.memberId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      DietPlan? p = widget.draft;
      if (p == null && widget.planId != null) {
        p = await _repo.dietPlan(widget.planId!);
      }
      if (p == null && _memberMode) {
        p = await _repo.memberDiet(widget.memberId!);
      }
      if (p == null && widget.planId == null && !_memberMode) {
        p = DietPlan(
          name: '',
          meals: [DietMeal(name: 'Breakfast', time: '08:00')],
        );
      }
      _setPlan(p);
      _dirty = widget.draft != null;
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPlan(DietPlan? p) {
    _plan = p;
    _name.text = p?.name ?? '';
    _kcal.text = p?.calorieTarget?.toString() ?? '';
    _notes.text = p?.notes ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  Future<void> _save() async {
    final p = _plan!;
    p.name = _name.text.trim();
    p.calorieTarget = int.tryParse(_kcal.text.trim());
    p.notes = _notes.text.trim();
    if (p.name.isEmpty) {
      return showToast(context, 'Please enter a name', error: true);
    }
    if (p.meals.isEmpty) {
      return showToast(context, 'Please add at least one meal', error: true);
    }
    if (p.meals.any((m) => m.items.isEmpty)) {
      return showToast(
        context,
        'Every meal needs at least one food item',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      if (_memberMode) {
        await _repo.saveMemberDiet(widget.memberId!, p);
      } else if (p.id != null) {
        await _repo.updateDiet(p.id!, p);
      } else {
        await _repo.createDiet(p);
      }
      if (!mounted) return;
      setState(() => _dirty = false);
      showToast(
        context,
        p.id == null && !_memberMode
            ? 'Diet plan created successfully'
            : 'Diet plan updated successfully',
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editItem(DietMeal meal, [DietItem? item]) async {
    final name = TextEditingController(text: item?.name);
    final qty = TextEditingController(
      text: item == null ? '1' : '${item.quantity}',
    );
    final unit = TextEditingController(text: item?.unit);
    final kcal = TextEditingController(text: item?.kcal?.round().toString());
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: item == null ? 'Add Food' : 'Edit Food',
      builder: (ctx) => Form(
        key: key,
        child: Column(
          children: [
            AppTextField(
              controller: name,
              label: 'Food',
              hint: 'Eg: 1 cup of rice, 2 eggs, 1 apple, etc.',
              validator: (v) => V.required(v, 'Please enter a name'),
              maxLength: 100,
            ),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: qty,
                    label: 'Quantity',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        (double.tryParse((v ?? '').trim()) ?? 0) <= 0
                        ? 'Enter quantity'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: unit,
                    label: 'Unit',
                    hint: 'cup, piece…',
                    maxLength: 30,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: kcal,
                    label: 'kcal',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const Gap(12),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        final it = item ?? DietItem(name: '');
        it.name = name.text.trim();
        it.quantity = double.parse(qty.text.trim());
        it.unit = unit.text.trim().isEmpty ? null : unit.text.trim();
        it.kcal = double.tryParse(kcal.text.trim());
        if (item == null) meal.items.add(it);
      });
      _touch();
    }
    for (final c in [name, qty, unit, kcal]) {
      c.dispose();
    }
  }

  Future<void> _assign() async {
    final p = _plan!;
    if (p.id == null) {
      return showToast(context, 'Save the plan first', error: true);
    }
    final m = await pickMember(
      context,
      title: 'Assign Member',
      status: 'active',
    );
    if (m == null || !mounted) return;
    final r = await runWithProgress(
      context,
      () => _repo.assignDiet(p.id!, m.id),
      success: 'Diet plan assigned successfully',
    );
    if (r != null && mounted) showToast(context, 'Assigned to ${m.name}');
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final title = _memberMode
        ? 'Diet Plan'
        : (_plan?.id == null ? 'New Diet Plan' : 'Edit Diet Plan');
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const LoadingBox(),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ErrorState(error: toApiException(_error!), onRetry: _load),
      );
    }
    if (_plan == null) {
      return _DietEmpty(
        memberId: widget.memberId!,
        onChosen: (p) => setState(() => _setPlan(p)),
        onCreate: () => setState(() {
          _setPlan(
            DietPlan(
              name: '',
              meals: [DietMeal(name: 'Breakfast', time: '08:00')],
              ownerType: 'member',
              memberId: widget.memberId,
            ),
          );
          _dirty = true;
        }),
      );
    }
    final p = _plan!;
    final total = p.meals.fold<double>(0, (a, m) => a + m.kcal);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final save = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes?'),
            content: const Text(
              'Your changes to this diet plan have not been saved. Would you like to save before leaving?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (save == true) {
          await _save();
        } else if (save == false) {
          setState(() => _dirty = false);
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (p.meals.any((m) => m.items.isNotEmpty))
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Diet Plan Share',
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: p.toShareText(s.profile?.name ?? ''),
                    subject: p.name,
                  ),
                ),
              ),
            if (!_memberMode && p.id != null && s.can(Perm.plansetsWrite))
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                tooltip: 'Assign Member',
                onPressed: _assign,
              ),
            if (p.id != null && s.can(Perm.plansetsWrite))
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmDialog(
                        context,
                        title: _memberMode ? 'Remove plan' : 'Delete Diet Plan',
                        message: _memberMode
                            ? 'Remove this plan from the member?'
                            : 'Do you want to delete this diet plan? This action cannot be undone.',
                        confirmLabel: 'Delete',
                        destructive: true,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  final ok = await runOk(
                    context,
                    () => _memberMode
                        ? _repo.removeMemberDiet(widget.memberId!)
                        : _repo.deleteDiet(p.id!),
                    success: 'Diet plan deleted successfully',
                  );
                  if (ok && context.mounted) {
                    setState(() => _dirty = false);
                    context.pop(true);
                  }
                },
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final w in p.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InfoBanner(
                        w,
                        icon: Icons.health_and_safety_outlined,
                        warning: true,
                      ),
                    ),
                  if (p.generator != null && p.id == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: InfoBanner(
                        'Draft from the rule-based generator. Review and edit before saving.',
                        icon: Icons.auto_awesome,
                      ),
                    ),
                  AppTextField(
                    controller: _name,
                    label: 'Diet Plan Name',
                    hint: 'Eg: Keto Diet Plan',
                    maxLength: 80,
                    onChanged: (_) => _touch(),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _kcal,
                          label: 'Daily calorie target',
                          hint: 'kcal',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => _touch(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Plan total',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${total.round()} kcal',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (p.protein != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          Tag(
                            'Protein ${p.protein!.round()} g',
                            tone: Tone.info,
                          ),
                          Tag('Carbs ${p.carbs?.round() ?? 0} g'),
                          Tag('Fat ${p.fat?.round() ?? 0} g'),
                        ],
                      ),
                    ),
                  for (final (mi, meal) in p.meals.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final n = await promptText(
                                        context,
                                        title: 'Meal Name',
                                        label: 'Meal Name',
                                        hint: 'Eg: Breakfast, Lunch, Dinner, etc.',
                                        initial: meal.name,
                                        required: true,
                                        maxLength: 60,
                                      );
                                      if (n != null) {
                                        setState(() => meal.name = n);
                                        _touch();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              meal.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          if (meal.time != null)
                                            Text(
                                              '  ${meal.time}',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: AppColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${meal.kcal.round()} kcal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() => p.meals.removeAt(mi));
                                    _touch();
                                  },
                                ),
                              ],
                            ),
                            for (final (ii, it) in meal.items.indexed)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  it.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: it.kcal == null
                                    ? null
                                    : Text(
                                        '${it.kcal!.round()} kcal${it.protein == null ? '' : ' · ${it.protein!.round()} g protein'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                onTap: () => _editItem(meal, it),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setState(() => meal.items.removeAt(ii));
                                    _touch();
                                  },
                                ),
                              ),
                            TextButton.icon(
                              onPressed: () => _editItem(meal),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Food'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Gap(12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(
                        () => p.meals.add(
                          DietMeal(name: 'Meal ${p.meals.length + 1}'),
                        ),
                      );
                      _touch();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Meal'),
                  ),
                  const Gap(16),
                  AppTextField(
                    controller: _notes,
                    label: 'Notes (optional)',
                    hint: 'Allergies / foods to avoid, hydration…',
                    maxLines: 3,
                    maxLength: 1000,
                    onChanged: (_) => _touch(),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LoadingButton(
                  label: _memberMode || p.id != null
                      ? 'Save'
                      : 'Save Diet Plan',
                  onPressed: _dirty || p.id == null ? _save : null,
                  loading: _saving,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DietEmpty extends StatelessWidget {
  const _DietEmpty({
    required this.memberId,
    required this.onChosen,
    required this.onCreate,
  });
  final String memberId;
  final void Function(DietPlan) onChosen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final repo = getIt<FitnessRepository>();
    final s = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Diet Plan')),
      body: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.restaurant_menu,
              title: 'No diet plan assigned',
              message: 'Choose an existing diet plan, generate one, or create it from scratch.',
              actionLabel: 'Choose Existing Diet Plan',
              onAction: () async {
                final list = await runWithProgress(context, repo.dietTemplates);
                if (list == null || !context.mounted) return;
                if (list.isEmpty) {
                  return showToast(
                    context,
                    "Looks like you haven't created any templates.",
                    error: true,
                  );
                }
                final t = await showPickerSheet<DietPlan>(
                  context,
                  title: 'Choose Existing Diet Plan',
                  items: list,
                  labelOf: (p) => p.name,
                  subtitleOf: (p) =>
                      '${p.calorieTarget ?? '-'} kcal · ${p.meals.length} meals',
                );
                if (t == null || !context.mounted) return;
                final r = await runWithProgress(
                  context,
                  () => repo.assignDiet(t.id!, memberId),
                  success: 'Diet plan assigned successfully',
                );
                if (r != null) onChosen(r);
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                children: [
                  if (s.feature(Feat.aiWorkouts))
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await context.push<bool>(
                            '/diet-plans/generate?memberId=$memberId',
                          );
                          if (ok == true && context.mounted) context.pop(true);
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate Diet Plan'),
                      ),
                    ),
                  TextButton(
                    onPressed: onCreate,
                    child: const Text('Create from scratch'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GenerateDietScreen extends StatefulWidget {
  const GenerateDietScreen({super.key, this.memberId});
  final String? memberId;
  @override
  State<GenerateDietScreen> createState() => _GenerateDietScreenState();
}

class _GenerateDietScreenState extends State<GenerateDietScreen> {
  final _repo = getIt<FitnessRepository>();
  FitnessMeta? _meta;
  String _goal = 'General Fitness';
  String _pref = 'Vegetarian';
  int _meals = 4;
  final _kcal = TextEditingController();
  final Set<String> _allergies = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _repo
        .meta()
        .then((m) => mounted ? setState(() => _meta = m) : null)
        .catchError((Object e) {
          if (mounted) showError(context, e);
        });
  }

  @override
  void dispose() {
    _kcal.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final plan = await _repo.generateDiet({
        if (widget.memberId != null) 'memberId': widget.memberId,
        'goal': _goal,
        'dietaryPreference': _pref,
        'mealsPerDay': _meals,
        if (int.tryParse(_kcal.text.trim()) != null)
          'calorieTarget': int.parse(_kcal.text.trim()),
        'allergies': _allergies.toList(),
      });
      if (!mounted) return;
      final saved = await context.push<bool>(
        '/diet-plans/review${widget.memberId == null ? '' : '?memberId=${widget.memberId}'}',
        extra: plan,
      );
      if (saved == true && mounted) context.pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta;
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Diet Plan')),
      body: m == null
          ? const LoadingBox()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const InfoBanner(
                        'Age, body metrics and weight trend are factored in automatically when a member is selected. Calories are estimated with the Mifflin-St Jeor formula. (Rule-based generator, not an AI model.)',
                        icon: Icons.auto_awesome,
                      ),
                      ChoiceGroup<String>(
                        title: 'Goals',
                        options: m.goals,
                        value: _goal,
                        onChanged: (v) => setState(() => _goal = v),
                      ),
                      ChoiceGroup<String>(
                        title: 'Dietary preference',
                        options: m.dietaryPreferences,
                        value: _pref,
                        onChanged: (v) => setState(() => _pref = v),
                      ),
                      ChoiceGroup<int>(
                        title: 'Meals per day',
                        options: const [3, 4, 5, 6],
                        value: _meals,
                        onChanged: (v) => setState(() => _meals = v),
                      ),
                      const Gap(8),
                      AppTextField(
                        controller: _kcal,
                        label: 'Daily calorie target (optional)',
                        hint: 'Leave empty to estimate',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 12),
                        child: Text(
                          'Allergies / foods to avoid',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final a in [
                            'nuts',
                            'dairy',
                            'gluten',
                            'soy',
                            'egg',
                            'fish',
                          ])
                            PillChip(
                              label: a[0].toUpperCase() + a.substring(1),
                              selected: _allergies.contains(a),
                              onTap: () => setState(
                                () => _allergies.contains(a)
                                    ? _allergies.remove(a)
                                    : _allergies.add(a),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LoadingButton(
                      label: 'Generate Diet Plan',
                      icon: Icons.auto_awesome,
                      loading: _busy,
                      onPressed: _run,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
