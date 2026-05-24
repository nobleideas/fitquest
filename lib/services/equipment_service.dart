import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentService {
  final supabase = Supabase.instance.client;

  Future<List<dynamic>> getAllEquipment({String? kind}) async {
    final normalizedKind = kind?.trim().toLowerCase();

    var query = supabase.from('equipment').select();

    if (normalizedKind != null && normalizedKind.isNotEmpty) {
      if (normalizedKind != 'equipment' && normalizedKind != 'routine') {
        throw ArgumentError(
          'Invalid kind filter: $kind. Must be "equipment" or "routine".',
        );
      }
      query = query.eq('kind', normalizedKind);
    }

    return await query.order('name');
  }

  /// ✅ Insert equipment/routine and return the created row (so we can get id)
  /// `kind` should be 'equipment' or 'routine'
  Future<Map<String, dynamic>> insertEquipment(
    String name, {
    String kind = 'equipment',
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'equipment' && normalizedKind != 'routine') {
      throw ArgumentError(
        'Invalid kind: $kind. Must be "equipment" or "routine".',
      );
    }

    final res = await supabase
        .from('equipment')
        .insert({
          'name': name,
          'kind': normalizedKind,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  Future<Map<String, dynamic>?> getEquipmentByQr(String qrValue) async {
    final res = await supabase
        .from('equipment')
        .select()
        .eq('qr_code', qrValue)
        .maybeSingle();

    return res;
  }

  /// ✅ Rename equipment
  Future<void> updateEquipmentName({
    required String equipmentId,
    required String name,
  }) async {
    await supabase.from('equipment').update({'name': name}).eq('id', equipmentId);
  }

  /// ✅ Delete equipment row (only works if no exercises still reference it)
  Future<void> deleteEquipment(String equipmentId) async {
    await supabase.from('equipment').delete().eq('id', equipmentId);
  }

  /// ✅ Count exercises attached to equipment
  Future<int> getExerciseCountForEquipment(String equipmentId) async {
    final res = await supabase
        .from('exercises')
        .select('id')
        .eq('equipment_id', equipmentId);

    return (res as List).length;
  }

  /// ✅ Move ALL exercises from one equipment to another
  Future<void> moveAllExercisesToEquipment({
    required String fromEquipmentId,
    required String toEquipmentId,
  }) async {
    await supabase
        .from('exercises')
        .update({'equipment_id': toEquipmentId})
        .eq('equipment_id', fromEquipmentId);
  }

  // ---------------------------------------------------------------------------
  // "DELETE ANYWAY" SUPPORT (delete sessions -> exercises -> equipment)
  // ---------------------------------------------------------------------------

  /// ✅ Delete ALL sessions for exercises that belong to an equipment
  Future<void> deleteSessionsForEquipment(String equipmentId) async {
    // 1) Get exercise ids for this equipment
    final exRows = await supabase
        .from('exercises')
        .select('id')
        .eq('equipment_id', equipmentId);

    final ids = (exRows as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();

    if (ids.isEmpty) return;

    // 2) Delete sessions referencing those exercises
    // Use PostgREST "in" filter format: ("id1","id2",...)
    final inList = '(${ids.map((id) => '"$id"').join(',')})';

    await supabase
        .from('exercise_sessions')
        .delete()
        .filter('exercise_id', 'in', inList);
  }

  /// ✅ Delete ALL exercises for an equipment
  Future<void> deleteExercisesForEquipment(String equipmentId) async {
    await supabase.from('exercises').delete().eq('equipment_id', equipmentId);
  }

  /// ✅ Cascade delete: sessions -> exercises -> equipment
  /// Use this when user picks "Delete anyway" and wants everything removed.
  Future<void> deleteEquipmentCascade(String equipmentId) async {
    await deleteSessionsForEquipment(equipmentId);
    await deleteExercisesForEquipment(equipmentId);
    await deleteEquipment(equipmentId);
  }
}