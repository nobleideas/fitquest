import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final supabase = Supabase.instance.client;

  Future<void> insertSession({
    required String exerciseId,
    required double weight,
    required int reps,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) throw Exception("User not logged in");

    await supabase.from('exercise_sessions').insert({
      'user_id': user.id,
      'exercise_id': exerciseId,
      'weight': weight,
      'reps': reps,
    });
  }

  Future<List<DateTime>> getLast3SessionDates(String exerciseId) async {
  final user = supabase.auth.currentUser!;
  
  final res = await supabase
      .from('exercise_sessions')
      .select('created_at')
      .eq('exercise_id', exerciseId)
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(1000); // fetch enough rows

  // Extract distinct dates
  final dates = <DateTime>{};
  for (var row in res) {
    final date = DateTime.parse(row['created_at']).toLocal();
    dates.add(DateTime(date.year, date.month, date.day, date.hour, date.minute, date.second));
  }

  final sortedDates = dates.toList()
    ..sort((a, b) => b.compareTo(a)); // descending

  return sortedDates.take(3).toList();
  }

  Future<List<Map<String, dynamic>>> getSessionsForDate(
    String exerciseId, DateTime date) async {
  final user = supabase.auth.currentUser!;

  // Start and end of day in UTC
  final startUtc = (DateTime.utc(date.year, date.month, date.day, date.hour, date.minute, date.second));
  final endUtc = startUtc.add(const Duration(days: 1));

  print(startUtc.toIso8601String());
  print(endUtc.toIso8601String());

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

  Future<void> deleteSession(String sessionId) async {
  await supabase.from('exercise_sessions').delete().eq('id', sessionId);
  }

  
}
