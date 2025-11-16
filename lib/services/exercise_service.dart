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
}
