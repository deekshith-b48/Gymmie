import 'package:uuid/uuid.dart';

import '../../core/util/json.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class ExerciseDef {
  const ExerciseDef({
    required this.id,
    required this.name,
    required this.category,
    this.equipment = const [],
    this.builtIn = false,
    this.instructions,
    this.videoUrl,
  });
  final String id;
  final String name;
  final String category;
  final List<String> equipment;
  final bool builtIn;
  final String? instructions;
  final String? videoUrl;
  factory ExerciseDef.fromJson(Json j) => ExerciseDef(
    id: j.s('id'),
    name: j.s('name'),
    category: j.s('category'),
    equipment: j.strings('equipment'),
    builtIn: j.b('builtIn'),
    instructions: j.str('instructions'),
    videoUrl: j.str('videoUrl'),
  );
}

class FitnessMeta {
  const FitnessMeta({
    required this.categories,
    required this.equipment,
    required this.goals,
    required this.levels,
    required this.dietaryPreferences,
    required this.conditions,
  });
  final List<String> categories;
  final List<String> equipment;
  final List<String> goals;
  final List<String> levels;
  final List<String> dietaryPreferences;
  final List<String> conditions;
  factory FitnessMeta.fromJson(Json j) => FitnessMeta(
    categories: j.strings('categories'),
    equipment: j.strings('equipment'),
    goals: j.strings('goals'),
    levels: j.strings('levels'),
    dietaryPreferences: j.strings('dietaryPreferences'),
    conditions: j.strings('conditions'),
  );
}

class WorkoutExercise {
  WorkoutExercise({
    String? id,
    this.exerciseId,
    required this.name,
    this.sets = 3,
    this.reps = '10',
    this.restSec = 60,
    this.notes,
  }) : id = id ?? newId();
  final String id;
  String? exerciseId;
  String name;
  int sets;
  String reps;
  int restSec;
  String? notes;
  factory WorkoutExercise.fromJson(Json j) => WorkoutExercise(
    id: j.str('id'),
    exerciseId: j.str('exerciseId'),
    name: j.s('name'),
    sets: j.i('sets', 3),
    reps: j.s('reps', '10'),
    restSec: j.i('restSec', 60),
    notes: j.str('notes'),
  );
  Json toJson() => {
    'id': id,
    if (exerciseId != null) 'exerciseId': exerciseId,
    'name': name,
    'sets': sets,
    'reps': reps,
    'restSec': restSec,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };
}

class WorkoutDay {
  WorkoutDay({String? id, required this.name, List<WorkoutExercise>? exercises})
    : id = id ?? newId(),
      exercises = exercises ?? [];
  final String id;
  String name;
  List<WorkoutExercise> exercises;
  factory WorkoutDay.fromJson(Json j) => WorkoutDay(
    id: j.str('id'),
    name: j.s('name'),
    exercises: j.list('exercises').map(WorkoutExercise.fromJson).toList(),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };
}

class WorkoutPlan {
  WorkoutPlan({
    this.id,
    required this.name,
    this.goal,
    this.level,
    this.description,
    List<WorkoutDay>? days,
    this.ownerType = 'template',
    this.memberId,
    this.warnings = const [],
    this.generator,
  }) : days = days ?? [];
  String? id;
  String name;
  String? goal;
  String? level;
  String? description;
  List<WorkoutDay> days;
  String ownerType;
  String? memberId;
  List<String> warnings;
  String? generator;

  factory WorkoutPlan.fromJson(Json j) => WorkoutPlan(
    id: j.str('id'),
    name: j.s('name'),
    goal: j.str('goal'),
    level: j.str('level'),
    description: j.str('description'),
    days: j.list('days').map(WorkoutDay.fromJson).toList(),
    ownerType: j.s('ownerType', 'template'),
    memberId: j.str('memberId'),
    warnings: j.strings('warnings'),
    generator: j.str('generator'),
  );
  Json toJson() => {
    'name': name,
    if (goal != null) 'goal': goal,
    if (level != null) 'level': level,
    if (description != null && description!.isNotEmpty)
      'description': description,
    'days': days.map((d) => d.toJson()).toList(),
  };

  int get exerciseCount => days.fold(0, (s, d) => s + d.exercises.length);

