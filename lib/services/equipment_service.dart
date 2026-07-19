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
  /// The many-to-many relationship is stored in equipment_gyms.
  /// Routine container rows remain gym-independent and are not returned here.
  Future<List<dynamic>> getEquipmentForGym(String gymId) async {
    final trimmedGymId = gymId.trim();
    if (trimmedGymId.isEmpty) {
      throw ArgumentError('Gym ID cannot be blank.');
    }

    final rows = await supabase
        .from('equipment_gyms')
        .select('equipment:equipment_id(*)')
        .eq('user_id', _currentUserId)
        .eq('gym_id', trimmedGymId);

    final equipment = <dynamic>[];

    for (final row in rows) {
      final joined = row['equipment'];
      if (joined is! Map) continue;

      final item = Map<String, dynamic>.from(joined);
      if ((item['kind'] ?? 'equipment').toString().toLowerCase() !=
          'equipment') {
        continue;
      }

      equipment.add(item);
    }

    equipment.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );

    return _removeHiddenImportedContainer(equipment);
  }

  /// Returns routine container rows owned by the current user.
  ///
  /// Routines are intentionally independent from the active gym.
  Future<List<dynamic>> getRoutines() async {
    return getAllEquipment(kind: 'routine');
  }

  /// Returns regular equipment that has no equipment_gyms assignment.
  Future<List<dynamic>> getUnassignedEquipment() async {
    final equipmentRows = await supabase
        .from('equipment')
        .select()
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .order('name');

    final assignmentRows = await supabase
        .from('equipment_gyms')
        .select('equipment_id')
        .eq('user_id', _currentUserId);

    final assignedIds = assignmentRows
        .map<String>((row) => row['equipment_id'].toString())
        .toSet();

    final rows = equipmentRows
        .where((row) => !assignedIds.contains(row['id'].toString()))
        .toList();

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
  /// Routine rows remain gym-independent. During the migration period,
  /// equipment.gym_id is also populated as a compatibility fallback.
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
    final trimmedGymId = gymId?.trim() ?? '';

    if (normalizedKind == 'equipment' && trimmedGymId.isEmpty) {
      throw StateError('A gym must be selected before creating equipment.');
    }

    final values = <String, dynamic>{
      'name': trimmedName,
      'kind': normalizedKind,
      'user_id': _currentUserId,
    };

    if (normalizedKind == 'equipment') {
      values['gym_id'] = trimmedGymId;
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

    final equipment = Map<String, dynamic>.from(res);

    if (normalizedKind == 'equipment') {
      await supabase.from('equipment_gyms').upsert(
        {
          'equipment_id': equipment['id'],
          'gym_id': trimmedGymId,
          'user_id': _currentUserId,
        },
        onConflict: 'equipment_id,gym_id',
      );
    }

    return equipment;
  }

  /// Adds one equipment row to a gym without removing other assignments.
  Future<void> assignEquipmentToGym({
    required String equipmentId,
    required String gymId,
  }) async {
    await bulkAssignEquipmentToGym(
      equipmentIds: {equipmentId},
      gymId: gymId,
    );
  }

  /// Adds multiple regular equipment rows to a gym.
  Future<void> bulkAssignEquipmentToGym({
    required Set<String> equipmentIds,
    required String gymId,
  }) async {
    final ids = equipmentIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final trimmedGymId = gymId.trim();

    if (ids.isEmpty) {
      throw ArgumentError('Select at least one equipment item.');
    }

    if (trimmedGymId.isEmpty) {
      throw ArgumentError('Gym ID cannot be blank.');
    }

    final ownedRows = await supabase
        .from('equipment')
        .select('id')
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .inFilter('id', ids.toList());

    final ownedIds = ownedRows
        .map<String>((row) => row['id'].toString())
        .toSet();

    if (ownedIds.length != ids.length) {
      throw StateError('One or more selected equipment items are invalid.');
    }

    await supabase.from('equipment_gyms').upsert(
      ownedIds
          .map(
            (equipmentId) => {
              'equipment_id': equipmentId,
              'gym_id': trimmedGymId,
              'user_id': _currentUserId,
            },
          )
          .toList(),
      onConflict: 'equipment_id,gym_id',
    );

    // Temporary compatibility fallback for older code paths.
    await supabase
        .from('equipment')
        .update({'gym_id': trimmedGymId})
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .inFilter('id', ownedIds.toList())
        .isFilter('gym_id', null);
  }

  /// Removes one equipment assignment from one gym.
  Future<void> removeEquipmentFromGym({
    required String equipmentId,
    required String gymId,
  }) async {
    final trimmedEquipmentId = equipmentId.trim();
    final trimmedGymId = gymId.trim();

    if (trimmedEquipmentId.isEmpty || trimmedGymId.isEmpty) {
      throw ArgumentError('Equipment ID and gym ID are required.');
    }

    await supabase
        .from('equipment_gyms')
        .delete()
        .eq('user_id', _currentUserId)
        .eq('equipment_id', trimmedEquipmentId)
        .eq('gym_id', trimmedGymId);
  }

  /// Returns every gym ID where this equipment is available.
  Future<Set<String>> getGymIdsForEquipment(String equipmentId) async {
    final trimmedEquipmentId = equipmentId.trim();
    if (trimmedEquipmentId.isEmpty) {
      throw ArgumentError('Equipment ID cannot be blank.');
    }

    final rows = await supabase
        .from('equipment_gyms')
        .select('gym_id')
        .eq('user_id', _currentUserId)
        .eq('equipment_id', trimmedEquipmentId);

    return rows
        .map<String>((row) => row['gym_id'].toString())
        .toSet();
  }

  /// Replaces all gym assignments for one equipment row.
  ///
  /// At least one gym is required.
  Future<void> setGymsForEquipment({
    required String equipmentId,
    required Set<String> gymIds,
  }) async {
    final trimmedEquipmentId = equipmentId.trim();
    final cleanedGymIds = gymIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (trimmedEquipmentId.isEmpty) {
      throw ArgumentError('Equipment ID cannot be blank.');
    }

    if (cleanedGymIds.isEmpty) {
      throw StateError('Equipment must be available at at least one gym.');
    }

    final equipment = await supabase
        .from('equipment')
        .select('id')
        .eq('id', trimmedEquipmentId)
        .eq('user_id', _currentUserId)
        .eq('kind', 'equipment')
        .maybeSingle();

    if (equipment == null) {
      throw StateError('Equipment not found or not owned by the current user.');
    }

    final currentGymIds = await getGymIdsForEquipment(trimmedEquipmentId);
    final toAdd = cleanedGymIds.difference(currentGymIds);
    final toRemove = currentGymIds.difference(cleanedGymIds);

    if (toAdd.isNotEmpty) {
      await supabase.from('equipment_gyms').upsert(
        toAdd
            .map(
              (gymId) => {
                'equipment_id': trimmedEquipmentId,
                'gym_id': gymId,
                'user_id': _currentUserId,
              },
            )
            .toList(),
        onConflict: 'equipment_id,gym_id',
      );
    }

    if (toRemove.isNotEmpty) {
      await supabase
          .from('equipment_gyms')
          .delete()
          .eq('user_id', _currentUserId)
          .eq('equipment_id', trimmedEquipmentId)
          .inFilter('gym_id', toRemove.toList());
    }

    // Temporary compatibility fallback for code that still reads equipment.gym_id.
    await supabase
        .from('equipment')
        .update({'gym_id': cleanedGymIds.first})
        .eq('id', trimmedEquipmentId)
        .eq('user_id', _currentUserId);
  }

  /// Removes all gym assignments from multiple equipment rows.
  ///
  /// Retained for migration/administrative flows only.
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
        .from('equipment_gyms')
        .delete()
        .eq('user_id', _currentUserId)
        .inFilter('equipment_id', ids);

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
