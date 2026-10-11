// The exercise catalogue (assets/member/exercises.json, exported from openGym by
// member-app/scripts/export-catalogue.mjs) plus the member's own custom exercises.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'rows.dart';

/// Used for custom exercises, which carry only a body part (openGym lib/muscles.js BY_BODYPART).
const bodypartMuscles = <String, Map<String, double>>{
  'chest': {'chest': 1},
  'back': {'upper-back': 0.75, 'lower-back': 0.25},
  'shoulders': {'deltoids': 1},
  'upper arms': {'biceps': 0.5, 'triceps': 0.5},
  'lower arms': {'forearm': 1},
  'waist': {'abs': 0.7, 'obliques': 0.3},
  'upper legs': {'quadriceps': 0.4, 'hamstring': 0.35, 'gluteal': 0.25},
  'lower legs': {'calves': 0.8, 'tibialis': 0.2},
  'neck': {'trapezius': 1},
  'full body': {'chest': 0.2, 'upper-back': 0.2, 'gluteal': 0.2, 'quadriceps': 0.2, 'hamstring': 0.1, 'abs': 0.1},
  'cardio': <String, double>{},
};

/// openGym shows catalogue names capitalised (its CSS does it); the dataset stores them lower case.
String titleCase(String s) => s.replaceAllMapped(RegExp(r'(^|[\s(/-])([a-z])'), (m) => '${m[1]}${m[2]!.toUpperCase()}');

class Muscle {
  const Muscle(this.id, this.name);
  final String id;
  final String name;
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.bodypart,
    required this.equipment,
    required this.category,
    required this.img,
    required this.gif,
    required this.weights,
    this.cardio = false,
    this.assisted = false,
    this.custom = false,
  });

  final String id;
  final String name;
  final String bodypart;
  final String equipment;
  final String category;
  final String img;
  final String gif;
  final Map<String, double> weights;
  final bool cardio;
  final bool assisted;
  final bool custom;

  bool trains(String muscle) => (weights[muscle] ?? 0) > 0;
  bool primaryFor(String muscle) => weights[muscle] == 1;

  /// How an exercise is logged by default (openGym modeOf): cardio rows are minutes and speed.
  String get mode => cardio ? 'cardio' : 'reps';

  factory Exercise.fromCatalogue(Json j) => Exercise(
    id: '${j['id']}',
    name: titleCase('${j['n']}'),
    bodypart: '${j['bp'] ?? ''}',
    equipment: '${j['eq'] ?? ''}',
    category: '${j['cat'] ?? ''}',
    img: '${j['img'] ?? ''}',
    gif: '${j['gif'] ?? ''}',
    weights: {for (final e in asMap(j['w']).entries) e.key: (e.value as num).toDouble()},
    cardio: j['cardio'] == true,
    assisted: j['assisted'] == true,
  );

  /// A member-made exercise (state.customEx): a name and a body part.
  factory Exercise.fromCustom(Json j) {
    final bp = '${j['bp'] ?? ''}';
    return Exercise(
      id: '${j['id']}',
      name: '${j['n'] ?? j['name'] ?? 'Exercise'}',
      bodypart: bp,
      equipment: '${j['eq'] ?? ''}',
      category: '',
      img: '',
      gif: '',
      weights: bodypartMuscles[bp] ?? const {},
      cardio: bp == 'cardio',
      custom: true,
    );
  }
}

class Catalogue {
  Catalogue._(this.exercises, this.muscles, this.bodyparts)
    : _byId = {for (final e in exercises) e.id: e};

  final List<Exercise> exercises;
  final List<Muscle> muscles;
  final List<String> bodyparts;
  final Map<String, Exercise> _byId;

  static Catalogue? _cache;

  static Future<Catalogue> load() async {
    final c = _cache;
    if (c != null) return c;
    final raw = await rootBundle.loadString('assets/member/exercises.json');
    return _cache = parse(raw);
  }

  static Catalogue parse(String raw) {
    final j = asMap(jsonDecode(raw));
    return Catalogue._(
      [for (final e in asRows(j['exercises'])) Exercise.fromCatalogue(e)],
      [for (final m in asRows(j['muscles'])) Muscle('${m['id']}', '${m['name']}')],
      [for (final b in (j['bodyparts'] as List? ?? const [])) '$b'],
    );
  }

  Exercise? byId(String id) => _byId[id];
  String muscleName(String id) => muscles.firstWhere((m) => m.id == id, orElse: () => Muscle(id, id)).name;

  /// The catalogue plus the member's custom exercises.
  List<Exercise> withCustom(Object? customEx) => [
    ...exercises,
    for (final c in asRows(customEx)) Exercise.fromCustom(c),
  ];

  Exercise? find(String id, Object? customEx) {
    final built = _byId[id];
    if (built != null) return built;
    for (final c in asRows(customEx)) {
      if ('${c['id']}' == id) return Exercise.fromCustom(c);
    }
    return null;
  }
}

/// Exercises that train any of [muscles]; primary hits first, helpers after (stable within each).
List<Exercise> exercisesForFocus(Iterable<Exercise> list, Set<String> muscles) {
  if (muscles.isEmpty) return const [];
  int score(Exercise e) {
    var best = 0;
    for (final m in muscles) {
      final w = e.weights[m] ?? 0;
      final s = w == 1 ? 2 : (w > 0 ? 1 : 0);
      if (s > best) best = s;
    }
    return best;
  }
  final scored = [for (final e in list) (e, score(e))].where((x) => x.$2 > 0).toList();
  // Dart's sort is not stable; sort on (score desc, original index).
  final indexed = [for (var i = 0; i < scored.length; i++) (scored[i].$1, scored[i].$2, i)];
  indexed.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final x in indexed) x.$1];
}

/// Every word of [query] must appear in the name, body part, equipment or category.
List<Exercise> searchExercises(Iterable<Exercise> list, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return list.toList();
  return [
    for (final e in list)
      if (words.every((w) => '${e.name} ${e.bodypart} ${e.equipment} ${e.category}'.toLowerCase().contains(w))) e,
  ];
}
