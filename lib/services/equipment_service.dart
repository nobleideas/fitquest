import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentService {
  final SupabaseClient supabase = Supabase.instance.client;

  String get _currentUserId {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User must be logged in.');
    }
    return user.id;
  }

  String _normalizeKind(String kind) {
    final normalizedKind = kind.trim().toLowerCase();

    if (normalizedKind != 'equipment' && normalizedKind != 'routine') {
      throw ArgumentError(
        'Invalid kind: $kind. Must be "equipment" or "routine".',
      );
    }

    return normalizedKind;
  }

  List<dynamic> _removeHiddenImportedContainer(List<dynamic> rows) {
    return rows
        .where(
          (e) =>
              (e['name'] ?? '').toString().trim().toLowerCase() != 'imported',
        )
        .toList();
  }

  /// Returns every equipment and routine row owned by the current user.
  ///
  /// This remains available for management flows that must work across gyms.
  Future<List<dynamic>> getAllEquipment({String? kind}) async {
    final normalizedKind = kind == null || kind.trim().isEmpty
        ? null
        : _normalizeKind(kind);

    var query = supabase
        .from('equipment')
        .select()
        .eq('user_id', _currentUserId);

    if (normalizedKind != null) {
      query = query.eq('kind', normalizedKind);
    }

    final rows = await query.order('name');

    return _removeHiddenImportedContainer(List<dynamic>.from(rows));
  }

  /// Returns regular equipment assigned to a specific gym.
  ///
  /// Routine container rows remain gym-independent and are not returned here.
  Future<List<dynamic>> getEquipmentForGym(String gymId) async {
    final trimmedGymId = gymId.trim();
    if (trimmedGymId.isEmpty) {
      throw ArgumentError('Gym ID cannot be blank.');
    }

    final rows = await supabase
        .from('equipment')
        .select()
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .eq('gym_id', trimmedGymId)
        .order('name');

    return _removeHiddenImportedContainer(List<dynamic>.from(rows));
  }

  /// Returns routine container rows owned by the current user.
  ///
  /// Routines are intentionally independent from the active gym.
  Future<List<dynamic>> getRoutines() async {
    return getAllEquipment(kind: 'routine');
  }

  /// Returns unassigned regular equipment for migration and management.
  Future<List<dynamic>> getUnassignedEquipment() async {
    final rows = await supabase
        .from('equipment')
        .select()
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .isFilter('gym_id', null)
        .order('name');

    return _removeHiddenImportedContainer(List<dynamic>.from(rows));
  }

  /// Returns the equipment page rows for the selected gym.
  ///
  /// Regular equipment is filtered by gym, while routines remain visible
  /// because routines are not tied to a gym.
  Future<List<dynamic>> getEquipmentPageItems({required String gymId}) async {
    final results = await Future.wait<List<dynamic>>([
      getEquipmentForGym(gymId),
      getRoutines(),
    ]);

    final combined = <dynamic>[...results[0], ...results[1]];

    combined.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );

    return combined;
  }

  /// Creates equipment in the supplied gym.
  ///
  /// Routine rows do not receive a gym_id.
  Future<Map<String, dynamic>> insertEquipment(
    String name, {
    String kind = 'equipment',
    String? gymId,
    String? sourceRoutineId,
    String? sourceTrainerUserId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Name cannot be blank.');
    }

    final normalizedKind = _normalizeKind(kind);

    if (normalizedKind == 'equipment') {
      final trimmedGymId = gymId?.trim() ?? '';
      if (trimmedGymId.isEmpty) {
        throw StateError('A gym must be selected before creating equipment.');
      }
    }

    final values = <String, dynamic>{
      'name': trimmedName,
      'kind': normalizedKind,
      'user_id': _currentUserId,
    };

    if (normalizedKind == 'equipment') {
      values['gym_id'] = gymId!.trim();
    } else {
      values['gym_id'] = null;
      values['source_routine_id'] = sourceRoutineId;
      values['source_trainer_user_id'] = sourceTrainerUserId;
    }

    final res = await supabase
        .from('equipment')
        .insert(values)
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  /// Moves one equipment row to a gym owned by the current user.
  Future<void> assignEquipmentToGym({
    required String equipmentId,
    required String gymId,
  }) async {
    await bulkAssignEquipmentToGym(equipmentIds: {equipmentId}, gymId: gymId);
  }

  /// Moves multiple regular equipment rows to a gym in one update.
  ///
  /// RLS verifies that the destination gym belongs to the current user.
  Future<void> bulkAssignEquipmentToGym({
    required Set<String> equipmentIds,
    required String gymId,
  }) async {
    final ids = equipmentIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    final trimmedGymId = gymId.trim();

    if (ids.isEmpty) {
      throw ArgumentError('Select at least one equipment item.');
    }

    if (trimmedGymId.isEmpty) {
      throw ArgumentError('Gym ID cannot be blank.');
    }

    await supabase
        .from('equipment')
        .update({'gym_id': trimmedGymId})
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .inFilter('id', ids);
  }

  /// Removes gym assignment from multiple regular equipment rows.
  Future<void> bulkUnassignEquipment({
    required Set<String> equipmentIds,
  }) async {
    final ids = equipmentIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    if (ids.isEmpty) {
      throw ArgumentError('Select at least one equipment item.');
    }

    await supabase
        .from('equipment')
        .update({'gym_id': null})
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .inFilter('id', ids);
  }

  Future<Map<String, dynamic>?> getEquipmentByQr(String qrValue) async {
    final res = await supabase
        .from('equipment')
        .select()
        .eq('qr_code', qrValue)
        .maybeSingle();

    return res;
  }

  Future<void> updateEquipmentName({
    required String equipmentId,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Name cannot be blank.');
    }

    await supabase
        .from('equipment')
        .update({'name': trimmedName})
        .eq('id', equipmentId)
        .eq('user_id', _currentUserId);
  }

  Future<void> deleteEquipment(String equipmentId) async {
    await supabase
        .from('equipment')
        .delete()
        .eq('id', equipmentId)
        .eq('user_id', _currentUserId);
  }

  Future<int> getExerciseCountForEquipment(String equipmentId) async {
    final res = await supabase
        .from('exercises')
        .select('id')
        .eq('equipment_id', equipmentId);

    return (res as List).length;
  }

  Future<void> moveAllExercisesToEquipment({
    required String fromEquipmentId,
    required String toEquipmentId,
  }) async {
    await supabase
        .from('exercises')
        .update({'equipment_id': toEquipmentId})
        .eq('equipment_id', fromEquipmentId);
  }

  Future<void> deleteSessionsForEquipment(String equipmentId) async {
    final exRows = await supabase
        .from('exercises')
        .select('id')
        .eq('equipment_id', equipmentId);

    final ids = (exRows as List)
        .map((e) => (e as Map)['id'].toString())
        .toList();

    if (ids.isEmpty) return;

    final inList = '(${ids.map((id) => '"$id"').join(',')})';

    await supabase
        .from('exercise_sessions')
        .delete()
        .filter('exercise_id', 'in', inList);
  }

  Future<void> deleteExercisesForEquipment(String equipmentId) async {
    await supabase.from('exercises').delete().eq('equipment_id', equipmentId);
  }

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
        .select('id, user_id, kind, source_routine_id, source_trainer_user_id')
        .eq('id', routineId)
        .eq('user_id', user.id)
        .eq('kind', 'routine')
        .maybeSingle();

    if (routine == null) {
      throw StateError('Routine not found or you do not own this routine.');
    }

    final sourceRoutineId = (routine['source_routine_id'] ?? '')
        .toString()
        .trim();
    final sourceTrainerUserId = (routine['source_trainer_user_id'] ?? '')
        .toString()
        .trim();

    if (sourceRoutineId.isNotEmpty || sourceTrainerUserId.isNotEmpty) {
      throw StateError('Imported routines cannot be assigned.');
    }

    await supabase
        .from('routine_assignments')
        .delete()
        .eq('routine_id', routineId)
        .eq('trainer_user_id', user.id);

    if (friendUserIds.isEmpty) {
      return;
    }

    final rows = friendUserIds
        .map(
          (friendUserId) => {
            'routine_id': routineId,
            'trainer_user_id': user.id,
            'friend_user_id': friendUserId,
          },
        )
        .toList();

    await supabase.from('routine_assignments').insert(rows);
  }
}
