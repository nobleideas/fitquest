import 'package:supabase_flutter/supabase_flutter.dart';
import 'workout_date_service.dart';

class SessionService {
  final supabase = Supabase.instance.client;
  final WorkoutDateService _workoutDateService = WorkoutDateService.instance;

  Future<Map<String, dynamic>> insertSession({
    required String exerciseId,
    required double weight,
    required double metricValue,
    required String metricType,
    required String loadType,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    _validateMetric(metricType, metricValue);
    _validateLoadType(loadType);

    // Capture the selected date once so a UI change during the request cannot
    // change the date used for this insertion.
    final selectedBacklogDate = _workoutDateService.selectedDate.value;

    final values = <String, dynamic>{
      'user_id': user.id,
      'exercise_id': exerciseId,
      'weight': weight,
      'load_type': loadType,
      // Keep reps populated for backwards compatibility with older code.
      // Non-rep metrics intentionally store 0 reps.
      'reps': metricType == 'reps' ? metricValue.toInt() : 0,
      'metric_type': metricType,
      'metric_value': metricValue,
    };

    if (selectedBacklogDate != null) {
      final date = DateTime(
        selectedBacklogDate.year,
        selectedBacklogDate.month,
        selectedBacklogDate.day,
      );
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      if (!date.isBefore(todayStart)) {
        throw StateError('Backlog date must be before today.');
      }

      // Noon local time avoids most DST edge cases and ensures the session
      // appears on the selected local calendar date. Existing rows are untouched.
      final historicalLocal = DateTime(date.year, date.month, date.day, 12);
      values['created_at'] = historicalLocal.toUtc().toIso8601String();
    }

    final res = await supabase
        .from('exercise_sessions')
        .insert(values)
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  Future<void> updateSession({
    required String sessionId,
    required double weight,
    required double metricValue,
    required String metricType,
    required String loadType,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    _validateMetric(metricType, metricValue);
    _validateLoadType(loadType);

    // Do not change created_at when editing an existing session.
    await supabase
        .from('exercise_sessions')
        .update({
          'weight': weight,
          'load_type': loadType,
          'reps': metricType == 'reps' ? metricValue.toInt() : 0,
          'metric_type': metricType,
          'metric_value': metricValue,
        })
        .eq('id', sessionId)
        .eq('user_id', user.id);
  }

  void _validateMetric(String metricType, double metricValue) {
    const allowed = {'reps', 'seconds', 'minutes', 'miles'};
    if (!allowed.contains(metricType)) {
      throw ArgumentError('Unsupported metric type: $metricType');
    }
    if (!metricValue.isFinite || metricValue < 0) {
      throw ArgumentError('Metric value must be finite and nonnegative.');
    }
    if (metricType == 'reps' && metricValue != metricValue.roundToDouble()) {
      throw ArgumentError('Reps must be a whole number.');
    }
  }

  void _validateLoadType(String loadType) {
    const allowed = {'weight', 'level'};
    if (!allowed.contains(loadType)) {
      throw ArgumentError('Unsupported load type: $loadType');
    }
  }

  Future<List<DateTime>> getLast3SessionDates(String exerciseId) async {
    final user = supabase.auth.currentUser!;
    final res = await supabase
        .from('exercise_sessions')
        .select('created_at')
        .eq('exercise_id', exerciseId)
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1000);

    final seenDayKeys = <String>{};
    final days = <DateTime>[];
    for (final row in res) {
      final createdLocal = DateTime.parse(row['created_at']).toLocal();
      final dayLocal = DateTime(
        createdLocal.year,
        createdLocal.month,
        createdLocal.day,
      );
      final key = '${dayLocal.year}-${dayLocal.month}-${dayLocal.day}';
      if (seenDayKeys.add(key)) {
        days.add(dayLocal);
        if (days.length == 3) break;
      }
    }
    return days;
  }

  Future<List<Map<String, dynamic>>> getSessionsForDate(
    String exerciseId,
    DateTime dayLocal,
  ) async {
    final user = supabase.auth.currentUser!;
    final startLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final endLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day + 1);

    final res = await supabase
        .from('exercise_sessions')
        .select()
        .eq('exercise_id', exerciseId)
        .eq('user_id', user.id)
        .gte('created_at', startLocal.toUtc().toIso8601String())
        .lt('created_at', endLocal.toUtc().toIso8601String())
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> deleteSession(String sessionId) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    await supabase
        .from('exercise_sessions')
        .delete()
        .eq('id', sessionId)
        .eq('user_id', user.id);
  }
}
