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

  // Insert a new exercise
  Future<void> insertExercise({
    required String name,
    required String primaryMuscleGroup,
    required String type, // Push or Pull
    required String equipmentId,
  }) async {
    
    final muscleGroupLower = primaryMuscleGroup.toLowerCase();
    // Insert into Supabase
    final response = await supabase.from('exercises').insert({
      'name': name,
      'primary_muscle_group': muscleGroupLower,
      'type': type,
      'equipment_id': equipmentId,
    });

}
}