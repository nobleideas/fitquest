import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

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

enum _WorkoutFilter { all, push, pull, legs, core }

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  Map<DateTime, _DayWorkoutSummary> summaryByDay = {};

  _WorkoutFilter _selectedFilter = _WorkoutFilter.all;

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

  String _filterLabel(_WorkoutFilter f) {
    switch (f) {
      case _WorkoutFilter.all:
        return 'All';
      case _WorkoutFilter.push:
        return 'Push';
      case _WorkoutFilter.pull:
        return 'Pull';
      case _WorkoutFilter.legs:
        return 'Legs';
      case _WorkoutFilter.core:
        return 'Core';
    }
  }

  bool _matchesFilter(_DayWorkoutSummary s) {
    if (_selectedFilter == _WorkoutFilter.all) return true;

    final label = s.dayTypeLabel.trim().toLowerCase();
    switch (_selectedFilter) {
      case _WorkoutFilter.all:
        return true;
      case _WorkoutFilter.push:
        return label == 'push';
      case _WorkoutFilter.pull:
        return label == 'pull';
      case _WorkoutFilter.legs:
        return label == 'legs';
      case _WorkoutFilter.core:
        return label == 'core';
    }
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  List<MapEntry<DateTime, _DayWorkoutSummary>> _filteredEntries() {
    return summaryByDay.entries
        .where((e) => _matchesFilter(e.value))
        .toList();
  }

  /// Builds a shareable text block from the currently filtered workouts.
  String _buildShareText(List<MapEntry<DateTime, _DayWorkoutSummary>> entries) {
    final filterName = _filterLabel(_selectedFilter);
    final b = StringBuffer();

    b.writeln('Fit Quest — Workout Summary ($filterName)');
    b.writeln('');

    for (final entry in entries) {
      final date = entry.key;
      final s = entry.value;

      b.writeln('${_formatDate(date)} — ${s.dayTypeLabel}');

      // Muscle counts (high -> low)
      final muscles = s.muscleGroupCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (muscles.isNotEmpty) {
        b.writeln('Muscles: ${muscles.map((e) => '${e.key}(${e.value})').join(', ')}');
      }

      if (s.exerciseNames.isNotEmpty) {
        b.writeln('Exercises: ${s.exerciseNames.join(', ')}');
      }

      b.writeln(''); // blank line between days
    }

    if (entries.isEmpty) {
      b.writeln('No workouts found for this filter.');
    }

    return b.toString().trim();
  }

  Future<void> _shareFilteredWorkouts() async {
    final entries = _filteredEntries();

    final text = _buildShareText(entries);

    // Optional: share the current page position (mobile). If context is missing, Share.share still works.
    await Share.share(
      text,
      subject: 'Workout Summary (${_filterLabel(_selectedFilter)})',
    );
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

    final entries = _filteredEntries();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // ---------- Header row with Share ----------
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workout Summary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Share',
                onPressed: entries.isEmpty ? null : _shareFilteredWorkouts,
                icon: const Icon(Icons.share),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---------- Filter Buttons ----------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _WorkoutFilter.values.map((f) {
              final selected = _selectedFilter == f;
              return ChoiceChip(
                label: Text(_filterLabel(f)),
                selected: selected,
                onSelected: (_) => setState(() => _selectedFilter = f),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          if (summaryByDay.isEmpty)
            const Text('No workouts logged yet.')
          else if (entries.isEmpty)
            const Text('No workouts found for this filter.')
          else
            ...entries.map((entry) {
              final date = entry.key;
              final s = entry.value;

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
                            _formatDate(date),
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
        ],
      ),
    );
  }
}
