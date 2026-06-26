import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseService {
  final supabase = Supabase.instance.client;

  // -----------------------------
  // READ
  // -----------------------------

  Future<List<dynamic>> getExercisesForEquipment(String equipmentId) async {
    final res = await supabase
        .from('exercises')
        .select()
        .eq('equipment_id', equipmentId);

    return res;
  }

  /// ✅ NEW: Load exercises included in a routine via routine_items
  Future<List<Map<String, dynamic>>> getExercisesForRoutine(String routineId) async {
    final rows = await supabase
        .from('routine_items')
        .select('exercise:exercises(*)')
        .eq('routine_id', routineId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    final list = <Map<String, dynamic>>[];

    if (rows is List) {
      for (final r in rows) {
        if (r is Map && r['exercise'] is Map) {
          list.add(Map<String, dynamic>.from(r['exercise'] as Map));
        }
      }
    }

    return list;
  }

  // -----------------------------
  // CREATE / UPDATE
  // -----------------------------

  Future<Map<String, dynamic>> insertExerciseReturningRow({
    required String name,
    required String primaryMuscleGroup,
    required String type,
    required String equipmentId,
  }) async {
    final muscleGroupLower = primaryMuscleGroup.toLowerCase();

    final res = await supabase
        .from('exercises')
        .insert({
          'name': name,
          'primary_muscle_group': muscleGroupLower,
          'type': type,
          'equipment_id': equipmentId,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  Future<void> insertExercise({
    required String name,
    required String primaryMuscleGroup,
    required String type,
    required String equipmentId,
  }) async {
    await insertExerciseReturningRow(
      name: name,
      primaryMuscleGroup: primaryMuscleGroup,
      type: type,
      equipmentId: equipmentId,
    );
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

  // -----------------------------
  // ROUTINES (routine_items)
  // -----------------------------

  /// ✅ Add a canonical exercise to a routine (no duplication)
  Future<void> addExerciseToRoutine({
    required String routineId,
    required String exerciseId,
    int? sortOrder,
  }) async {
    // Avoid duplicates (same exercise already in routine)
    final existing = await supabase
        .from('routine_items')
        .select('id')
        .eq('routine_id', routineId)
        .eq('exercise_id', exerciseId);

    if (existing is List && existing.isNotEmpty) return;

    final data = <String, dynamic>{
      'routine_id': routineId,
      'exercise_id': exerciseId,
    };

    if (sortOrder != null) data['sort_order'] = sortOrder;

    await supabase.from('routine_items').insert(data);
  }

  /// ✅ Remove an exercise from a routine (does NOT delete sessions or exercise)
  Future<void> removeExerciseFromRoutine({
    required String routineId,
    required String exerciseId,
  }) async {
    await supabase
        .from('routine_items')
        .delete()
        .eq('routine_id', routineId)
        .eq('exercise_id', exerciseId);
  }

  // -----------------------------
  // DELETE / COUNTS
  // -----------------------------

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

  /// ✅ Safer delete that also removes routine links first (prevents FK conflicts)
  Future<void> deleteExerciseCascadeSafe(String exerciseId) async {
    // If routine_items has an FK to exercises, this prevents conflicts even if no cascade exists.
    await supabase.from('routine_items').delete().eq('exercise_id', exerciseId);

    await deleteExerciseCascade(exerciseId);
  }
}