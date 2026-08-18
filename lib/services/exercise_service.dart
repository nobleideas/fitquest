import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseVideoData {
  final String? userVideoUrl;
  final String? importedVideoUrl;
  final String? sourceExerciseId;
  final String? userFormNotes;
  final String? importedFormNotes;

  const ExerciseVideoData({
    required this.userVideoUrl,
    required this.importedVideoUrl,
    required this.sourceExerciseId,
    required this.userFormNotes,
    required this.importedFormNotes,
  });

  bool get hasUserVideo =>
      userVideoUrl != null && userVideoUrl!.trim().isNotEmpty;

  bool get hasImportedVideo =>
      importedVideoUrl != null && importedVideoUrl!.trim().isNotEmpty;
}


class ExerciseDayPerformance {
  final DateTime day;
  final double totalVolume;
  final double estimatedOneRepMax;

  const ExerciseDayPerformance({
    required this.day,
    required this.totalVolume,
    required this.estimatedOneRepMax,
  });
}

class ExercisePerformanceData {
  final double? strengthTrendPercent;
  final double? volumeTrendPercent;
  final String strengthTrendLabel;
  final String volumeTrendLabel;
  final String progressSummary;

  const ExercisePerformanceData({
    required this.strengthTrendPercent,
    required this.volumeTrendPercent,
    required this.strengthTrendLabel,
    required this.volumeTrendLabel,
    required this.progressSummary,
  });
}

class ExerciseService {
  final supabase = Supabase.instance.client;

  static const String _formVideoBucket = 'exercise_form_video';



  // -----------------------------
  // PERFORMANCE / PROGRESS
  // -----------------------------

  Future<ExercisePerformanceData> getExercisePerformanceData({
    required String exerciseId,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User must be logged in.');
    }

    final rowsRaw = await supabase
        .from('exercise_sessions')
        .select('id, weight, reps, load_type, metric_type, metric_value, created_at')
        .eq('user_id', user.id)
        .eq('exercise_id', exerciseId)
        .order('created_at', ascending: false)
        .limit(500);

    final rows = (rowsRaw as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final days = _groupPerformanceDays(rows);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final priorDays = days.where((day) => day.day.isBefore(today)).toList();
    final comparisonDays = priorDays.take(6).toList();

    final progress = _calculateProgress(comparisonDays);

    return ExercisePerformanceData(
      strengthTrendPercent: progress.$1,
      volumeTrendPercent: progress.$2,
      strengthTrendLabel: _trendLabel(progress.$1),
      volumeTrendLabel: _trendLabel(progress.$2),
      progressSummary: progress.$3,
    );
  }

  List<ExerciseDayPerformance> _groupPerformanceDays(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <DateTime, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final parsed = DateTime.tryParse((row['created_at'] ?? '').toString());
      if (parsed == null) continue;

      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(day, () => <Map<String, dynamic>>[]).add(row);
    }

    final result = grouped.entries.map((entry) {
      final sets = entry.value
          .where((row) =>
              (row['load_type'] ?? 'weight').toString() == 'weight' &&
              (row['metric_type'] ?? 'reps').toString() == 'reps')
          .map((row) => (
                weight: _performanceDouble(row['weight']),
                reps: row['metric_value'] != null
                    ? _performanceInt(row['metric_value'])
                    : _performanceInt(row['reps']),
              ))
          .where((set) => set.weight > 0 && set.reps > 0)
          .toList();

      final totalVolume = sets.fold<double>(
        0,
        (sum, set) => sum + set.weight * set.reps,
      );

      double estimatedOneRepMax = 0;
      if (sets.isNotEmpty) {
        estimatedOneRepMax = sets
            .map((set) => set.weight * (1 + set.reps / 30.0))
            .reduce((a, b) => a > b ? a : b);
      }

      return ExerciseDayPerformance(
        day: entry.key,
        totalVolume: totalVolume,
        estimatedOneRepMax: estimatedOneRepMax,
      );
    }).toList()
      ..sort((a, b) => b.day.compareTo(a.day));

    return result;
  }

