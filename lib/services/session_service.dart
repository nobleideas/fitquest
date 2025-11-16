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
}
