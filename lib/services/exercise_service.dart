import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseService {
  final supabase = Supabase.instance.client;

  Future<List<dynamic>> getExercisesForEquipment(String equipmentId) async {
    final res = await supabase
        .from('exercises')
        .select()
        .eq('equipment_id', equipmentId);

    return res;
  }

  Future<void> insertExercise({
    required String name,
    required String primaryMuscleGroup,
    required String type,
    required String equipmentId,
  }) async {
    final muscleGroupLower = primaryMuscleGroup.toLowerCase();

    await supabase.from('exercises').insert({
      'name': name,
      'primary_muscle_group': muscleGroupLower,
      'type': type,
      'equipment_id': equipmentId,
    });
  }

  Future<void> updateExerciseName({
    required String exerciseId,
    required String name,
  }) async {
    await supabase.from('exercises').update({'name': name}).eq('id', exerciseId);
  }

  /// ✅ Move an exercise to another equipment
  Future<void> moveExerciseToEquipment({
    required String exerciseId,
    required String equipmentId,
  }) async {
    await supabase
        .from('exercises')
        .update({'equipment_id': equipmentId})
        .eq('id', exerciseId);
  }

  Future<void> deleteExercise(String exerciseId) async {
    await supabase.from('exercises').delete().eq('id', exerciseId);
  }

  // ✅ Count how many sessions exist for an exercise
  Future<int> getSessionCountForExercise(String exerciseId) async {
    final res = await supabase
        .from('exercise_sessions')
        .select('id')
        .eq('exercise_id', exerciseId);

    return (res as List).length;
  }

  // ✅ Delete all sessions for an exercise (cascade behavior)
  Future<void> deleteSessionsForExercise(String exerciseId) async {
    await supabase.from('exercise_sessions').delete().eq('exercise_id', exerciseId);
  }

  // ✅ Cascade: delete sessions first, then exercise
  Future<void> deleteExerciseCascade(String exerciseId) async {
    await deleteSessionsForExercise(exerciseId);
    await deleteExercise(exerciseId);
  }
}
