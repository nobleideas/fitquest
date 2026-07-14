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

    final rows = await query.order('name');

return (rows as List)
    .where((e) =>
        (e['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase() !=
        'imported')
    .toList();
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


  Future<List<Map<String, dynamic>>> getAcceptedFriends() async {
  final rows = await supabase.rpc('get_accepted_friends');

  if (rows is! List) {
    return [];
  }

  return rows
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

Future<Set<String>> getAssignedFriendIds(String routineId) async {
  final user = supabase.auth.currentUser;
  if (user == null) {
    throw StateError('User must be logged in.');
  }

  final rows = await supabase
      .from('routine_assignments')
      .select('friend_user_id')
      .eq('routine_id', routineId)
      .eq('trainer_user_id', user.id);

  return (rows as List)
      .map((row) => (row as Map)['friend_user_id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toSet();
}

Future<void> replaceRoutineAssignments({
  required String routineId,
  required Set<String> friendUserIds,
}) async {
  final user = supabase.auth.currentUser;
  if (user == null) {
    throw StateError('User must be logged in.');
  }

  final routine = await supabase
      .from('equipment')
      .select('id, user_id, kind')
      .eq('id', routineId)
      .eq('user_id', user.id)
      .eq('kind', 'routine')
      .maybeSingle();

  if (routine == null) {
    throw StateError(
      'Routine not found or you do not own this routine.',
    );
  }

  await supabase
      .from('routine_assignments')
      .delete()
      .eq('routine_id', routineId)
      .eq('trainer_user_id', user.id);

  if (friendUserIds.isEmpty) {
    return;
  }

  final rows = friendUserIds.map((friendUserId) {
    return {
      'routine_id': routineId,
      'trainer_user_id': user.id,
      'friend_user_id': friendUserId,
    };
  }).toList();

  await supabase.from('routine_assignments').insert(rows);
}
}