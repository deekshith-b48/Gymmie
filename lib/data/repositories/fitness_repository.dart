import '../../core/network/api_client.dart';
import '../../core/util/json.dart';
import '../models/fitness.dart';

class FitnessRepository {
  FitnessRepository(this._api);
  final ApiClient _api;

  Future<FitnessMeta> meta() async =>
      FitnessMeta.fromJson((await _api.get('/v5/exercises/meta')).map);
  Future<List<ExerciseDef>> exercises({String? q, String? category}) async =>
      (await _api.get(
        '/v5/exercises',
        query: {'q': q, 'category': category},
      )).list.map(ExerciseDef.fromJson).toList();
  Future<ExerciseDef> createExercise(Json body) async =>
      ExerciseDef.fromJson((await _api.post('/v5/exercises', body: body)).map);
  Future<ExerciseDef> updateExercise(String id, Json body) async =>
      ExerciseDef.fromJson(
        (await _api.patch('/v5/exercises/$id', body: body)).map,
      );
  Future<void> deleteExercise(String id) async =>
      _api.delete('/v5/exercises/$id');

  // ---- workout ----
  Future<List<WorkoutPlan>> workoutTemplates() async =>
      (await _api.get('/v5/workout/plans')).list
          .map(WorkoutPlan.fromJson)
          .toList();
  Future<WorkoutPlan> workoutPlan(String id) async =>
      WorkoutPlan.fromJson((await _api.get('/v5/workout/plans/$id')).map);
  Future<WorkoutPlan> createWorkout(WorkoutPlan p) async =>
      WorkoutPlan.fromJson(
        (await _api.post('/v5/workout/plans', body: p.toJson())).map,
      );
  Future<WorkoutPlan> updateWorkout(String id, WorkoutPlan p) async =>
      WorkoutPlan.fromJson(
        (await _api.put('/v5/workout/plans/$id', body: p.toJson())).map,
      );
  Future<void> deleteWorkout(String id) async =>
      _api.delete('/v5/workout/plans/$id');
  Future<WorkoutPlan> assignWorkout(String planId, String memberId) async =>
      WorkoutPlan.fromJson(
        (await _api.post(
          '/v5/workout/plans/$planId/assign',
          body: {'memberId': memberId},
        )).map,
      );
  Future<WorkoutPlan?> memberWorkout(String memberId) async {
    final r = await _api.get('/v5/workout/members/$memberId');
    return r.data is Map ? WorkoutPlan.fromJson(r.map) : null;
  }

  Future<WorkoutPlan> saveMemberWorkout(String memberId, WorkoutPlan p) async =>
      WorkoutPlan.fromJson(
        (await _api.put('/v5/workout/members/$memberId', body: p.toJson())).map,
      );
  Future<void> removeMemberWorkout(String memberId) async =>
      _api.delete('/v5/workout/members/$memberId');
  Future<WorkoutPlan> generateWorkout(Json body) async => WorkoutPlan.fromJson(
    (await _api.post('/v5/workout/generate', body: body)).map,
  );

  // ---- diet ----
  Future<List<DietPlan>> dietTemplates() async =>
      (await _api.get('/v5/diet/plans')).list.map(DietPlan.fromJson).toList();
  Future<DietPlan> dietPlan(String id) async =>
      DietPlan.fromJson((await _api.get('/v5/diet/plans/$id')).map);
  Future<DietPlan> createDiet(DietPlan p) async => DietPlan.fromJson(
    (await _api.post('/v5/diet/plans', body: p.toJson())).map,
  );
  Future<DietPlan> updateDiet(String id, DietPlan p) async => DietPlan.fromJson(
    (await _api.put('/v5/diet/plans/$id', body: p.toJson())).map,
  );
  Future<void> deleteDiet(String id) async => _api.delete('/v5/diet/plans/$id');
  Future<DietPlan> assignDiet(String planId, String memberId) async =>
      DietPlan.fromJson(
        (await _api.post(
          '/v5/diet/plans/$planId/assign',
          body: {'memberId': memberId},
        )).map,
      );
  Future<DietPlan?> memberDiet(String memberId) async {
    final r = await _api.get('/v5/diet/members/$memberId');
    return r.data is Map ? DietPlan.fromJson(r.map) : null;
  }

  Future<DietPlan> saveMemberDiet(String memberId, DietPlan p) async =>
      DietPlan.fromJson(
        (await _api.put('/v5/diet/members/$memberId', body: p.toJson())).map,
      );
  Future<void> removeMemberDiet(String memberId) async =>
      _api.delete('/v5/diet/members/$memberId');
  Future<DietPlan> generateDiet(Json body) async =>
      DietPlan.fromJson((await _api.post('/v5/diet/generate', body: body)).map);
}
