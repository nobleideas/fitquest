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

    if (user == null) {
      return YearWorkoutStats.empty(year);
    }

    final startLocal = DateTime(year, 1, 1);
    final endLocal = DateTime(year + 1, 1, 1);

    final List<Map<String, dynamic>> rows = [];
    const int pageSize = 1000;
    int from = 0;

    while (true) {
      final pageRaw = await supabase
          .from('exercise_sessions')
          .select('id, created_at')
          .eq('user_id', user.id)
          .gte(
            'created_at',
            startLocal.toUtc().toIso8601String(),
          )
          .lt(
            'created_at',
            endLocal.toUtc().toIso8601String(),
          )
          .order('created_at', ascending: true)
          .range(from, from + pageSize - 1);

      final page = (pageRaw as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      rows.addAll(page);

      if (page.length < pageSize) {
        break;
      }

      from += pageSize;
    }

    if (rows.isEmpty) {
      return YearWorkoutStats.empty(year);
    }

    final sessionsByDay = <DateTime, List<DateTime>>{};

    for (final row in rows) {
      final parsed = DateTime.tryParse(
        (row['created_at'] ?? '').toString(),
      );

      if (parsed == null) continue;

      final local = parsed.toLocal();
      if (local.year != year) continue;

      final day = DateTime(
        local.year,
        local.month,
        local.day,
      );

      sessionsByDay
          .putIfAbsent(day, () => <DateTime>[])
          .add(local);
    }

    if (sessionsByDay.isEmpty) {
      return YearWorkoutStats.empty(year);
    }

    final monthCounts = <DateTime, int>{};
    final weekCounts = <DateTime, int>{};
    double totalMinutes = 0;

    for (final entry in sessionsByDay.entries) {
      final day = entry.key;
      final sessions = [...entry.value]..sort();

      final monthKey = DateTime(day.year, day.month);
      monthCounts[monthKey] =
          (monthCounts[monthKey] ?? 0) + 1;

      final weekStart = _startOfWeek(day);
      weekCounts[weekStart] =
          (weekCounts[weekStart] ?? 0) + 1;

      var minutes =
          sessions.last.difference(sessions.first).inMinutes + 5;

      minutes = minutes.clamp(10, 240);
      totalMinutes += minutes;
    }

    final bestMonths = _highestCountEntries(monthCounts);
    final bestWeeks = _highestCountEntries(weekCounts);

    final bestMonthCount =
        bestMonths.isEmpty ? 0 : bestMonths.first.value;

    final bestWeekCount =
        bestWeeks.isEmpty ? 0 : bestWeeks.first.value;

    final bestMonthLabel = bestMonths.isEmpty
        ? '—'
        : bestMonths
            .map((entry) => _monthName(entry.key.month))
            .join('\n');

    final bestWeekLabel = bestWeeks.isEmpty
        ? '—'
        : bestWeeks
            .map((entry) => _formatWeekRange(entry.key))
            .join('\n');

    return YearWorkoutStats(
      year: year,
      workoutDays: sessionsByDay.length,
      bestMonthLabel: bestMonthLabel,
      bestMonthWorkoutDays: bestMonthCount,
      bestWeekLabel: bestWeekLabel,
      bestWeekWorkoutDays: bestWeekCount,
      estimatedWorkoutHours: totalMinutes / 60.0,
    );
  }

  DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return normalized.subtract(
      Duration(
        days: normalized.weekday - DateTime.monday,
      ),
    );
  }

  List<MapEntry<DateTime, int>> _highestCountEntries(
    Map<DateTime, int> values,
  ) {
    if (values.isEmpty) {
      return [];
    }

    final highestCount = values.values.reduce(
      (a, b) => a > b ? a : b,
    );

    final tiedEntries = values.entries
        .where((entry) => entry.value == highestCount)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return tiedEntries;
  }

  String _formatWeekRange(DateTime weekStart) {
    final weekEnd = weekStart.add(
      const Duration(days: 6),
    );

    if (weekStart.month == weekEnd.month) {
      return '${_monthShort(weekStart.month)} '
          '${weekStart.day}–${weekEnd.day}';
    }

    return '${_monthShort(weekStart.month)} ${weekStart.day}–'
        '${_monthShort(weekEnd.month)} ${weekEnd.day}';
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  String _monthShort(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[month - 1];
  }
}
