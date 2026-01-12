import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _DayWorkoutSummary {
  final DateTime day;
  final List<String> exerciseNames;
  final Map<String, int> muscleGroupCounts;
  final String dayTypeLabel;

  _DayWorkoutSummary({
    required this.day,
    required this.exerciseNames,
    required this.muscleGroupCounts,
    required this.dayTypeLabel,
  });
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  Map<DateTime, _DayWorkoutSummary> summaryByDay = {};

  @override
  void initState() {
    super.initState();
    _loadRecentExercises();
  }

  bool _isLegsGroup(String group) {
    final g = group.trim().toLowerCase();
    return g == 'legs' ||
        g == 'leg' ||
        g == 'lower body' ||
        g == 'lowerbody' ||
        g == 'quads' ||
        g == 'quadriceps' ||
        g == 'hamstrings' ||
        g == 'glutes' ||
        g == 'calves';
  }

  bool _isCoreGroup(String group) {
    final g = group.trim().toLowerCase();
    return g == 'core' ||
        g == 'abs' ||
        g == 'abdominals' ||
        g == 'obliques' ||
        g == 'lower abs' ||
        g == 'upper abs';
  }

  Future<void> _loadRecentExercises() async {
    setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => summaryByDay = {});
        return;
      }

      final sessions = await supabase
          .from('exercise_sessions')
          .select('created_at, exercises!inner(id, name, type, primary_muscle_group)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final List<DateTime> workoutDays = [];
      final Map<DateTime, Map<String, Map<String, dynamic>>> uniqueExercisesByDay = {};

      for (final row in sessions) {
        final local = DateTime.parse(row['created_at']).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        workoutDays.add(day);

        final exJoined = row['exercises'];
        final List<Map<String, dynamic>> list = exJoined is List
            ? List<Map<String, dynamic>>.from(exJoined)
            : [Map<String, dynamic>.from(exJoined)];

        uniqueExercisesByDay.putIfAbsent(day, () => {});
        for (final ex in list) {
          uniqueExercisesByDay[day]![ex['id'].toString()] = ex; // UUID-safe unique
        }
      }

      // keep newest -> oldest, remove duplicates while preserving order
      final orderedUniqueDays = <DateTime>[];
      for (final d in workoutDays) {
        if (!orderedUniqueDays.contains(d)) orderedUniqueDays.add(d);
      }

      final Map<DateTime, _DayWorkoutSummary> result = {};

      for (final day in orderedUniqueDays) {
        final uniqueExercises = (uniqueExercisesByDay[day] ?? {}).values.toList();

        final names = uniqueExercises
            .map((e) => (e['name'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final Map<String, int> muscleCounts = {};
        int push = 0, pull = 0, legs = 0, core = 0;

        for (final e in uniqueExercises) {
          final mg = (e['primary_muscle_group'] ?? '').toString();
          if (mg.isNotEmpty) {
            muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;
          }

          if (_isLegsGroup(mg)) legs++;
          if (_isCoreGroup(mg)) core++;

          final type = (e['type'] ?? '').toString().toLowerCase();
          if (type == 'push') push++;
          if (type == 'pull') pull++;
        }

        final total = uniqueExercises.length;

        final label = (legs > total / 2)
            ? 'Legs'
            : (core > total / 2)
                ? 'Core'
                : (pull > push)
                    ? 'Pull'
                    : 'Push';

        result[day] = _DayWorkoutSummary(
          day: day,
          exerciseNames: names,
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: label,
        );
      }

      setState(() => summaryByDay = result);
    } catch (e, st) {
      debugPrint('Error loading workout summary: $e');
      debugPrint('$st');
      setState(() => summaryByDay = {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load workouts: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (summaryByDay.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No workouts logged yet.'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: summaryByDay.entries.map((entry) {
          final date = entry.key;
          final s = entry.value;

          // Muscle chips ordered high->low
          final muscleEntries = s.muscleGroupCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${date.month}/${date.day}/${date.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        s.dayTypeLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (muscleEntries.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: muscleEntries.map((e) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text('${e.key}: ${e.value}'),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 8),
                ...s.exerciseNames.map((name) => Text('• $name')),
                const Divider(height: 24),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
