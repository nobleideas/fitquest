import 'package:supabase_flutter/supabase_flutter.dart';

class YearWorkoutStats {
  final int year;
  final int workoutDays;
  final String bestMonthLabel;
  final int bestMonthWorkoutDays;
  final String bestWeekLabel;
  final int bestWeekWorkoutDays;
  final double estimatedWorkoutHours;

  const YearWorkoutStats({
    required this.year,
    required this.workoutDays,
    required this.bestMonthLabel,
    required this.bestMonthWorkoutDays,
    required this.bestWeekLabel,
    required this.bestWeekWorkoutDays,
    required this.estimatedWorkoutHours,
  });

  factory YearWorkoutStats.empty(int year) {
    return YearWorkoutStats(
      year: year,
      workoutDays: 0,
      bestMonthLabel: '—',
      bestMonthWorkoutDays: 0,
      bestWeekLabel: '—',
      bestWeekWorkoutDays: 0,
      estimatedWorkoutHours: 0,
    );
  }
}

class ProfileService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getProfile([String? uid]) async {
    final userId = uid ?? supabase.auth.currentUser?.id;
    if (userId == null) return null;

    return supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
  }

  Future<void> createProfile({
    required String userId,
    required String username,
    required String goal,
  }) async {
    await supabase.from('profiles').insert({
      'id': userId,
      'username': username,
      'goal': goal,
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

  Future<YearWorkoutStats> getCurrentYearWorkoutStats() async {
    final user = supabase.auth.currentUser;
    final now = DateTime.now();
    final year = now.year;

    if (user == null) return YearWorkoutStats.empty(year);

    final startLocal = DateTime(year, 1, 1);
    final endLocal = DateTime(year + 1, 1, 1);

    final rowsRaw = await supabase
        .from('exercise_sessions')
        .select('id, created_at')
        .eq('user_id', user.id)
        .gte('created_at', startLocal.toUtc().toIso8601String())
        .lt('created_at', endLocal.toUtc().toIso8601String())
        .order('created_at', ascending: true);

    final rows = (rowsRaw as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (rows.isEmpty) return YearWorkoutStats.empty(year);

    final sessionsByDay = <DateTime, List<DateTime>>{};

    for (final row in rows) {
      final parsed = DateTime.tryParse(
        (row['created_at'] ?? '').toString(),
      );
      if (parsed == null) continue;

      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      sessionsByDay.putIfAbsent(day, () => <DateTime>[]).add(local);
    }

    if (sessionsByDay.isEmpty) return YearWorkoutStats.empty(year);

    final monthCounts = <DateTime, int>{};
    final weekCounts = <DateTime, int>{};
    double totalMinutes = 0;

    for (final entry in sessionsByDay.entries) {
      final day = entry.key;
      final sessions = [...entry.value]..sort();

      final monthKey = DateTime(day.year, day.month);
      monthCounts[monthKey] = (monthCounts[monthKey] ?? 0) + 1;

      final weekStart = _startOfWeek(day);
      weekCounts[weekStart] = (weekCounts[weekStart] ?? 0) + 1;

      var minutes = sessions.last.difference(sessions.first).inMinutes + 5;
      minutes = minutes.clamp(10, 240);
      totalMinutes += minutes;
    }

    final bestMonth = _highestCountEntry(monthCounts);
    final bestWeek = _highestCountEntry(weekCounts);

    return YearWorkoutStats(
      year: year,
      workoutDays: sessionsByDay.length,
      bestMonthLabel:
          bestMonth == null ? '—' : _monthName(bestMonth.key.month),
      bestMonthWorkoutDays: bestMonth?.value ?? 0,
      bestWeekLabel:
          bestWeek == null ? '—' : _formatWeekRange(bestWeek.key),
      bestWeekWorkoutDays: bestWeek?.value ?? 0,
      estimatedWorkoutHours: totalMinutes / 60.0,
    );
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    );
  }

  MapEntry<DateTime, int>? _highestCountEntry(
    Map<DateTime, int> values,
  ) {
    if (values.isEmpty) return null;

    final entries = values.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) return countCompare;
        return b.key.compareTo(a.key);
      });

    return entries.first;
  }

  String _formatWeekRange(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));

    if (weekStart.month == weekEnd.month) {
      return '${_monthShort(weekStart.month)} '
          '${weekStart.day}–${weekEnd.day}';
    }

    return '${_monthShort(weekStart.month)} ${weekStart.day}–'
        '${_monthShort(weekEnd.month)} ${weekEnd.day}';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month - 1];
  }

  String _monthShort(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }
}
