import 'package:supabase_flutter/supabase_flutter.dart';

class GymService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _currentUserId {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required.');
    }
    return user.id;
  }

  /// Returns all non-archived gyms owned by the current user.
  Future<List<Map<String, dynamic>>> getGyms({
    bool includeArchived = false,
  }) async {
    var query = _supabase
        .from('gyms')
        .select('id, user_id, name, is_archived, created_at, updated_at')
        .eq('user_id', _currentUserId);

    if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    final rows = await query.order('name', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Returns the current user's active gym, or null when none is selected.
  Future<Map<String, dynamic>?> getActiveGym() async {
    final profile = await _supabase
        .from('profiles')
        .select('active_gym_id')
        .eq('id', _currentUserId)
        .maybeSingle();

    final activeGymId = profile?['active_gym_id']?.toString();
    if (activeGymId == null || activeGymId.isEmpty) {
      return null;
    }

    final gym = await _supabase
        .from('gyms')
        .select('id, user_id, name, is_archived, created_at, updated_at')
        .eq('id', activeGymId)
        .eq('user_id', _currentUserId)
        .eq('is_archived', false)
        .maybeSingle();

    // This can occur if the active gym was archived or otherwise became invalid.
    if (gym == null) {
      await clearActiveGym();
      return null;
    }

    return Map<String, dynamic>.from(gym);
  }

  /// Returns only the active gym ID, or null when none is selected.
  Future<String?> getActiveGymId() async {
    final profile = await _supabase
        .from('profiles')
        .select('active_gym_id')
        .eq('id', _currentUserId)
        .maybeSingle();

    final value = profile?['active_gym_id']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  /// Creates a gym. By default, it becomes active when the user has no active gym.
  Future<Map<String, dynamic>> createGym(
    String name, {
    bool makeActive = false,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Gym name cannot be blank.');
    }

    final existingActiveGymId = await getActiveGymId();

    final inserted = await _supabase
        .from('gyms')
        .insert({'user_id': _currentUserId, 'name': trimmedName})
        .select('id, user_id, name, is_archived, created_at, updated_at')
        .single();

    final gym = Map<String, dynamic>.from(inserted);
    final gymId = gym['id']?.toString();

    if (gymId == null || gymId.isEmpty) {
      throw StateError('The gym was created without a valid ID.');
    }

    if (makeActive || existingActiveGymId == null) {
      await setActiveGym(gymId);
    }

    return gym;
  }

  /// Sets the current user's active gym.
  ///
  /// RLS verifies that the gym belongs to the current user and is not archived.
  Future<void> setActiveGym(String gymId) async {
    final trimmedGymId = gymId.trim();
    if (trimmedGymId.isEmpty) {
      throw ArgumentError('Gym ID cannot be blank.');
    }

    await _supabase
        .from('profiles')
        .update({'active_gym_id': trimmedGymId})
        .eq('id', _currentUserId);
  }

  /// Clears the current user's active gym selection.
  Future<void> clearActiveGym() async {
    await _supabase
        .from('profiles')
        .update({'active_gym_id': null})
        .eq('id', _currentUserId);
  }

  /// Renames a gym owned by the current user.
  Future<void> renameGym({required String gymId, required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Gym name cannot be blank.');
    }

    await _supabase
        .from('gyms')
        .update({
          'name': trimmedName,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', gymId)
        .eq('user_id', _currentUserId);
  }

  /// Archives a gym instead of deleting it.
  ///
  /// If it is currently active, the active gym selection is cleared first.
  Future<void> archiveGym(String gymId) async {
    final activeGymId = await getActiveGymId();

    if (activeGymId == gymId) {
      await clearActiveGym();
    }

    await _supabase
        .from('gyms')
        .update({
          'is_archived': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', gymId)
        .eq('user_id', _currentUserId);
  }

  /// Restores a previously archived gym.
  Future<void> restoreGym(String gymId) async {
    await _supabase
        .from('gyms')
        .update({
          'is_archived': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', gymId)
        .eq('user_id', _currentUserId);
  }
}
