import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class SessionService {
  Future<void> insertSession({
    required String exerciseId,
    required double weight,
    required int reps,
  }) async {
    final user = supabase.auth.currentUser!;
    await supabase.from('exercise_sessions').insert({
      'exercise_id': exerciseId,
      'user_id': user.id,
      'weight': weight,
      'reps': reps,
    });
  }

  Future<void> deleteSession(String sessionId) async {
    await supabase.from('exercise_sessions').delete().eq('id', sessionId);
  }

  /// Get the last 3 distinct days that have sessions for this exercise
  Future<List<DateTime>> getLast3SessionDates(String exerciseId) async {
    final user = supabase.auth.currentUser!;
    
    // Use SQL query to fetch distinct UTC dates
    final res = await supabase.rpc('last_3_session_dates', params: {
      'exercise_id_param': exerciseId,
      'user_id_param': user.id,
    });

    // res should be List of ISO date strings
    final dates = (res as List<dynamic>)
        .map((d) => DateTime.parse(d.toString()).toLocal())
        .toList();

    return dates;
  }

  /// Get all sessions for a specific day (date in UTC-safe)
  Future<List<Map<String, dynamic>>> getSessionsForDate(
      String exerciseId, DateTime date) async {
    final user = supabase.auth.currentUser!;

    // Start and end of day in UTC
    final startUtc = DateTime.utc(date.year, date.month, date.day);
    final endUtc = startUtc.add(const Duration(days: 1));

    final res = await supabase
        .from('exercise_sessions')
        .select()
        .eq('exercise_id', exerciseId)
        .eq('user_id', user.id)
        .gte('created_at', startUtc.toIso8601String())
        .lt('created_at', endUtc.toIso8601String())
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(res);
  }
}
