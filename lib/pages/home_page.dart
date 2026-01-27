import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'exercise_session_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class _DayWorkoutSummary {
  final DateTime day;
  final List<String> exerciseNames;
  final Map<String, int> exerciseSetCountsByName;
  final Map<String, int> muscleGroupCounts;
  final String dayTypeLabel;
  final int workoutDurationMinutes;

  _DayWorkoutSummary({
    required this.day,
    required this.exerciseNames,
    required this.exerciseSetCountsByName,
    required this.muscleGroupCounts,
    required this.dayTypeLabel,
    required this.workoutDurationMinutes,
  });
}

enum _WorkoutFilter { all, push, pull, legs, core }
enum _SuggestedDayType { push, pull, legsCore }

class _SuggestedRoutine {
  final _SuggestedDayType dayType;
  final int minutes;
  final List<Map<String, dynamic>> exercises;

  _SuggestedRoutine({
    required this.dayType,
    required this.minutes,
    required this.exercises,
  });
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  Map<DateTime, _DayWorkoutSummary> summaryByDay = {};

  _WorkoutFilter _selectedFilter = _WorkoutFilter.all;

  bool _isSubmittingReport = false;
  final TextEditingController _reportController = TextEditingController();
  String _reportType = 'bug';

  String? _username;

  _SuggestedRoutine? _suggestedRoutine;
  bool _isSuggesting = false;
  int? _lastSuggestedMinutes;

  // Tracks which local day this suggestion belongs to (YYYY-MM-DD)
  String? _suggestedRoutineDayKey;

  Future<void> refresh() async {
    await _loadRecentExercises();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Restore suggestion (if any) then load summary
    _restoreSuggestedRoutineIfAny().then((_) => _loadRecentExercises());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportController.dispose();
    super.dispose();
  }

