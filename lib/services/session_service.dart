import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> insertSession({
    required String exerciseId,
    required double weight,
    required int reps,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) throw Exception("User not logged in");

    final res = await supabase.from('exercise_sessions').insert({
      'user_id': user.id,
      'exercise_id': exerciseId,
      'weight': weight,
      'reps': reps,
    })
    .select()
    .single();

    return res;
  }

  Future<List<DateTime>> getLast3SessionDates(String exerciseId) async {
  final user = supabase.auth.currentUser!;

  final res = await supabase
      .from('exercise_sessions')
      .select('created_at')
      .eq('exercise_id', exerciseId)
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(1000); // enough rows to find last 3 distinct days

  final seenDayKeys = <String>{};
  final days = <DateTime>[];

  for (final row in res) {
    final createdLocal = DateTime.parse(row['created_at']).toLocal();
    final dayLocal = DateTime(createdLocal.year, createdLocal.month, createdLocal.day); // midnight local
    final key = '${dayLocal.year}-${dayLocal.month}-${dayLocal.day}';

    if (seenDayKeys.add(key)) {
      days.add(dayLocal);
      if (days.length == 3) break;
    }
  }

  return days; // already in newest-first order because query is desc
}

  Future<List<Map<String, dynamic>>> getSessionsForDate(
  String exerciseId,
  DateTime dayLocal,
) async {
  final user = supabase.auth.currentUser!;

  // Ensure dayLocal is treated as local midnight
  final startLocal = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
  final endLocal = startLocal.add(const Duration(days: 1));

  // Convert local boundaries to UTC instants for DB query
  final startUtc = startLocal.toUtc();
  final endUtc = endLocal.toUtc();

  final res = await supabase
      .from('exercise_sessions')
      .select()
      .eq('exercise_id', exerciseId)
      .eq('user_id', user.id)
      .gte('created_at', startUtc.toIso8601String())
      .lt('created_at', endUtc.toIso8601String())
      .order('created_at', ascending: false); // newest first

  return List<Map<String, dynamic>>.from(res);
}

  Future<void> deleteSession(String sessionId) async {
  await supabase.from('exercise_sessions').delete().eq('id', sessionId);
  }

  
}
