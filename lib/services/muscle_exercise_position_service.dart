import 'package:supabase_flutter/supabase_flutter.dart';

/// Derives the 1st/2nd/etc exercise within its primary muscle group.
/// Existing exercise_order remains the authoritative daily sequence.
class MuscleExercisePositionService {
  final _db = Supabase.instance.client;

  static String ordinal(int n) {
    final suffix = n % 100 >= 11 && n % 100 <= 13 ? 'th'
        : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suffix';
  }

  static String label(int position, String muscle) =>
      '${ordinal(position)} ${muscle.trim().isEmpty ? 'Muscle Group' : muscle.trim()} Exercise';

  Future<Map<String, int>> positionsForDay(DateTime day) async {
    final user = _db.auth.currentUser;
    if (user == null) return {};
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0;; offset += pageSize) {
      final page = await _db.from('exercise_sessions')
          .select('exercise_id, exercise_order, exercises!inner(primary_muscle_group)')
          .eq('user_id', user.id)
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', end.toUtc().toIso8601String())
          .order('exercise_order', ascending: true)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((r) => Map<String, dynamic>.from(r)));
      if (page.length < pageSize) break;
    }
    final first = <String, ({int order, String muscle})>{};
    for (final row in rows) {
      final id = (row['exercise_id'] ?? '').toString();
      final raw = row['exercise_order'];
      final order = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (id.isEmpty || order == null || order <= 0) continue;
      final ex = row['exercises'];
      final muscle = ex is Map ? (ex['primary_muscle_group'] ?? '').toString().trim() : '';
      if (muscle.isEmpty) continue;
      if (!first.containsKey(id) || order < first[id]!.order) {
        first[id] = (order: order, muscle: muscle);
      }
    }
    final sorted = first.entries.toList()
      ..sort((a, b) => a.value.order.compareTo(b.value.order));
    final counts = <String, int>{};
    final result = <String, int>{};
    for (final entry in sorted) {
      final group = entry.value.muscle.toLowerCase();
      counts[group] = (counts[group] ?? 0) + 1;
      result[entry.key] = counts[group]!;
    }
    return result;
  }
}
