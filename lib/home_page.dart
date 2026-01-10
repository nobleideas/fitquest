import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/equipment_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _DayWorkoutSummary {
  final DateTime day;
  final List<String> exerciseNames; // unique, sorted
  final Map<String, int> muscleGroupCounts; // primary muscle group -> count of unique exercises
  final String dayTypeLabel; // Legs/Core override, else Push/Pull

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

  /// Local workout day -> summary
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

  /* -------------------------------------------------------------------------- */
  /*                     LOAD ALL WORKOUT DAYS + ANALYTICS                      */
  /* -------------------------------------------------------------------------- */
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

      // Per day: unique exercises by exercise UUID (String)
      final Map<DateTime, Map<String, Map<String, dynamic>>> uniqueExercisesByDay =
          {};

      for (final row in sessions) {
        final createdAtRaw = row['created_at'];
        if (createdAtRaw == null) continue;

        final local = DateTime.parse(createdAtRaw.toString()).toLocal();
        final day = DateTime(local.year, local.month, local.day);

        if (!workoutDays.contains(day)) {
          workoutDays.add(day);
        }

        final exJoined = row['exercises'];

        List<Map<String, dynamic>> exercisesList = [];
        if (exJoined is Map<String, dynamic>) {
          exercisesList = [exJoined];
        } else if (exJoined is List) {
          exercisesList = exJoined
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          continue;
        }

        uniqueExercisesByDay.putIfAbsent(
            day, () => <String, Map<String, dynamic>>{});

        for (final ex in exercisesList) {
          final exIdRaw = ex['id'];
          if (exIdRaw == null) continue;

          final exId = exIdRaw.toString(); // UUID string
          uniqueExercisesByDay[day]![exId] = ex;
        }
      }

      final Map<DateTime, _DayWorkoutSummary> result = {};

      for (final day in workoutDays) {
        final exMap = uniqueExercisesByDay[day] ?? {};
        final uniqueExercises = exMap.values.toList();

        final names = uniqueExercises
            .map((e) => (e['name'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        // Primary muscle group counts (counts of unique exercises)
        final Map<String, int> muscleCounts = {};
        for (final e in uniqueExercises) {
          final mg =
              (e['primary_muscle_group'] ?? 'Unknown').toString().trim();
          if (mg.isEmpty) continue;
          muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;
        }

        // Push/Pull counts (counts of unique exercises)
        int pushCount = 0;
        int pullCount = 0;

        for (final e in uniqueExercises) {
          final type = (e['type'] ?? '').toString().trim().toLowerCase();
          if (type == 'push') pushCount++;
          if (type == 'pull') pullCount++;
        }

        // ✅ Legs/Core override if it is a MAJORITY (> 50%)
        final int totalExercises = uniqueExercises.length;

        int legsCount = 0;
        int coreCount = 0;

        for (final entry in muscleCounts.entries) {
          if (_isLegsGroup(entry.key)) legsCount += entry.value;
          if (_isCoreGroup(entry.key)) coreCount += entry.value;
        }

        String dayTypeLabel;
        if (totalExercises > 0 && legsCount > totalExercises / 2) {
          dayTypeLabel = 'Legs';
        } else if (totalExercises > 0 && coreCount > totalExercises / 2) {
          dayTypeLabel = 'Core';
        } else {
          // Greater wins; no "Mixed". Tie-breaker defaults to Push.
          dayTypeLabel = (pullCount > pushCount) ? 'Pull' : 'Push';
        }

        result[day] = _DayWorkoutSummary(
          day: day,
          exerciseNames: names,
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: dayTypeLabel,
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

  /* -------------------------------------------------------------------------- */
  /*                                   UI                                       */
  /* -------------------------------------------------------------------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fit Quest')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EquipmentListPage(),
                  ),
                );
              },
              child: const Text("View My Equipment"),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Recent Workouts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (summaryByDay.isEmpty)
              const Text('No workouts logged yet.')
            else
              ...summaryByDay.entries.map((entry) {
                final date = entry.key;
                final summary = entry.value;

                final muscleEntries = summary.muscleGroupCounts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
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
                              summary.dayTypeLabel,
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text('${e.key}: ${e.value}'),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 8),
                      ...summary.exerciseNames.map((name) => Text('• $name')),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
