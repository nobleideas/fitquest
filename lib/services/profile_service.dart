import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final supabase = Supabase.instance.client;

  /// Get the profile for the *current* authenticated user.
  /// Returns null if no profile exists yet.
  Future<Map<String, dynamic>?> getProfile([String? uid]) async {
    final userId = uid ?? supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle(); // <-- prevents crash when row doesn't exist

    return data; // may be null
  }

  /// Create a new profile (used during onboarding)
  Future<void> createProfile({
    required String userId,
    required String username,
    required String goal,
  }) async {
    await supabase.from('profiles').insert({
      'id': userId,
      'username': username,
      'goal': goal, // lose_weight / gain_mass / gain_strength
    });
  }

  Future<void> updateGoal(String newGoal) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase
        .from('profiles')
        .update({'goal': newGoal})
        .eq('id', user.id);
  }
}
