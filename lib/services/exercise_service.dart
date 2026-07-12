import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseVideoData {
  final String? userVideoUrl;
  final String? importedVideoUrl;
  final String? sourceExerciseId;

  const ExerciseVideoData({
    required this.userVideoUrl,
    required this.importedVideoUrl,
    required this.sourceExerciseId,
  });

  bool get hasUserVideo =>
      userVideoUrl != null && userVideoUrl!.trim().isNotEmpty;

  bool get hasImportedVideo =>
      importedVideoUrl != null && importedVideoUrl!.trim().isNotEmpty;
}

class ExerciseService {
  final supabase = Supabase.instance.client;

  static const String _formVideoBucket = 'exercise_form_video';

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

  Future<Map<String, dynamic>> mergeMyDuplicateExercises() async {
  final result = await supabase.rpc(
    'merge_my_duplicate_exercises',
  );

  if (result is Map<String, dynamic>) {
    return result;
  }

  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }

  return <String, dynamic>{};
}

  /// Load exercises included in a routine via routine_items.
  Future<List<Map<String, dynamic>>> getExercisesForRoutine(
    String routineId,
  ) async {
    final rows = await supabase
        .from('routine_items')
        .select('exercise:exercises(*)')
        .eq('routine_id', routineId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    final list = <Map<String, dynamic>>[];

    if (rows is List) {
      for (final row in rows) {
        if (row is Map && row['exercise'] is Map) {
          list.add(
            Map<String, dynamic>.from(row['exercise'] as Map),
          );
        }
      }
    }

    return list;
  }

  // -----------------------------
  // EXERCISE VIDEOS
  // -----------------------------

  /// Loads both videos independently:
  /// - userVideoUrl: this user's own uploaded form video
  /// - importedVideoUrl: the trainer/friend source video
  Future<ExerciseVideoData> getExerciseVideos({
    required String exerciseId,
    Map<String, dynamic>? passedExercise,
  }) async {
    String? userVideoUrl = _cleanNullableString(
      passedExercise?['video_url'],
    );

    String? sourceExerciseId = _cleanNullableString(
      passedExercise?['video_source_exercise_id'],
    );

    // Always fetch when either field was not supplied by the page.
    if (userVideoUrl == null || sourceExerciseId == null) {
      final row = await supabase
          .from('exercises')
          .select('video_url, video_source_exercise_id')
          .eq('id', exerciseId)
          .maybeSingle();

      userVideoUrl ??= _cleanNullableString(row?['video_url']);
      sourceExerciseId ??=
          _cleanNullableString(row?['video_source_exercise_id']);
    }

    String? importedVideoUrl;

    if (sourceExerciseId != null) {
      importedVideoUrl = await resolveExerciseVideoUrl(
        sourceExerciseId,
      );
    }

    return ExerciseVideoData(
      userVideoUrl: userVideoUrl,
      importedVideoUrl: importedVideoUrl,
      sourceExerciseId: sourceExerciseId,
    );
  }

  /// Resolves a friend's/trainer's video URL through the existing RPC.
  Future<String?> resolveExerciseVideoUrl(
    String sourceExerciseId,
  ) async {
    try {
      final result = await supabase.rpc(
        'get_exercise_video_url',
        params: {'p_exercise_id': sourceExerciseId},
      );

      if (result == null) return null;

      if (result is String) {
        return _cleanNullableString(result);
      }

      if (result is List && result.isNotEmpty) {
        final first = result.first;

        if (first is Map && first.isNotEmpty) {
          return _cleanNullableString(first.values.first);
        }

        return _cleanNullableString(first);
      }

      if (result is Map) {
        if (result.values.isEmpty) return null;
        return _cleanNullableString(result.values.first);
      }

      return _cleanNullableString(result);
    } catch (_) {
      return null;
    }
  }

  /// Uploads only the user's personal form video.
  ///
  /// This intentionally preserves video_source_exercise_id so the imported
  /// trainer video remains available beside the user's own video.
  Future<String> uploadUserFormVideo({
    required String exerciseId,
    required XFile video,
  }) async {
    final bucket = supabase.storage.from(_formVideoBucket);

    final extension = p.extension(video.name).isNotEmpty
        ? p.extension(video.name)
        : '.mp4';

    final storagePath = 'exercise_$exerciseId/form$extension';
    final bytes = await video.readAsBytes();

    await bucket.uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: video.mimeType ?? 'video/mp4',
      ),
    );

    final publicUrl = bucket.getPublicUrl(storagePath);

    await supabase
        .from('exercises')
        .update({'video_url': publicUrl})
        .eq('id', exerciseId);

    return publicUrl;
  }

  /// Removes only the user's personal video.
  ///
  /// The imported trainer/source reference remains untouched.
  Future<void> removeUserFormVideo({
    required String exerciseId,
    required String? userVideoUrl,
  }) async {
    final url = (userVideoUrl ?? '').trim();

    await supabase
        .from('exercises')
        .update({'video_url': null})
        .eq('id', exerciseId);

    if (url.isEmpty) return;

    final storagePath = _tryExtractStoragePathFromPublicUrl(
      url,
      _formVideoBucket,
    );

    if (storagePath == null) return;

    try {
      await supabase.storage
          .from(_formVideoBucket)
          .remove([storagePath]);
    } catch (_) {
      // The database update succeeded. A missing storage object should not
      // prevent the user video from being removed from the exercise.
    }
  }

  String? _cleanNullableString(dynamic value) {
    final cleaned = (value ?? '').toString().trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _tryExtractStoragePathFromPublicUrl(
    String url,
    String bucketId,
  ) {
    try {
      final marker = '/storage/v1/object/public/$bucketId/';
      final markerIndex = url.indexOf(marker);

      if (markerIndex == -1) return null;

      final path = url.substring(markerIndex + marker.length);
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
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
    await supabase
        .from('exercises')
        .update({'name': name})
        .eq('id', exerciseId);
  }

  Future<void> updateExerciseType({
    required String exerciseId,
    required String type,
  }) async {
    await supabase
        .from('exercises')
        .update({'type': type})
        .eq('id', exerciseId);
  }

  /// Move an exercise to another equipment.
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

  /// Add a canonical exercise to a routine without duplication.
  Future<void> addExerciseToRoutine({
    required String routineId,
    required String exerciseId,
    int? sortOrder,
  }) async {
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

    if (sortOrder != null) {
      data['sort_order'] = sortOrder;
    }

    await supabase.from('routine_items').insert(data);
  }

  /// Remove an exercise from a routine without deleting its sessions.
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
    await supabase
        .from('exercises')
        .delete()
        .eq('id', exerciseId);
  }

  Future<int> getSessionCountForExercise(
    String exerciseId,
  ) async {
    final res = await supabase
        .from('exercise_sessions')
        .select('id')
        .eq('exercise_id', exerciseId);

    return (res as List).length;
  }

  Future<void> deleteSessionsForExercise(
    String exerciseId,
  ) async {
    await supabase
        .from('exercise_sessions')
        .delete()
        .eq('exercise_id', exerciseId);
  }

  Future<void> deleteExerciseCascade(
    String exerciseId,
  ) async {
    await deleteSessionsForExercise(exerciseId);
    await deleteExercise(exerciseId);
  }

  /// Removes routine links before deleting the exercise.
  Future<void> deleteExerciseCascadeSafe(
    String exerciseId,
  ) async {
    await supabase
        .from('routine_items')
        .delete()
        .eq('exercise_id', exerciseId);

    await deleteExerciseCascade(exerciseId);
  }
}
