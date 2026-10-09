import 'package:flutter/material.dart';
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

class WorkoutPlansScreen extends StatefulWidget {
  const WorkoutPlansScreen({super.key});
  @override
  State<WorkoutPlansScreen> createState() => _WorkoutPlansScreenState();
}

class _WorkoutPlansScreenState extends State<WorkoutPlansScreen> {
  final _repo = getIt<FitnessRepository>();
  late final AsyncCubit<List<WorkoutPlan>> _cubit = AsyncCubit(
    _repo.workoutTemplates,
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
      appBar: AppBar(title: const Text('Workout Plans')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => showAppSheet<void>(
                context,
                title: 'New workout plan',
                builder: (ctx) => Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: const Text('Create from scratch'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await context.push('/workout-plans/new');
                        _cubit.refresh();
                      },
                    ),
                    if (s.feature(Feat.aiWorkouts))
                      ListTile(
                        leading: const Icon(Icons.auto_awesome),
                        title: const Text('Generate Workout Plan'),
                        subtitle: const Text(
                          'Training routine tailored to goals, schedule and equipment (rule-based)',
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await context.push('/workout-plans/generate');
                          _cubit.refresh();
                        },
                      ),
                  ],
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New Workout Plan'),
            )
          : null,
      body: AsyncBody<List<WorkoutPlan>>(
        cubit: _cubit,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyState(
          icon: Icons.fitness_center,
          title: 'No workout plans yet',
          message: 'Create reusable templates and assign them to members.',
        ),
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final p = list[i];
            return AppCard(
              onTap: () async {
                await context.push('/workout-plans/${p.id}');
                _cubit.refresh();
              },
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.chip,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.fitness_center,
                      color: AppColors.navy,
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
                            Tag('${p.days.length} days'),
                            Tag('${p.exerciseCount} exercises'),
                            if (p.goal != null) Tag(p.goal!, tone: Tone.info),
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

/// Create / edit a workout plan (template or a member's own plan).
class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({
    super.key,
    this.planId,
    this.memberId,
    this.draft,
  });
  final String? planId;
  final String? memberId;
  final WorkoutPlan? draft;
  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  final _repo = getIt<FitnessRepository>();
  WorkoutPlan? _plan;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;
  final _name = TextEditingController();
  final _desc = TextEditingController();

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
      WorkoutPlan? p = widget.draft;
      if (p == null && widget.planId != null) {
        p = await _repo.workoutPlan(widget.planId!);
      }
      if (p == null && _memberMode) {
        p = await _repo.memberWorkout(widget.memberId!);
      }
      if (p == null && widget.planId == null && !_memberMode) {
        p = WorkoutPlan(
          name: '',
          days: [WorkoutDay(name: 'Day 1')],
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

  void _setPlan(WorkoutPlan? p) {
    _plan = p;
    _name.text = p?.name ?? '';
    _desc.text = p?.description ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  Future<void> _save() async {
    final p = _plan!;
    p.name = _name.text.trim();
    p.description = _desc.text.trim();
    if (p.name.isEmpty) {
      return showToast(context, 'Please enter a name', error: true);
    }
    if (p.days.isEmpty) {
      return showToast(context, 'Please add at least one day', error: true);
    }
    if (p.days.any((d) => d.exercises.isEmpty)) {
      return showToast(
        context,
        'Every day needs at least one exercise',
        error: true,
      );
    }
    setState(() => _saving = true);
    try {
      WorkoutPlan saved;
      if (_memberMode) {
        saved = await _repo.saveMemberWorkout(widget.memberId!, p);
      } else if (p.id != null) {
        saved = await _repo.updateWorkout(p.id!, p);
      } else {
        saved = await _repo.createWorkout(p);
      }
      if (!mounted) return;
      setState(() {
        _plan = saved;
        _dirty = false;
      });
      showToast(
        context,
        p.id == null && !_memberMode
            ? 'Workout plan created successfully'
            : 'Workout plan updated successfully',
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addExercise(WorkoutDay day) async {
    final ex = await context.push<ExerciseDef>('/exercises/select');
    if (ex == null) return;
    setState(
      () => day.exercises.add(
        WorkoutExercise(
          exerciseId: ex.id.startsWith('lib:') || !ex.builtIn ? ex.id : null,
          name: ex.name,
        ),
      ),
    );
    _touch();
  }

  Future<void> _editExercise(WorkoutExercise e) async {
    final sets = TextEditingController(text: '${e.sets}');
    final reps = TextEditingController(text: e.reps);
    final rest = TextEditingController(text: '${e.restSec}');
    final notes = TextEditingController(text: e.notes);
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: e.name,
      builder: (ctx) => Form(
        key: key,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: sets,
                    label: 'Sets',
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        V.integer(v, min: 1, max: 20, label: '1-20'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: reps,
                    label: 'Reps',
                    hint: '8-12',
                    validator: (v) => V.required(v, 'Required'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: rest,
                    label: 'Rest (seconds, optional)',
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        V.integer(v, min: 0, max: 900, label: '0-900'),
                  ),
                ),
              ],
            ),
            const Gap(12),
            AppTextField(
              controller: notes,
              label: 'Notes',
              hint: 'Add a short note',
              maxLength: 300,
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
        e.sets = int.parse(sets.text.trim());
        e.reps = reps.text.trim();
        e.restSec = int.parse(rest.text.trim());
        e.notes = notes.text.trim().isEmpty ? null : notes.text.trim();
      });
      _touch();
    }
    for (final c in [sets, reps, rest, notes]) {
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
      title: 'Assign Members',
      status: 'active',
    );
    if (m == null || !mounted) return;
    final r = await runWithProgress(
      context,
      () => _repo.assignWorkout(p.id!, m.id),
      success: 'Workout plan assigned successfully',
    );
    if (r != null && mounted) showToast(context, 'Assigned to ${m.name}');
  }

  @override
  Widget build(BuildContext context) {
    final s = getIt<SessionCubit>().state;
    final title = _memberMode
        ? 'Workout Plan'
        : (_plan?.id == null ? 'New Workout Plan' : 'Edit Workout Plan');
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
      return _MemberEmpty(
        memberId: widget.memberId!,
        kind: 'workout',
        onChosen: (p) {
          setState(() => _setPlan(p as WorkoutPlan));
        },
        onCreate: () => setState(() {
          _setPlan(
            WorkoutPlan(
              name: '',
              days: [WorkoutDay(name: 'Day 1')],
              ownerType: 'member',
              memberId: widget.memberId,
            ),
          );
          _dirty = true;
        }),
      );
    }
    final p = _plan!;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final save = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes?'),
            content: const Text(
              'Your changes to this workout plan have not been saved. Would you like to save before leaving?',
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
            if (p.exerciseCount > 0)
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Workout Plan Share',
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
                tooltip: 'Assign Members',
                onPressed: _assign,
              ),
            if (p.id != null && s.can(Perm.plansetsWrite))
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmDialog(
                        context,
                        title: _memberMode
                            ? 'Remove plan'
                            : 'Delete Workout Plan',
                        message: _memberMode
                            ? 'Remove this plan from the member?'
                            : 'Do you want to delete this workout plan? This action cannot be undone.',
                        confirmLabel: 'Delete',
                        destructive: true,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  final ok = await runOk(
                    context,
                    () => _memberMode
                        ? _repo.removeMemberWorkout(widget.memberId!)
                        : _repo.deleteWorkout(p.id!),
                    success: 'Workout plan deleted successfully',
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
                    label: 'Workout Plan Name',
                    hint: 'Eg. Strength Training etc...',
                    maxLength: 80,
                    onChanged: (_) => _touch(),
                  ),
                  const Gap(12),
                  AppTextField(
                    controller: _desc,
                    label: 'Description (optional)',
                    hint: 'Add a short note',
                    maxLength: 500,
                    onChanged: (_) => _touch(),
                  ),
                  const Gap(8),
                  for (final (di, day) in p.days.indexed)
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
                                        title: 'Day Name',
                                        label: 'Day Name',
                                        hint: 'Eg. Day 1, Chest Day, etc.',
                                        initial: day.name,
                                        required: true,
                                        maxLength: 60,
                                      );
                                      if (n != null) {
                                        setState(() => day.name = n);
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
                                              day.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: AppColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete Day',
                                  onPressed: () async {
                                    if (await confirmDialog(
                                      context,
                                      title: 'Delete Day',
                                      message: 'Do you want to delete this day? This action cannot be undone.',
                                      confirmLabel: 'Delete',
                                      destructive: true,
                                    )) {
                                      setState(() => p.days.removeAt(di));
                                      _touch();
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (day.exercises.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'No exercises yet',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorderItem: (a, b) {
                                setState(
                                  () => day.exercises.insert(
                                    b,
                                    day.exercises.removeAt(a),
                                  ),
                                );
                                _touch();
                              },
                              children: [
                                for (final (ei, e) in day.exercises.indexed)
                                  ListTile(
                                    key: ValueKey(e.id),
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    leading: ReorderableDragStartListener(
                                      index: ei,
                                      child: const Icon(
                                        Icons.drag_indicator,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    title: Text(
                                      e.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${e.sets} × ${e.reps}${e.restSec > 0 ? ' · rest ${e.restSec}s' : ''}${e.notes == null ? '' : ' · ${e.notes}'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onTap: () => _editExercise(e),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      tooltip:
                                          'Remove this exercise from the day?',
                                      onPressed: () {
                                        setState(
                                          () => day.exercises.removeAt(ei),
                                        );
                                        _touch();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () => _addExercise(day),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Exercise'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Gap(12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(
                        () => p.days.add(
                          WorkoutDay(name: 'Day ${p.days.length + 1}'),
                        ),
                      );
                      _touch();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Day'),
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
                      : 'Save Workout Plan',
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

/// Empty state for a member without a plan: choose a template, generate, or create.
class _MemberEmpty extends StatelessWidget {
  const _MemberEmpty({
    required this.memberId,
    required this.kind,
    required this.onChosen,
    required this.onCreate,
  });
  final String memberId;
  final String kind; // workout | diet
  final void Function(Object plan) onChosen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final repo = getIt<FitnessRepository>();
    final isWorkout = kind == 'workout';
    final s = getIt<SessionCubit>().state;
    return Scaffold(
      appBar: AppBar(title: Text(isWorkout ? 'Workout Plan' : 'Diet Plan')),
      body:
          EmptyState(
            icon: isWorkout ? Icons.fitness_center : Icons.restaurant_menu,
            title: isWorkout
                ? 'No workout plan assigned'
                : 'No diet plan assigned',
            message: 'Choose Your Templates, generate one, or create it from scratch.',
            actionLabel: 'Choose existing templates!',
            onAction: () async {
              if (isWorkout) {
                final list = await runWithProgress(
                  context,
                  repo.workoutTemplates,
                );
                if (list == null || !context.mounted) return;
                if (list.isEmpty) {
                  return showToast(
                    context,
                    "Looks like you haven't created any templates.",
                    error: true,
                  );
                }
                final t = await showPickerSheet<WorkoutPlan>(
                  context,
                  title: 'Choose Your Templates',
                  items: list,
                  labelOf: (p) => p.name,
                  subtitleOf: (p) =>
                      '${p.days.length} days · ${p.exerciseCount} exercises',
                );
                if (t == null || !context.mounted) return;
                final r = await runWithProgress(
                  context,
                  () => repo.assignWorkout(t.id!, memberId),
                  success: 'Workout plan assigned successfully',
                );
                if (r != null) onChosen(r);
              } else {
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
              }
            },
          ).wrapWithExtras(context, [
            if ((isWorkout
                ? s.feature(Feat.aiWorkouts)
                : s.feature(Feat.aiWorkouts)))
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await context.push<bool>(
                    '${isWorkout ? '/workout-plans' : '/diet-plans'}/generate?memberId=$memberId',
                  );
                  if (ok == true && context.mounted) context.pop(true);
                },
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  isWorkout ? 'Generate Workout Plan' : 'Generate Diet Plan',
                ),
              ),
            TextButton(
              onPressed: onCreate,
              child: const Text('Create from scratch'),
            ),
          ]),
    );
  }
}

extension on Widget {
  Widget wrapWithExtras(BuildContext context, List<Widget> extras) => Column(
    children: [
      Expanded(child: this),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            children: [
              for (final e in extras)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(width: double.infinity, child: e),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// "Generate Workout Plan": collects goals, runs the generator, opens the result for review.
class GenerateWorkoutScreen extends StatefulWidget {
  const GenerateWorkoutScreen({super.key, this.memberId});
  final String? memberId;
  @override
  State<GenerateWorkoutScreen> createState() => _GenerateWorkoutScreenState();
}

class _GenerateWorkoutScreenState extends State<GenerateWorkoutScreen> {
  final _repo = getIt<FitnessRepository>();
  FitnessMeta? _meta;
  String _goal = 'General Fitness';
  String _level = 'Beginner';
  int _days = 3;
  int _minutes = 60;
  final Set<String> _equipment = {'Full Gym'};
  final Set<String> _conditions = {};
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

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final plan = await _repo.generateWorkout({
        if (widget.memberId != null) 'memberId': widget.memberId,
        'goal': _goal,
        'level': _level,
        'daysPerWeek': _days,
        'sessionMinutes': _minutes,
        'equipment': _equipment.toList(),
        'conditions': _conditions.toList(),
      });
      if (!mounted) return;
      final saved = await context.push<bool>(
        '/workout-plans/review${widget.memberId == null ? '' : '?memberId=${widget.memberId}'}',
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
      appBar: AppBar(title: const Text('Generate Workout Plan')),
      body: m == null
          ? const LoadingBox()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const InfoBanner(
                        'Smart training routines tailored to goals, schedule and equipment. Health flags on the member profile are factored in automatically. (Rule-based generator, not an AI model.)',
                        icon: Icons.auto_awesome,
                      ),
                      ChoiceGroup<String>(
                        title: 'Primary activity',
                        options: m.goals,
                        value: _goal,
                        onChanged: (v) => setState(() => _goal = v),
                      ),
                      ChoiceGroup<String>(
                        title: 'Experience level',
                        options: m.levels,
                        value: _level,
                        onChanged: (v) => setState(() => _level = v),
                      ),
                      ChoiceGroup<int>(
                        title: 'Training days per week',
                        options: const [2, 3, 4, 5, 6],
                        value: _days,
                        onChanged: (v) => setState(() => _days = v),
                      ),
                      ChoiceGroup<int>(
                        title: 'Session length',
                        options: const [30, 45, 60, 75, 90],
                        value: _minutes,
                        labelOf: (v) => '$v min',
                        onChanged: (v) => setState(() => _minutes = v),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 12),
                        child: Text(
                          'Available equipment',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final e in m.equipment)
                            PillChip(
                              label: e,
                              selected: _equipment.contains(e),
                              onTap: () => setState(
                                () => _equipment.contains(e)
                                    ? _equipment.remove(e)
                                    : _equipment.add(e),
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 12),
                        child: Text(
                          'Injury / limitations',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in [
                            'Knee Pain',
                            'Back Pain',
                            'Shoulder Pain',
                            'Neck Pain',
                            'Hip Pain',
                            'High BP',
                            'Heart Problem',
                            'Asthma',
                          ])
                            PillChip(
                              label: c,
                              selected: _conditions.contains(c),
                              onTap: () => setState(
                                () => _conditions.contains(c)
                                    ? _conditions.remove(c)
                                    : _conditions.add(c),
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
                      label: 'Generate Workout Plan',
                      icon: Icons.auto_awesome,
                      loading: _busy,
                      onPressed: _equipment.isEmpty ? null : _run,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
