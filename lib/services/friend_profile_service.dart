import 'package:supabase_flutter/supabase_flutter.dart';

import 'equipment_service.dart';

class FriendProfileData {
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> containers;
  final List<Map<String, dynamic>> exercises;

  const FriendProfileData({
    required this.history,
    required this.containers,
    required this.exercises,
  });
}

class FriendImportResult {
  final int addedContainers;
  final int skippedContainers;
  final int addedExercises;
  final int skippedExercises;
  final int addedRoutineLinks;

  const FriendImportResult({
    this.addedContainers = 0,
    this.skippedContainers = 0,
    this.addedExercises = 0,
    this.skippedExercises = 0,
    this.addedRoutineLinks = 0,
  });

  int get totalSkipped => skippedContainers + skippedExercises;
}

class FriendProfileService {
  static const String importedEquipmentName = 'Imported';

  final SupabaseClient supabase;
  final EquipmentService equipmentService;

  FriendProfileService({
    SupabaseClient? supabase,
    EquipmentService? equipmentService,
  })  : supabase = supabase ?? Supabase.instance.client,
        equipmentService = equipmentService ?? EquipmentService();

  String normalizeContainerName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<Map<String, dynamic>?> findExistingContainer({
    required String name,
    required String kind,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final normalizedName = normalizeContainerName(name);
    final normalizedKind = kind.trim().toLowerCase();

    if (normalizedName.isEmpty) return null;

    final rows = await supabase
        .from('equipment')
        .select('id, name, kind, user_id')
        .eq('user_id', user.id)
        .eq('kind', normalizedKind);

    for (final row in rows) {
      final container = Map<String, dynamic>.from(row as Map);
      final rowName = normalizeContainerName(
        (container['name'] ?? '').toString(),
      );

      if (rowName == normalizedName) {
        return container;
      }
    }

    return null;
  }

  Future<FriendProfileData> loadFriendProfile(String friendUserId) async {
    final results = await Future.wait<dynamic>([
      supabase.rpc(
        'get_friend_workout_history',
        params: {'friend_user_id': friendUserId, 'max_rows': 250},
      ),
      supabase.rpc(
        'get_friend_equipment',
        params: {'friend_user_id': friendUserId},
      ),
      supabase.rpc(
        'get_friend_exercises',
        params: {'friend_user_id': friendUserId},
      ),
    ]);

    return FriendProfileData(
      history: _mapList(results[0]),
      containers: _mapList(results[1]),
      exercises: _mapList(results[2]),
    );
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getMyContainers({
    required String kind,
  }) async {
    final rows = await equipmentService.getAllEquipment();

    final result = rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where(
          (row) =>
              (row['kind'] ?? 'equipment')
                  .toString()
                  .trim()
                  .toLowerCase() ==
              kind.trim().toLowerCase(),
        )
        .toList();

    result.sort((a, b) {
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return result;
  }

  Future<Map<String, dynamic>> createContainer({
    required String name,
    required String kind,
  }) async {
    final existing = await findExistingContainer(
      name: name,
      kind: kind,
    );

    if (existing != null) {
      return existing;
    }

    final created = await equipmentService.insertEquipment(
      name,
      kind: kind,
    );

    return Map<String, dynamic>.from(created);
  }

  Future<Map<String, dynamic>> ensureImportedEquipment() async {
    final containers = await getMyContainers(kind: 'equipment');

    for (final container in containers) {
      final name = (container['name'] ?? '').toString().trim().toLowerCase();
      if (name == importedEquipmentName.toLowerCase()) {
        return container;
      }
    }

    return createContainer(
      name: importedEquipmentName,
      kind: 'equipment',
    );
  }

  String? exerciseVideoUrl(Map<String, dynamic> exercise) {
    final value = (exercise['video_url'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<Map<String, dynamic>?> findExistingExerciseByName({
    required String name,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final normalizedName = name.trim().toLowerCase();
    if (normalizedName.isEmpty) return null;

    final rows = await supabase
        .from('exercises')
        .select(
          'id, name, video_url, video_source_exercise_id, equipment_id',
        )
        .eq('user_id', user.id);

    for (final row in rows) {
      final exercise = Map<String, dynamic>.from(row as Map);
      final rowName = (exercise['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (rowName == normalizedName) {
        return exercise;
      }
    }

    return null;
  }

  Future<String?> insertExerciseIntoEquipment({
    required String equipmentId,
    required Map<String, dynamic> friendExercise,
  }) async {
    final name = (friendExercise['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final sourceExerciseId =
        (friendExercise['id'] ?? '').toString().trim();
    final sourceVideoUrl = exerciseVideoUrl(friendExercise);

    final existingExercise = await findExistingExerciseByName(
      name: name,
    );

    if (existingExercise != null) {
      final existingId = (existingExercise['id'] ?? '').toString().trim();
      if (existingId.isEmpty) return null;

      final existingSourceId = (existingExercise['video_source_exercise_id'] ?? '')
          .toString()
          .trim();

      // If the existing exercise does not yet have an imported trainer video
      // reference, preserve the source from this import.
      if (existingSourceId.isEmpty &&
          sourceVideoUrl != null &&
          sourceExerciseId.isNotEmpty) {
        await supabase
            .from('exercises')
            .update({
              'video_source_exercise_id': sourceExerciseId,
            })
            .eq('id', existingId);
      }

      return existingId;
    }

    final inserted = await supabase
        .from('exercises')
        .insert({
          'name': name,
          'primary_muscle_group':
              (friendExercise['primary_muscle_group'] ?? '').toString(),
          'type': (friendExercise['type'] ?? '').toString(),
          'equipment_id': equipmentId,

          // The importing user's own upload remains independent.
          'video_url': null,

          // Preserve the trainer/friend demonstration by reference.
          'video_source_exercise_id':
              sourceVideoUrl != null && sourceExerciseId.isNotEmpty
                  ? sourceExerciseId
                  : null,
        })
        .select('id')
        .single();

    final id = (inserted['id'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<bool> linkExerciseToRoutine({
    required String routineId,
    required String exerciseId,
  }) async {
    try {
      await supabase.from('routine_items').insert({
        'routine_id': routineId,
        'exercise_id': exerciseId,
      });
      return true;
    } catch (_) {
      // A duplicate routine link is treated as already linked.
      return false;
    }
  }

  Future<FriendImportResult> importContainers({
    required List<Map<String, dynamic>> friendContainers,
    required List<Map<String, dynamic>> friendExercises,
    required String insertKind,
    required bool includeExercises,
  }) async {
    var addedContainers = 0;
    var skippedContainers = 0;
    var addedExercises = 0;
    var skippedExercises = 0;
    var addedRoutineLinks = 0;

    Map<String, dynamic>? importedEquipment;

    for (final friendContainer in friendContainers) {
      final name = (friendContainer['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        skippedContainers++;
        continue;
      }

      Map<String, dynamic>? createdContainer;

      try {
        final existingContainer = await findExistingContainer(
          name: name,
          kind: insertKind,
        );

        if (existingContainer != null) {
          createdContainer = existingContainer;
          skippedContainers++;
        } else {
          createdContainer = await createContainer(
            name: name,
            kind: insertKind,
          );
          addedContainers++;
        }
      } catch (_) {
        skippedContainers++;
      }

      if (!includeExercises || createdContainer == null) continue;

      final friendContainerId =
          (friendContainer['id'] ?? '').toString().trim();
      final myContainerId =
          (createdContainer['id'] ?? '').toString().trim();

      if (friendContainerId.isEmpty || myContainerId.isEmpty) continue;

      final matchingExercises = friendExercises.where((exercise) {
        return (exercise['equipment_id'] ?? '').toString().trim() ==
            friendContainerId;
      });

      if (insertKind == 'routine') {
        importedEquipment ??= await ensureImportedEquipment();
      }

      for (final friendExercise in matchingExercises) {
        try {
          final targetEquipmentId = insertKind == 'routine'
              ? (importedEquipment!['id'] ?? '').toString().trim()
              : myContainerId;

          if (targetEquipmentId.isEmpty) {
            skippedExercises++;
            continue;
          }

          final exerciseId = await insertExerciseIntoEquipment(
            equipmentId: targetEquipmentId,
            friendExercise: friendExercise,
          );

          if (exerciseId == null) {
            skippedExercises++;
            continue;
          }

          addedExercises++;

          if (insertKind == 'routine') {
            final linked = await linkExerciseToRoutine(
              routineId: myContainerId,
              exerciseId: exerciseId,
            );
            if (linked) addedRoutineLinks++;
          }
        } catch (_) {
          skippedExercises++;
        }
      }
    }

    return FriendImportResult(
      addedContainers: addedContainers,
      skippedContainers: skippedContainers,
      addedExercises: addedExercises,
      skippedExercises: skippedExercises,
      addedRoutineLinks: addedRoutineLinks,
    );
  }

  Future<FriendImportResult> importExercisesToEquipment({
    required List<Map<String, dynamic>> friendExercises,
    required String equipmentId,
  }) async {
    var added = 0;
    var skipped = 0;

    for (final exercise in friendExercises) {
      try {
        final id = await insertExerciseIntoEquipment(
          equipmentId: equipmentId,
          friendExercise: exercise,
        );
        id == null ? skipped++ : added++;
      } catch (_) {
        skipped++;
      }
    }

    return FriendImportResult(
      addedExercises: added,
      skippedExercises: skipped,
    );
  }

  Future<FriendImportResult> importExercisesToRoutine({
    required List<Map<String, dynamic>> friendExercises,
    required String homeEquipmentId,
    required String routineId,
  }) async {
    var imported = 0;
    var skipped = 0;
    var linked = 0;

    for (final exercise in friendExercises) {
      try {
        final exerciseId = await insertExerciseIntoEquipment(
          equipmentId: homeEquipmentId,
          friendExercise: exercise,
        );

        if (exerciseId == null) {
          skipped++;
          continue;
        }

        imported++;

        final didLink = await linkExerciseToRoutine(
          routineId: routineId,
          exerciseId: exerciseId,
        );
        if (didLink) linked++;
      } catch (_) {
        skipped++;
      }
    }

    return FriendImportResult(
      addedExercises: imported,
      skippedExercises: skipped,
      addedRoutineLinks: linked,
    );
  }
}
