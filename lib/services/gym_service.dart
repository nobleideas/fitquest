import 'package:supabase_flutter/supabase_flutter.dart';

class GymService {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getUserGyms() async {
    final res = await supabase
        .from('gyms')
        .select()
        .eq('user_id', supabase.auth.currentUser!.id);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> createGym(String name) async {
    await supabase.from('gyms').insert({
      'user_id': supabase.auth.currentUser!.id,
      'name': name,
    });
  }

  Future<List<Map<String, dynamic>>> getGymEquipment(String gymId) async {
    final res = await supabase
        .from('gym_equipment')
        .select()
        .eq('gym_id', gymId);
    return List<Map<String, dynamic>>.from(res);
  }

  // Add an existing equipment to a gym
  Future<void> addEquipmentToGym({
    required String gymId,
    required String equipmentId,
  }) async {
    await supabase.from('gym_equipment').insert({
      'gym_id': gymId,
      'original_equipment_id': equipmentId,
    });
  }
}