  String toShareText(String gym) {
    final b = StringBuffer('$name — $gym\n');
    if (goal != null) {
      b.writeln('Goal: $goal${level == null ? '' : ' · $level'}');
    }
    for (final d in days) {
      b.writeln('\n${d.name}');
      for (final (i, e) in d.exercises.indexed) {
        b.writeln(
          '${i + 1}. ${e.name} — ${e.sets} x ${e.reps}${e.restSec > 0 ? ' (rest ${e.restSec}s)' : ''}',
        );
      }
    }
    return b.toString();
  }
}

class DietItem {
  DietItem({
    String? id,
    required this.name,
    this.quantity = 1,
    this.unit,
    this.kcal,
    this.protein,
    this.notes,
  }) : id = id ?? newId();
  final String id;
  String name;
  double quantity;
  String? unit;
  double? kcal;
  double? protein;
  String? notes;
  factory DietItem.fromJson(Json j) => DietItem(
    id: j.str('id'),
    name: j.s('name'),
    quantity: j.d('quantity', 1),
    unit: j.str('unit'),
    kcal: j.dblOrNull('kcal'),
    protein: j.dblOrNull('protein'),
    notes: j.str('notes'),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    if (unit != null) 'unit': unit,
    if (kcal != null) 'kcal': kcal,
    if (protein != null) 'protein': protein,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };
  String get label =>
      '${quantity % 1 == 0 ? quantity.toInt() : quantity}${unit == null ? '' : ' $unit'} $name';
}

class DietMeal {
  DietMeal({String? id, required this.name, this.time, List<DietItem>? items})
    : id = id ?? newId(),
      items = items ?? [];
  final String id;
  String name;
  String? time;
  List<DietItem> items;
  factory DietMeal.fromJson(Json j) => DietMeal(
    id: j.str('id'),
    name: j.s('name'),
    time: j.str('time'),
    items: j.list('items').map(DietItem.fromJson).toList(),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    if (time != null) 'time': time,
    'items': items.map((i) => i.toJson()).toList(),
  };
  double get kcal => items.fold(0, (s, i) => s + (i.kcal ?? 0));
}

class DietPlan {
  DietPlan({
    this.id,
    required this.name,
    this.goal,
    this.dietaryPreference,
    this.calorieTarget,
    this.protein,
    this.carbs,
    this.fat,
    this.notes,
    List<DietMeal>? meals,
    this.ownerType = 'template',
    this.memberId,
    this.warnings = const [],
    this.generator,
  }) : meals = meals ?? [];
  String? id;
  String name;
  String? goal;
  String? dietaryPreference;
  int? calorieTarget;
  double? protein;
  double? carbs;
  double? fat;
  String? notes;
  List<DietMeal> meals;
  String ownerType;
  String? memberId;
  List<String> warnings;
  String? generator;

  factory DietPlan.fromJson(Json j) {
    final m = j.obj('macros') ?? const {};
    return DietPlan(
      id: j.str('id'),
      name: j.s('name'),
      goal: j.str('goal'),
      dietaryPreference: j.str('dietaryPreference'),
      calorieTarget: j.intOrNull('calorieTarget'),
      protein: m.dblOrNull('protein'),
      carbs: m.dblOrNull('carbs'),
      fat: m.dblOrNull('fat'),
      notes: j.str('notes'),
      meals: j.list('meals').map(DietMeal.fromJson).toList(),
      ownerType: j.s('ownerType', 'template'),
      memberId: j.str('memberId'),
      warnings: j.strings('warnings'),
      generator: j.str('generator'),
    );
  }

  Json toJson() => {
    'name': name,
    if (goal != null) 'goal': goal,
    if (dietaryPreference != null) 'dietaryPreference': dietaryPreference,
    if (calorieTarget != null) 'calorieTarget': calorieTarget,
    if (protein != null || carbs != null || fat != null)
      'macros': {
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
      },
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    'meals': meals.map((m) => m.toJson()).toList(),
  };

  String toShareText(String gym) {
    final b = StringBuffer('$name — $gym\n');
    if (calorieTarget != null) {
      b.writeln(
        'Daily target: $calorieTarget kcal${protein == null ? '' : ' · P ${protein!.round()}g C ${carbs?.round() ?? 0}g F ${fat?.round() ?? 0}g'}',
      );
    }
    for (final m in meals) {
      b.writeln('\n${m.name}${m.time == null ? '' : ' (${m.time})'}');
      for (final i in m.items) {
        b.writeln(
          '• ${i.label}${i.kcal == null ? '' : ' — ${i.kcal!.round()} kcal'}',
        );
      }
    }
    return b.toString();
  }
}
