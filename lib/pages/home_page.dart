import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
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

// ✅ public so MainShell can reference it in GlobalKey<HomePageState>
class HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  Map<DateTime, _DayWorkoutSummary> summaryByDay = {};

  _WorkoutFilter _selectedFilter = _WorkoutFilter.all;

  // --- Bug/Suggestion Report UI state ---
  bool _isSubmittingReport = false;
  final TextEditingController _reportController = TextEditingController();
  String _reportType = 'bug'; // 'bug' | 'suggestion'

  // ✅ allow MainShell to refresh Home tab on selection
  Future<void> refresh() async {
    await _loadRecentExercises();
  }

  @override
  void initState() {
    super.initState();
    _loadRecentExercises();
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  // ---------------- Bug/Suggestion report system ----------------

  Future<void> _openReportDialog() async {
    _reportController.clear();
    _reportType = 'bug';

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Report a bug / suggestion'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _reportType,
                  items: const [
                    DropdownMenuItem(value: 'bug', child: Text('Bug')),
                    DropdownMenuItem(value: 'suggestion', child: Text('Suggestion')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() => _reportType = v);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reportController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Describe it',
                    hintText: 'What happened? What did you expect?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: _isSubmittingReport ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: _isSubmittingReport
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Submit'),
                onPressed: _isSubmittingReport
                    ? null
                    : () async {
                        await _submitReport();
                        if (mounted) Navigator.pop(context);
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitReport() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to submit a report.')),
      );
      return;
    }

    final msg = _reportController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message.')),
      );
      return;
    }

    setState(() => _isSubmittingReport = true);

    try {
      await supabase.from('user_reports').insert({
        'user_id': user.id,
        'type': _reportType, // 'bug' or 'suggestion'
        'message': msg,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your report was sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingReport = false);
    }
  }

  // ---------------- Existing workout summary logic ----------------

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
    final list = summaryByDay.entries.where((e) => _matchesFilter(e.value)).toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return list;
  }

  String _buildShareText(List<MapEntry<DateTime, _DayWorkoutSummary>> entries, {String? titleOverride}) {
    final filterName = _filterLabel(_selectedFilter);
    final b = StringBuffer();

    final title = titleOverride ?? 'Fit Quest — Workout Summary ($filterName)';
    b.writeln(title);
    b.writeln('');

    if (entries.isEmpty) {
      b.writeln('No workouts found for this filter.');
      return b.toString().trim();
    }

    for (final entry in entries) {
      final date = entry.key;
      final s = entry.value;

      b.writeln('${_formatDate(date)} — ${s.dayTypeLabel}');

      final muscles = s.muscleGroupCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (muscles.isNotEmpty) {
        b.writeln('Muscles: ${muscles.map((e) => '${e.key}(${e.value})').join(', ')}');
      }

      if (s.exerciseNames.isNotEmpty) {
        b.writeln('Exercises:');
        for (final name in s.exerciseNames) {
          b.writeln('• $name');
        }
      }

      b.writeln('');
    }

    return b.toString().trim();
  }

  Future<void> _shareEntries(List<MapEntry<DateTime, _DayWorkoutSummary>> entries, {String? subject}) async {
    final text = _buildShareText(entries);
    await Share.share(
      text,
      subject: subject ?? 'Workout Summary',
    );
  }

  // ✅ share dialog that lets user select one or more displayed workouts
  Future<void> _openSharePicker() async {
    final entries = _filteredEntries();
    if (entries.isEmpty) return;

    final selected = <DateTime>{};

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          void toggleAll(bool select) {
            setLocal(() {
              selected.clear();
              if (select) selected.addAll(entries.map((e) => e.key));
            });
          }

          final allSelected = selected.length == entries.length && entries.isNotEmpty;

          return AlertDialog(
            title: Text('Share workouts (${_filterLabel(_selectedFilter)})'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Select one or more days to share.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => toggleAll(true),
                        child: const Text('Select all'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => toggleAll(false),
                        child: const Text('Clear'),
                      ),
                      const Spacer(),
                      Text(
                        '${selected.length}/${entries.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final day = e.key;
                        final s = e.value;

                        final isChecked = selected.contains(day);

                        final subtitleParts = <String>[];
                        if (s.exerciseNames.isNotEmpty) subtitleParts.add('${s.exerciseNames.length} exercises');
                        subtitleParts.add(s.dayTypeLabel);

                        return CheckboxListTile(
                          value: isChecked,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_formatDate(day)),
                          subtitle: Text(subtitleParts.join(' • ')),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                selected.add(day);
                              } else {
                                selected.remove(day);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _shareEntries(
                    entries,
                    subject: 'Workout Summary (${_filterLabel(_selectedFilter)})',
                  );
                },
                child: const Text('Share all shown'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share selected'),
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        final picked = entries.where((e) => selected.contains(e.key)).toList();
                        Navigator.pop(context);
                        await _shareEntries(
                          picked,
                          subject: 'Workout Summary (${_filterLabel(_selectedFilter)})',
                        );
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: _WorkoutFilter.values.map((f) {
        final isSelected = _selectedFilter == f;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                backgroundColor: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : null,
                side: BorderSide(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => setState(() => _selectedFilter = f),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _filterLabel(f),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- helpers for volume math (numeric can come back as int/double/String) ---
  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _numToInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<void> _loadRecentExercises() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => summaryByDay = {});
        return;
      }

      // ✅ UPDATED: include weight/reps so we can tie-break Legs vs Core by volume
      final sessions = await supabase
          .from('exercise_sessions')
          .select('created_at, weight, reps, exercises!inner(id, name, type, primary_muscle_group)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final List<DateTime> workoutDays = [];

      // For listing unique exercise names + muscle counts
      final Map<DateTime, Map<String, Map<String, dynamic>>> uniqueExercisesByDay = {};

      // For tie-break logic legs/core by VOLUME (sum of weight*reps for sessions)
      final Map<DateTime, double> legsVolumeByDay = {};
      final Map<DateTime, double> coreVolumeByDay = {};

      for (final row in sessions) {
        final local = DateTime.parse(row['created_at']).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        workoutDays.add(day);

        final w = _numToDouble(row['weight']);
        final r = _numToInt(row['reps']);
        final sessionVolume = w * r;

        final exJoined = row['exercises'];
        final List<Map<String, dynamic>> list = exJoined is List
            ? List<Map<String, dynamic>>.from(exJoined)
            : [Map<String, dynamic>.from(exJoined)];

        uniqueExercisesByDay.putIfAbsent(day, () => {});
        legsVolumeByDay.putIfAbsent(day, () => 0.0);
        coreVolumeByDay.putIfAbsent(day, () => 0.0);

        // A session maps to ONE exercise_id, but your join may come back as list;
        // if it does, we’ll attribute the session volume to each (usually just one).
        for (final ex in list) {
          uniqueExercisesByDay[day]![ex['id'].toString()] = ex;

          final mg = (ex['primary_muscle_group'] ?? '').toString();
          if (_isLegsGroup(mg)) {
            legsVolumeByDay[day] = (legsVolumeByDay[day] ?? 0.0) + sessionVolume;
          }
          if (_isCoreGroup(mg)) {
            coreVolumeByDay[day] = (coreVolumeByDay[day] ?? 0.0) + sessionVolume;
          }
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

        // ✅ FIXED: if ANY legs/core exist, show Legs/Core (whichever has more).
        // tie-break uses total VOLUME for legs vs core (sum of weight*reps per session)
        String label;
        if (legs > 0 || core > 0) {
          if (legs > core) {
            label = 'Legs';
          } else if (core > legs) {
            label = 'Core';
          } else {
            final legsVol = legsVolumeByDay[day] ?? 0.0;
            final coreVol = coreVolumeByDay[day] ?? 0.0;

            if (legsVol > coreVol) {
              label = 'Legs';
            } else if (coreVol > legsVol) {
              label = 'Core';
            } else {
              // perfectly tied: pick a consistent default
              label = 'Legs';
            }
          }
        } else if (pull > push) {
          label = 'Pull';
        } else {
          label = 'Push';
        }

        result[day] = _DayWorkoutSummary(
          day: day,
          exerciseNames: names,
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: label,
        );
      }

      if (!mounted) return;
      setState(() => summaryByDay = result);
    } catch (e, st) {
      debugPrint('Error loading workout summary: $e');
      debugPrint('$st');
      if (!mounted) return;

      setState(() => summaryByDay = {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load workouts: $e')),
      );
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workout Summary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),

              // bug/suggestion report
              IconButton(
                tooltip: 'Report a bug / suggestion',
                onPressed: _isSubmittingReport ? null : _openReportDialog,
                icon: const Icon(Icons.bug_report_outlined),
              ),

              // share picker
              IconButton(
                tooltip: 'Share',
                onPressed: entries.isEmpty ? null : _openSharePicker,
                icon: const Icon(Icons.share),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildFilterBar(),
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
