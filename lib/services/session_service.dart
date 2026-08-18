import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> insertSession({
    required String exerciseId,
    required double weight,
    required double metricValue,
    required String metricType,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) throw Exception('User not logged in');

    _validateMetric(metricType, metricValue);

    final res = await supabase
        .from('exercise_sessions')
        .insert({
          'user_id': user.id,
          'exercise_id': exerciseId,
          'weight': weight,
          // Keep reps populated for backwards compatibility with older code.
          // Non-rep metrics intentionally store 0 reps.
          'reps': metricType == 'reps' ? metricValue.toInt() : 0,
          'metric_type': metricType,
          'metric_value': metricValue,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(res);
  }

  Future<void> updateSession({
    required String sessionId,
    required double weight,
    required double metricValue,
    required String metricType,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    _validateMetric(metricType, metricValue);

    await supabase
        .from('exercise_sessions')
        .update({
          'weight': weight,
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

    if (metricValue < 0) {
      throw ArgumentError('Metric value cannot be negative.');
    }

    if (metricType == 'reps' && metricValue != metricValue.roundToDouble()) {
      throw ArgumentError('Reps must be a whole number.');
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
    final endLocal = startLocal.add(const Duration(days: 1));

    final startUtc = startLocal.toUtc();
    final endUtc = endLocal.toUtc();

    final res = await supabase
        .from('exercise_sessions')
        .select()
        .eq('exercise_id', exerciseId)
        .eq('user_id', user.id)
        .gte('created_at', startUtc.toIso8601String())
        .lt('created_at', endUtc.toIso8601String())
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