  // Persist when app goes to background / inactive
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistSuggestedRoutine();
    }
  }

  // ===================== NEW: open exercise session from suggestion =====================

  Future<void> _openExerciseSessionFromSuggestion(Map<String, dynamic> ex) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseSessionPage(exercise: ex),
      ),
    );

    if (!mounted) return;
    await _loadRecentExercises(); // keep suggestion list the same
    await _persistSuggestedRoutine(); // keep persisted routine up to date
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
        'type': _reportType,
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

  // ---------------- Username loading for share title ----------------

  Future<void> _loadUsernameIfNeeded() async {
    if (_username != null && _username!.trim().isNotEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final row = await supabase.from('profiles').select('username').eq('id', user.id).maybeSingle();
      final name = (row?['username'] ?? '').toString().trim();
      if (name.isNotEmpty) _username = name;
    } catch (_) {}
  }

  String _shareHandle() {
    final u = (_username ?? '').trim();
    if (u.isEmpty) return '@user';
    return u.startsWith('@') ? u : '@$u';
  }

  // ===================== Suggested routine persistence =====================

  String _dayKeyLocal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _prefKeyRoutine(String userId) => 'suggested_routine_v1_$userId';
  String _prefKeyMinutes(String userId) => 'suggested_routine_minutes_v1_$userId';

  Future<void> _persistSuggestedRoutine() async {
    final user = supabase.auth.currentUser;
    final s = _suggestedRoutine;
    if (user == null || s == null) return;

    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'dayKey': _suggestedRoutineDayKey ?? _dayKeyLocal(DateTime.now()),
      'createdAt': DateTime.now().toIso8601String(),
      'dayType': s.dayType.name, // push / pull / legsCore
      'minutes': s.minutes,
      'exerciseIds': s.exercises.map((e) => (e['id'] ?? '').toString()).toList(),
    };

    await prefs.setString(_prefKeyRoutine(user.id), jsonEncode(payload));
    await prefs.setInt(_prefKeyMinutes(user.id), s.minutes);
  }

  Future<void> _clearPersistedSuggestedRoutine() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyRoutine(user.id));
    await prefs.remove(_prefKeyMinutes(user.id));
  }

  _SuggestedDayType? _parseDayType(String? s) {
    switch (s) {
      case 'push':
        return _SuggestedDayType.push;
      case 'pull':
        return _SuggestedDayType.pull;
      case 'legsCore':
        return _SuggestedDayType.legsCore;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadExercisesByIdsInOrder(List<String> ids) async {
    final user = supabase.auth.currentUser;
    if (user == null || ids.isEmpty) return [];

    final rows = await supabase
        .from('exercises')
        .select('id, name, type, primary_muscle_group, video_url, equipment:equipment_id(name)')
        .eq('user_id', user.id)
        .inFilter('id', ids);

    final list = rows is List ? List<Map<String, dynamic>>.from(rows) : <Map<String, dynamic>>[];

    for (final ex in list) {
      final equipment = ex['equipment'];
      if (equipment is Map) {
        ex['equipment_name'] = (equipment['name'] ?? '').toString();
      } else {
        ex['equipment_name'] = '';
      }
    }

    final byId = <String, Map<String, dynamic>>{
      for (final ex in list) (ex['id'] ?? '').toString(): ex,
    };

    final ordered = <Map<String, dynamic>>[];
    for (final id in ids) {
      final ex = byId[id];
      if (ex != null) ordered.add(ex);
    }

    return ordered;
  }

  Future<void> _restoreSuggestedRoutineIfAny() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyRoutine(user.id));
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final dayKey = (data['dayKey'] ?? '').toString();
      final todayKey = _dayKeyLocal(DateTime.now());

      // Only restore if created today
      if (dayKey != todayKey) {
        await _clearPersistedSuggestedRoutine();
        return;
      }

      final dayType = _parseDayType((data['dayType'] ?? '').toString());
      final minutes = int.tryParse((data['minutes'] ?? '').toString()) ?? 0;

      final idsDynamic = data['exerciseIds'];
      final ids = (idsDynamic is List)
          ? idsDynamic.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : <String>[];

      if (dayType == null || minutes <= 0 || ids.isEmpty) {
        await _clearPersistedSuggestedRoutine();
        return;
      }

      final exercises = await _loadExercisesByIdsInOrder(ids);
      if (exercises.isEmpty) {
        await _clearPersistedSuggestedRoutine();
        return;
      }

      if (!mounted) return;
      setState(() {
        _suggestedRoutine = _SuggestedRoutine(
          dayType: dayType,
          minutes: minutes,
          exercises: exercises,
        );
        _lastSuggestedMinutes = minutes;
        _suggestedRoutineDayKey = todayKey;
      });
    } catch (_) {
      await _clearPersistedSuggestedRoutine();
    }
  }

  bool _hasActiveSuggestionToday() {
    final todayKey = _dayKeyLocal(DateTime.now());
    return _suggestedRoutine != null && _suggestedRoutineDayKey == todayKey;
  }

  Future<void> _clearSuggestionInMemoryAndDisk() async {
    setState(() {
      _suggestedRoutine = null;
      _lastSuggestedMinutes = null;
      _suggestedRoutineDayKey = null;
    });
    await _clearPersistedSuggestedRoutine();
  }

  // ---------------- Summary logic ----------------

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

  String _buildShareText(
    List<MapEntry<DateTime, _DayWorkoutSummary>> entries, {
    String? titleOverride,
  }) {
    final filterName = _filterLabel(_selectedFilter);
    final b = StringBuffer();

    final title = titleOverride ?? 'Fit Quest — Workout Summary for ${_shareHandle()} ($filterName)';
    b.writeln(title);
    b.writeln('');

    if (entries.isEmpty) {
      b.writeln('No workouts found for this filter.');
      return b.toString().trim();
    }

    for (final entry in entries) {
      final date = entry.key;
      final s = entry.value;

      final durationText = ' • ${s.workoutDurationMinutes} min';
      b.writeln('${_formatDate(date)}$durationText — ${s.dayTypeLabel}');

      final muscles = s.muscleGroupCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (muscles.isNotEmpty) {
        b.writeln('Muscles: ${muscles.map((e) => '${e.key}(${e.value})').join(', ')}');
      }

      if (s.exerciseNames.isNotEmpty) {
        b.writeln('Exercises:');
        for (final name in s.exerciseNames) {
          final sets = s.exerciseSetCountsByName[name] ?? 0;
          b.writeln('• $name ${sets}x');
        }
      }

      b.writeln('');
    }

    return b.toString().trim();
  }

  Future<void> _shareEntries(
    List<MapEntry<DateTime, _DayWorkoutSummary>> entries, {
    String? subject,
  }) async {
    await _loadUsernameIfNeeded();
    final text = _buildShareText(entries);
    await Share.share(text, subject: subject ?? 'Workout Summary');
  }

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
                        child: Text('Select one or more days to share.',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(onPressed: () => toggleAll(true), child: const Text('Select all')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => toggleAll(false), child: const Text('Clear')),
                      const Spacer(),
                      Text('${selected.length}/${entries.length}', style: Theme.of(context).textTheme.bodySmall),
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
                        subtitleParts.add('${s.workoutDurationMinutes} min');
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _shareEntries(entries, subject: 'Workout Summary (${_filterLabel(_selectedFilter)})');
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

      await _loadUsernameIfNeeded();

      final sessions = await supabase
          .from('exercise_sessions')
          .select('created_at, weight, reps, exercises!inner(id, name, type, primary_muscle_group)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final List<DateTime> workoutDays = [];
      final Map<DateTime, Map<String, Map<String, dynamic>>> uniqueExercisesByDay = {};
      final Map<DateTime, Map<String, int>> setCountsByDayByName = {};
      final Map<DateTime, DateTime> firstSessionLocalByDay = {};
      final Map<DateTime, DateTime> lastSessionLocalByDay = {};
      final Map<DateTime, double> legsVolumeByDay = {};
      final Map<DateTime, double> coreVolumeByDay = {};

      for (final row in sessions) {
        final local = DateTime.parse(row['created_at']).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        workoutDays.add(day);

        final currentFirst = firstSessionLocalByDay[day];
        final currentLast = lastSessionLocalByDay[day];
        if (currentFirst == null || local.isBefore(currentFirst)) firstSessionLocalByDay[day] = local;
        if (currentLast == null || local.isAfter(currentLast)) lastSessionLocalByDay[day] = local;

        final w = _numToDouble(row['weight']);
        final r = _numToInt(row['reps']);
        final sessionVolume = w * r;

        final exJoined = row['exercises'];
        final List<Map<String, dynamic>> list = exJoined is List
            ? List<Map<String, dynamic>>.from(exJoined)
            : [Map<String, dynamic>.from(exJoined)];

        uniqueExercisesByDay.putIfAbsent(day, () => {});
        setCountsByDayByName.putIfAbsent(day, () => {});
        legsVolumeByDay.putIfAbsent(day, () => 0.0);
        coreVolumeByDay.putIfAbsent(day, () => 0.0);

        for (final ex in list) {
          uniqueExercisesByDay[day]![ex['id'].toString()] = ex;

          final exName = (ex['name'] ?? '').toString().trim();
          if (exName.isNotEmpty) {
            setCountsByDayByName[day]![exName] = (setCountsByDayByName[day]![exName] ?? 0) + 1;
          }

          final mg = (ex['primary_muscle_group'] ?? '').toString();
          if (_isLegsGroup(mg)) legsVolumeByDay[day] = (legsVolumeByDay[day] ?? 0.0) + sessionVolume;
          if (_isCoreGroup(mg)) coreVolumeByDay[day] = (coreVolumeByDay[day] ?? 0.0) + sessionVolume;
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
          if (mg.isNotEmpty) muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;

          if (_isLegsGroup(mg)) legs++;
          if (_isCoreGroup(mg)) core++;

          final type = (e['type'] ?? '').toString().toLowerCase();
          if (type == 'push') push++;
          if (type == 'pull') pull++;
        }

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
              label = 'Legs';
            }
          }
        } else if (pull > push) {
          label = 'Pull';
        } else {
          label = 'Push';
        }

        int durationMin = 0;
        final first = firstSessionLocalByDay[day];
        final last = lastSessionLocalByDay[day];
        if (first != null && last != null) {
          durationMin = last.difference(first).inMinutes;
          if (durationMin < 0) durationMin = 0;
        }

        result[day] = _DayWorkoutSummary(
          day: day,
          exerciseNames: names,
          exerciseSetCountsByName: Map<String, int>.from(setCountsByDayByName[day] ?? const {}),
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: label,
          workoutDurationMinutes: durationMin,
        );
      }

      if (!mounted) return;
      setState(() => summaryByDay = result);
    } catch (e, st) {
      debugPrint('Error loading workout summary: $e');
      debugPrint('$st');
      if (!mounted) return;

      setState(() => summaryByDay = {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load workouts: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ===================== SUGGEST ROUTINE FEATURE =====================

  String _canonicalMuscleGroup(String mg) {
    final g = mg.trim().toLowerCase();
    if (g.isEmpty) return '';

    if (_isLegsGroup(g)) return 'legs';
    if (_isCoreGroup(g)) return 'core';

    if (g.contains('chest') || g.contains('pec')) return 'chest';
    if (g.contains('back') || g.contains('lat') || g.contains('trap')) return 'back';
    if (g.contains('shoulder') || g.contains('delt')) return 'shoulders';
    if (g.contains('arm') || g.contains('bicep') || g.contains('tricep') || g.contains('forearm')) return 'arms';

    return g;
  }

  String _suggestedDayTypeLabel(_SuggestedDayType t) {
    switch (t) {
      case _SuggestedDayType.push:
        return 'Push';
      case _SuggestedDayType.pull:
        return 'Pull';
      case _SuggestedDayType.legsCore:
        return 'Legs/Core';
    }
  }

  _SuggestedDayType _lastCompletedCanonicalDayType() {
    if (summaryByDay.isEmpty) return _SuggestedDayType.push;

    final newestDay = summaryByDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final last = summaryByDay[newestDay.first];
    final label = (last?.dayTypeLabel ?? '').trim().toLowerCase();

    if (label == 'push') return _SuggestedDayType.push;
    if (label == 'pull') return _SuggestedDayType.pull;
    return _SuggestedDayType.legsCore;
  }

  _SuggestedDayType _nextRotationType(_SuggestedDayType last) {
    switch (last) {
      case _SuggestedDayType.push:
        return _SuggestedDayType.pull;
      case _SuggestedDayType.pull:
        return _SuggestedDayType.legsCore;
      case _SuggestedDayType.legsCore:
        return _SuggestedDayType.push;
    }
  }

  List<String> _muscleGroupsForSuggestedType(_SuggestedDayType t) {
    switch (t) {
      case _SuggestedDayType.push:
        return const ['chest', 'shoulders', 'arms'];
      case _SuggestedDayType.pull:
        return const ['back', 'arms'];
      case _SuggestedDayType.legsCore:
        return const ['legs', 'core'];
    }
  }

  Future<Map<String, double>> _loadTotalVolumeByCanonicalGroup() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final rows = await supabase
        .from('exercise_sessions')
        .select('weight, reps, exercises!inner(primary_muscle_group)')
        .eq('user_id', user.id);

    final Map<String, double> vol = {
      'back': 0,
      'chest': 0,
      'shoulders': 0,
      'arms': 0,
      'legs': 0,
      'core': 0,
    };

    for (final row in rows) {
      final w = _numToDouble(row['weight']);
      final r = _numToInt(row['reps']);
      final v = w * r;

      final exJoined = row['exercises'];
      final Map<String, dynamic> ex = exJoined is List
          ? Map<String, dynamic>.from((exJoined.isNotEmpty ? exJoined.first : {}) as Map)
          : Map<String, dynamic>.from(exJoined as Map);

      final mgRaw = (ex['primary_muscle_group'] ?? '').toString();
      final mg = _canonicalMuscleGroup(mgRaw);

      if (vol.containsKey(mg)) vol[mg] = (vol[mg] ?? 0) + v;
    }

    return vol;
  }

  Future<List<Map<String, dynamic>>> _loadMyExercises() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('exercises')
        .select('id, name, type, primary_muscle_group, video_url, equipment:equipment_id(name)')
        .eq('user_id', user.id);

    final list = rows is List ? List<Map<String, dynamic>>.from(rows) : <Map<String, dynamic>>[];

    for (final ex in list) {
      final equipment = ex['equipment'];
      if (equipment is Map) {
        ex['equipment_name'] = (equipment['name'] ?? '').toString();
      } else {
        ex['equipment_name'] = '';
      }
    }

    list.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });

    return list;
  }

  Future<Map<String, DateTime>> _loadLastPerformedAtByExerciseId() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final rows = await supabase
        .from('exercise_sessions')
        .select('exercise_id, created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final Map<String, DateTime> lastById = {};

    for (final row in rows) {
      final id = (row['exercise_id'] ?? '').toString();
      if (id.isEmpty) continue;
      if (lastById.containsKey(id)) continue;

      final dt = DateTime.tryParse((row['created_at'] ?? '').toString());
      if (dt != null) lastById[id] = dt.toLocal();
    }

    return lastById;
  }

  // ✅ NEW: If a suggestion exists today, offer "Resume" vs "Generate new"
  Future<void> _handleSuggestButtonPressed() async {
    // If we have an active suggestion today, give options
    if (_hasActiveSuggestionToday()) {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Suggested routine in progress'),
          content: const Text(
            'You already have a suggested routine for today.\n\n'
            'Do you want to resume it, or generate a new one?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, 'resume'), child: const Text('Resume')),
            ElevatedButton(onPressed: () => Navigator.pop(context, 'new'), child: const Text('Generate new')),
          ],
        ),
      );

      if (choice == 'resume') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resuming your current suggested routine below.')),
        );
        return;
      }

      if (choice != 'new') return;

      await _clearSuggestionInMemoryAndDisk();
      // continue to minutes prompt
    }

    await _openSuggestRoutineDialog();
  }

  Future<void> _openSuggestRoutineDialog() async {
    final controller = TextEditingController(text: '30');

    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Suggest routine'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Workout length (minutes)',
            hintText: 'e.g. 30',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              if (m == null || m <= 0) return;
              Navigator.pop(context, m);
            },
            child: const Text('Suggest'),
          ),
        ],
      ),
    );

    if (minutes == null) return;
    await _buildSuggestedRoutine(minutes, randomize: false);
  }

  int _isoWeekKey(DateTime d) {
    if (d.millisecondsSinceEpoch == 0) return 0;

    final date = DateTime(d.year, d.month, d.day);
    final weekday = date.weekday;
    final thursday = date.add(Duration(days: 4 - weekday));
    final weekYear = thursday.year;

    final jan4 = DateTime(weekYear, 1, 4);
    final jan4Weekday = jan4.weekday;
    final firstThursday = jan4.add(Duration(days: 4 - jan4Weekday));

    final weekNum = 1 + ((thursday.difference(firstThursday).inDays) ~/ 7);
    return weekYear * 100 + weekNum;
  }

  Future<void> _buildSuggestedRoutine(int minutes, {bool randomize = false}) async {
    if (_isSuggesting) return;

    setState(() {
      _isSuggesting = true;
      _suggestedRoutine = null;
      _lastSuggestedMinutes = minutes;
    });

    try {
      final totalExercisesTarget = (minutes ~/ 5).clamp(1, 100);

      final lastType = _lastCompletedCanonicalDayType();
      final suggestedType = _nextRotationType(lastType);

      final volByGroup = await _loadTotalVolumeByCanonicalGroup();
      final allExercises = await _loadMyExercises();
      final lastPerformedById = await _loadLastPerformedAtByExerciseId();

      final neverDone = DateTime.fromMillisecondsSinceEpoch(0);

      DateTime _lastTimeFor(Map<String, dynamic> ex) {
        final id = (ex['id'] ?? '').toString();
        return lastPerformedById[id] ?? neverDone;
      }

      final relevantGroups = _muscleGroupsForSuggestedType(suggestedType);

      final pool = allExercises.where((ex) {
        final name = (ex['name'] ?? '').toString().trim();
        if (name.isEmpty) return false;

        final mg = _canonicalMuscleGroup((ex['primary_muscle_group'] ?? '').toString());
        if (!relevantGroups.contains(mg)) return false;

        if (suggestedType == _SuggestedDayType.push) {
          return (ex['type'] ?? '').toString().toLowerCase() == 'push';
        }
        if (suggestedType == _SuggestedDayType.pull) {
          return (ex['type'] ?? '').toString().toLowerCase() == 'pull';
        }
        return true;
      }).toList();

      if (pool.isEmpty) {
        if (!mounted) return;
        setState(() {
          _suggestedRoutine = _SuggestedRoutine(
            dayType: suggestedType,
            minutes: minutes,
            exercises: const [],
          );
          _suggestedRoutineDayKey = _dayKeyLocal(DateTime.now());
        });
        await _persistSuggestedRoutine();
        return;
      }

      final Map<String, List<Map<String, dynamic>>> byGroup = {};
      for (final ex in pool) {
        final mg = _canonicalMuscleGroup((ex['primary_muscle_group'] ?? '').toString());
        byGroup.putIfAbsent(mg, () => []).add(ex);
      }

      final availableGroups = byGroup.keys.toList();
      availableGroups.sort((a, b) {
        final av = volByGroup[a] ?? 0.0;
        final bv = volByGroup[b] ?? 0.0;
        return av.compareTo(bv);
      });

      final groupsSelected = availableGroups;
      final groupCount = groupsSelected.isEmpty ? 1 : groupsSelected.length;

      final base = totalExercisesTarget ~/ groupCount;
      final rem = totalExercisesTarget % groupCount;

      final Map<String, int> takeCount = {};
      for (var i = 0; i < groupsSelected.length; i++) {
        takeCount[groupsSelected[i]] = base + (i < rem ? 1 : 0);
      }

      final List<Map<String, dynamic>> picked = [];

      for (final g in groupsSelected) {
        final list = List<Map<String, dynamic>>.from(byGroup[g] ?? const []);
        if (list.isEmpty) continue;

        final need = takeCount[g] ?? 0;
        if (need <= 0) continue;

        list.sort((a, b) {
          final at = _lastTimeFor(a);
          final bt = _lastTimeFor(b);
          final cmp = at.compareTo(bt);
          if (cmp != 0) return cmp;

          final an = (a['name'] ?? '').toString().toLowerCase();
          final bn = (b['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

        if (randomize) {
          int start = 0;
          while (start < list.length) {
            final wk = _isoWeekKey(_lastTimeFor(list[start]));
            int end = start + 1;
            while (end < list.length && _isoWeekKey(_lastTimeFor(list[end])) == wk) {
              end++;
            }
            final sub = list.sublist(start, end);
            sub.shuffle(Random());
            for (int i = 0; i < sub.length; i++) {
              list[start + i] = sub[i];
            }
            start = end;
          }
        }

        picked.addAll(list.take(need));
      }

      if (picked.length < totalExercisesTarget) {
        final alreadyIds = picked.map((e) => (e['id'] ?? '').toString()).toSet();

        final remaining = pool.where((ex) {
          final id = (ex['id'] ?? '').toString();
          return id.isNotEmpty && !alreadyIds.contains(id);
        }).toList();

        remaining.sort((a, b) {
          final at = _lastTimeFor(a);
          final bt = _lastTimeFor(b);
          final cmp = at.compareTo(bt);
          if (cmp != 0) return cmp;

          final an = (a['name'] ?? '').toString().toLowerCase();
          final bn = (b['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

        if (randomize) {
          int start = 0;
          while (start < remaining.length) {
            final wk = _isoWeekKey(_lastTimeFor(remaining[start]));
            int end = start + 1;
            while (end < remaining.length && _isoWeekKey(_lastTimeFor(remaining[end])) == wk) {
              end++;
            }
            final sub = remaining.sublist(start, end);
            sub.shuffle(Random());
            for (int i = 0; i < sub.length; i++) {
              remaining[start + i] = sub[i];
            }
            start = end;
          }
        }

        for (final ex in remaining) {
          if (picked.length >= totalExercisesTarget) break;
          picked.add(ex);
        }
      }

      if (!mounted) return;

      final todayKey = _dayKeyLocal(DateTime.now());
      setState(() {
        _suggestedRoutine = _SuggestedRoutine(
          dayType: suggestedType,
          minutes: minutes,
          exercises: picked.take(totalExercisesTarget).toList(),
        );
        _suggestedRoutineDayKey = todayKey;
      });

      await _persistSuggestedRoutine();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to build suggestion: $e')));
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  // ✅ UPDATED: Randomize moved to centered position above the first suggested exercise
  Widget _buildSuggestedRoutineCard(BuildContext context) {
    final s = _suggestedRoutine;
    if (s == null) return const SizedBox.shrink();

    final title = _suggestedDayTypeLabel(s.dayType);
    final exCount = s.exercises.length;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Suggested Routine',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () async {
                    await _clearSuggestionInMemoryAndDisk();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Text(
                  '${s.minutes} min • $exCount exercise${exCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),

            const SizedBox(height: 10),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text('Randomize'),
                onPressed: _isSuggesting
                    ? null
                    : () async {
                        final m = _lastSuggestedMinutes ?? s.minutes;
                        await _buildSuggestedRoutine(m, randomize: true);
                      },
              ),
            ),
            const SizedBox(height: 10),

            if (s.exercises.isEmpty)
              const Text('No matching exercises found for this suggestion.')
            else
              ...s.exercises.map((ex) {
                final name = (ex['name'] ?? '').toString();
                final mg = _canonicalMuscleGroup((ex['primary_muscle_group'] ?? '').toString());
                final mgLabel = mg.isEmpty ? '' : mg[0].toUpperCase() + mg.substring(1);
                final equipmentName = (ex['equipment_name'] ?? '').toString().trim();

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openExerciseSessionFromSuggestion(ex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            equipmentName.isEmpty ? '$name ($mgLabel)' : '$name ($mgLabel)  •  $equipmentName',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          'Log',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    final entries = _filteredEntries();

    return PopScope(
      canPop: !_hasActiveSuggestionToday(),
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (!_hasActiveSuggestionToday()) return;

        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Leave workout?'),
            content: const Text(
              'If you leave now, this exact suggested routine might not be suggested again.\n\n'
              'Good news: your current suggestion is saved and will still be here when you return.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
            ],
          ),
        );

        if (leave == true && mounted) {
          await _persistSuggestedRoutine();
          Navigator.pop(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Workout Summary', style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton(
                  tooltip: 'Suggest Routine',
                  onPressed: _isSuggesting ? null : _handleSuggestButtonPressed,
                  icon: _isSuggesting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                ),
                IconButton(
                  tooltip: 'Report a bug / suggestion',
                  onPressed: _isSubmittingReport ? null : _openReportDialog,
                  icon: const Icon(Icons.bug_report_outlined),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: entries.isEmpty ? null : _openSharePicker,
                  icon: const Icon(Icons.share),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildSuggestedRoutineCard(context),
            if (_suggestedRoutine != null) const SizedBox(height: 12),

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
                            child: Row(
                              children: [
                                Text(_formatDate(date), style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text('${s.workoutDurationMinutes} min', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(s.dayTypeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      ...s.exerciseNames.map((name) {
                        final sets = s.exerciseSetCountsByName[name] ?? 0;
                        return Text('• $name ${sets}x');
                      }),
                      const Divider(height: 24),
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
