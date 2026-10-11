import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../core/auth/permissions.dart';
import '../../core/state/async_cubit.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/launch.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/list_toolbar.dart';
import '../../core/widgets/exercise_animation.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../data/models/fitness.dart';
import '../../data/repositories/fitness_repository.dart';

/// Exercise library: built-in exercises plus the gym's own. `selectMode` returns the chosen exercise.
class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key, this.selectMode = false});
  final bool selectMode;
  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  final _repo = getIt<FitnessRepository>();
  String _q = '';
  String? _category;
  late final AsyncCubit<List<ExerciseDef>> _cubit = AsyncCubit(
    () => _repo.exercises(q: _q.isEmpty ? null : _q, category: _category),
  );
  List<String> _categories = const [];

  @override
  void initState() {
    super.initState();
    _repo
        .meta()
        .then(
          (m) => mounted ? setState(() => _categories = m.categories) : null,
        )
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  /// The exercise's animation, as in openGym: the still, then the clip plays over it (tap to pause).
  Future<void> _preview(ExerciseDef e) => showExerciseAnimation(
    context,
    e.name,
    ExerciseMediaUrls(e.imageUrl, e.clipUrl),
    subtitle: '${e.category}${e.equipment.isEmpty ? '' : ' · ${e.equipment.take(3).join(', ')}'}',
  );

  Future<void> _edit([ExerciseDef? e]) async {
    final name = TextEditingController(text: e?.name);
    final instr = TextEditingController(text: e?.instructions);
    final video = TextEditingController(text: e?.videoUrl);
    var cat = e?.category ?? (_categories.firstOrNull ?? 'Chest');
    final key = GlobalKey<FormState>();
    final ok = await showAppSheet<bool>(
      context,
      title: e == null ? 'Add Exercise' : 'Edit Exercise',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: name,
                label: 'Exercise Name',
                hint: 'Eg: Jumping Jacks etc.',
                validator: (v) =>
                    V.required(v, 'Please enter an exercise name'),
                maxLength: 100,
              ),
              const Gap(12),
              DropdownField<String>(
                label: 'Category',
                value: cat,
                items: _categories,
                onChanged: (v) => set(() => cat = v ?? cat),
              ),
              const Gap(12),
              AppTextField(
                controller: instr,
                label: 'Instructions (optional)',
                maxLines: 3,
                maxLength: 1000,
              ),
              const Gap(12),
              AppTextField(
                controller: video,
                label: 'Video link (optional)',
                hint: 'https://…',
                keyboardType: TextInputType.url,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? null : V.url(v),
              ),
              const Gap(16),
              FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final body = {
        'name': name.text.trim(),
        'category': cat,
        if (instr.text.trim().isNotEmpty) 'instructions': instr.text.trim(),
        if (video.text.trim().isNotEmpty) 'videoUrl': video.text.trim(),
      };
      if (await runOk(
        context,
        () => e == null
            ? _repo.createExercise(body).then((_) {})
            : _repo.updateExercise(e.id, body).then((_) {}),
        success: e == null
            ? 'Exercise created successfully'
            : 'Exercise updated successfully',
      )) {
        _cubit.refresh();
      }
    }
    for (final c in [name, instr, video]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = getIt<SessionCubit>().state.can(Perm.plansetsWrite);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Search Exercises' : 'Exercises'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: ListToolbar(
                hint: 'Search your exercise here',
                onSearch: (v) {
                  _q = v;
                  _cubit.load();
                },
                onAdd: canWrite ? () => _edit() : null,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  PillChip(
                    label: 'All',
                    selected: _category == null,
                    onTap: () {
                      setState(() => _category = null);
                      _cubit.load();
                    },
                  ),
                  for (final c in _categories)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: PillChip(
                        label: c,
                        selected: _category == c,
                        onTap: () {
                          setState(() => _category = c);
                          _cubit.load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<List<ExerciseDef>>(
                cubit: _cubit,
                isEmpty: (d) => d.isEmpty,
                empty: const EmptyState(
                  icon: Icons.search_off,
                  title: 'No exercises found',
                ),
                builder: (context, list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      onTap: widget.selectMode
                          ? () => context.pop(e)
                          : (!e.builtIn && canWrite
                              ? () => _edit(e)
                              : (e.clipUrl != null ? () => _preview(e) : null)),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: AppColors.chip,
                              child: e.imageUrl == null
                                  ? Icon(Icons.fitness_center, size: 20, color: AppColors.navy)
                                  : Image.network(
                                      e.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(Icons.fitness_center, size: 20, color: AppColors.navy),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${e.category}${e.equipment.isEmpty ? '' : ' · ${e.equipment.take(2).join(', ')}'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (e.clipUrl != null)
                            IconButton(
                              tooltip: 'Watch the exercise',
                              icon: const Icon(Icons.play_circle_fill_rounded),
                              onPressed: () => _preview(e),
                            ),
                          if (e.videoUrl != null)
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline),
                              onPressed: () => Launch.url(context, e.videoUrl!),
                            ),
                          if (!e.builtIn) const Tag('Custom', tone: Tone.info),
                          if (!e.builtIn && canWrite && !widget.selectMode)
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                                size: 20,
                              ),
                              onPressed: () async {
                                if (!await confirmDialog(
                                      context,
                                      title: 'Delete Exercise',
                                      message: 'Do you want to delete this exercise? This action cannot be undone.',
                                      confirmLabel: 'Delete',
                                      destructive: true,
                                    ) ||
                                    !context.mounted) {
                                  return;
                                }
                                if (await runOk(
                                  context,
                                  () => _repo.deleteExercise(e.id),
                                  success: 'Exercise deleted successfully',
                                )) {
                                  _cubit.refresh();
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