  (double?, double?, String) _calculateProgress(
    List<ExerciseDayPerformance> days,
  ) {
    if (days.length < 2) {
      return (
        null,
        null,
        'Complete this exercise on more days to establish a progress trend.',
      );
    }

    final recent = days.take(3).toList();
    final previous = days.skip(3).take(3).toList();

    double strengthTrend;
    double volumeTrend;

    if (previous.isNotEmpty) {
      strengthTrend = _percentChange(
        _average(previous.map((day) => day.estimatedOneRepMax).toList()),
        _average(recent.map((day) => day.estimatedOneRepMax).toList()),
      );

      volumeTrend = _percentChange(
        _average(previous.map((day) => day.totalVolume).toList()),
        _average(recent.map((day) => day.totalVolume).toList()),
      );
    } else {
      strengthTrend = _percentChange(
        recent.last.estimatedOneRepMax,
        recent.first.estimatedOneRepMax,
      );

      volumeTrend = _percentChange(
        recent.last.totalVolume,
        recent.first.totalVolume,
      );
    }

    String summary;
    if (strengthTrend > 1 && volumeTrend < -1) {
      summary =
          'Strength is improving even though recent volume is lower. Fatigue, exercise order, or heavier working weights can explain that difference.';
    } else if (strengthTrend > 1 && volumeTrend > 1) {
      summary = 'Both strength and rolling volume are improving.';
    } else if (strengthTrend.abs() <= 1 && volumeTrend > 1) {
      summary = 'Strength is steady while work capacity and volume are improving.';
    } else if (strengthTrend.abs() <= 1 && volumeTrend < -1) {
      summary =
          'Strength is holding steady while volume is temporarily lower. This is not automatically regression.';
    } else if (strengthTrend < -1) {
      summary =
          'Recent strength performance is lower. Consider recovery, fatigue, exercise order, and consistency before treating it as regression.';
    } else {
      summary = 'Recent performance is relatively stable.';
    }

    return (strengthTrend, volumeTrend, summary);
  }


  String _trendLabel(double? value) {
    if (value == null) return 'Not enough data';
    if (value > 1) return 'Improving';
    if (value < -1) return 'Lower recently';
    return 'Stable';
  }

  double _average(List<double> values) {
    final valid = values.where((value) => value > 0).toList();
    if (valid.isEmpty) return 0;
    return valid.reduce((a, b) => a + b) / valid.length;
  }

  double _percentChange(double previous, double current) {
    if (previous <= 0) return 0;
    return ((current - previous) / previous) * 100;
  }




  double _performanceDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  int _performanceInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }


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

  Future<void> removeImportedTrainerVideo({
  required String exerciseId,
}) async {
  await supabase
      .from('exercises')
      .update({
        'video_source_exercise_id': null,
      })
      .eq('id', exerciseId);
}

  Future<Map<String, dynamic>> mergeMyDuplicateExercises() async {
  final mergeRaw = await supabase.rpc(
    'merge_my_duplicate_exercises',
  );

  final cleanupRaw = await supabase.rpc(
    'delete_my_empty_containers',
  );

  final mergeResult = mergeRaw is Map
      ? Map<String, dynamic>.from(mergeRaw)
      : <String, dynamic>{};

  final cleanupResult = cleanupRaw is Map
      ? Map<String, dynamic>.from(cleanupRaw)
      : <String, dynamic>{};

  return {
    ...mergeResult,
    ...cleanupResult,
  };
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

    String? userFormNotes = _cleanNullableString(
      passedExercise?['form_notes'],
    );

    // Fetch the current exercise so video + notes stay in sync even if the
    // page was opened with a partial/stale exercise map.
    final row = await supabase
        .from('exercises')
        .select('video_url, video_source_exercise_id, form_notes')
        .eq('id', exerciseId)
        .maybeSingle();

    userVideoUrl ??= _cleanNullableString(row?['video_url']);
    sourceExerciseId ??=
        _cleanNullableString(row?['video_source_exercise_id']);
    userFormNotes ??= _cleanNullableString(row?['form_notes']);

    String? importedVideoUrl;
    String? importedFormNotes;

    if (sourceExerciseId != null) {
      importedVideoUrl = await resolveExerciseVideoUrl(sourceExerciseId);
      importedFormNotes = await resolveExerciseFormNotes(sourceExerciseId);
    }

    return ExerciseVideoData(
      userVideoUrl: userVideoUrl,
      importedVideoUrl: importedVideoUrl,
      sourceExerciseId: sourceExerciseId,
      userFormNotes: userFormNotes,
      importedFormNotes: importedFormNotes,
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

  /// Resolves form notes from the trainer/friend source exercise.
  /// If RLS does not permit reading the source row, this safely returns null.
  Future<String?> resolveExerciseFormNotes(String sourceExerciseId) async {
    try {
      final row = await supabase
          .from('exercises')
          .select('form_notes')
          .eq('id', sourceExerciseId)
          .maybeSingle();

      return _cleanNullableString(row?['form_notes']);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateExerciseFormNotes({
    required String exerciseId,
    required String? formNotes,
  }) async {
    final cleaned = _cleanNullableString(formNotes);

    await supabase
        .from('exercises')
        .update({'form_notes': cleaned})
        .eq('id', exerciseId);
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
