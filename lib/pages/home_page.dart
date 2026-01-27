import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/suggestion_service.dart';
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

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  Map<DateTime, _DayWorkoutSummary> summaryByDay = {};

  _WorkoutFilter _selectedFilter = _WorkoutFilter.all;

  bool _isSubmittingReport = false;
  final TextEditingController _reportController = TextEditingController();
  String _reportType = 'bug';

  String? _username;

  // -------- Suggestion state (minimal + clean) --------
  final SuggestedDayTypeChoice _defaultChoice = SuggestedDayTypeChoice.auto;
  SuggestedRoutine? _suggestedRoutine;
  bool _isSuggesting = false;
  int _lastSuggestedMinutes = 30;

  // ---------- Persisted suggestion ----------
  static const String _prefsKeySuggestedRoutine = 'home.suggested_routine.v1';
  static const String _prefsKeyLastSuggestedMinutes = 'home.last_suggested_minutes.v1';

  // For "close app" warning (Android back / system navigation)
  bool _didShowCloseWarningThisSession = false;

  SuggestionService get _suggestionService => SuggestionService(supabase);

  Future<void> refresh() async {
    await _loadRecentExercises();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load persisted suggestion first, then load summary.
    _restoreSuggestedRoutineFromPrefs();
    _loadRecentExercises();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reportController.dispose();
    super.dispose();
  }

  // If app is backgrounded / detached, keep the latest suggestion saved.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistSuggestedRoutineToPrefs();
    }
  }

  // ===================== Persistence helpers =====================

  Map<String, dynamic> _routineToJson(SuggestedRoutine r) {
    return {
      'minutes': r.minutes,
      'dayType': r.dayType.name, // push / pull / legsCore (enum name)
      'message': r.message,
      'exercises': r.exercises, // already List<Map<String,dynamic>>
      'saved_at_utc': DateTime.now().toUtc().toIso8601String(),
    };
  }

  SuggestedRoutine? _routineFromJson(Map<String, dynamic> json) {
    try {
      final minutes = (json['minutes'] as num?)?.toInt() ?? 0;
      final dayTypeStr = (json['dayType'] ?? '').toString().trim();
      final message = (json['message'] as String?)?.toString();

      final exRaw = json['exercises'];
      final List<Map<String, dynamic>> exercises = (exRaw is List)
          ? exRaw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : <Map<String, dynamic>>[];

      if (minutes <= 0) return null;

      SuggestedDayType dayType;
      switch (dayTypeStr) {
        case 'push':
          dayType = SuggestedDayType.push;
          break;
        case 'pull':
          dayType = SuggestedDayType.pull;
          break;
        case 'legsCore':
          dayType = SuggestedDayType.legsCore;
          break;
        default:
          return null;
      }

      return SuggestedRoutine(
        minutes: minutes,
        dayType: dayType,
        exercises: exercises,
        message: (message != null && message.trim().isNotEmpty) ? message.trim() : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreSuggestedRoutineFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final lastMins = prefs.getInt(_prefsKeyLastSuggestedMinutes);
      if (lastMins != null && lastMins > 0) {
        _lastSuggestedMinutes = lastMins;
      }

      final raw = prefs.getString(_prefsKeySuggestedRoutine);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final routine = _routineFromJson(Map<String, dynamic>.from(decoded));
      if (!mounted) return;

      if (routine != null) {
        setState(() => _suggestedRoutine = routine);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _persistSuggestedRoutineToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyLastSuggestedMinutes, _lastSuggestedMinutes);

      final r = _suggestedRoutine;
      if (r == null) {
        await prefs.remove(_prefsKeySuggestedRoutine);
        return;
      }

      final raw = jsonEncode(_routineToJson(r));
      await prefs.setString(_prefsKeySuggestedRoutine, raw);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _clearSuggestedRoutinePersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeySuggestedRoutine);
    } catch (_) {
      // ignore
    }
  }

  // ===================== open exercise session from suggestion =====================

  Future<void> _openExerciseSessionFromSuggestion(Map<String, dynamic> ex) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExerciseSessionPage(exercise: ex)),
    );

    if (!mounted) return;
    await _loadRecentExercises(); // keep summary updated
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
      final row = await supabase
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();
      final name = (row?['username'] ?? '').toString().trim();
      if (name.isNotEmpty) _username = name;
    } catch (_) {}
  }

  String _shareHandle() {
    final u = (_username ?? '').trim();
    if (u.isEmpty) return '@user';
    return u.startsWith('@') ? u : '@$u';
  }

  // ---------------- Summary logic ----------------

  bool _isLegsGroup(String group) => group.trim().toLowerCase() == 'legs';
  bool _isCoreGroup(String group) => group.trim().toLowerCase() == 'core';

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
                      Text('${selected.length}/${entries.length}',
                          style: Theme.of(context).textTheme.bodySmall),
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
        final Map<String, dynamic> ex = exJoined is Map
            ? Map<String, dynamic>.from(exJoined)
            : (exJoined is List && exJoined.isNotEmpty)
                ? Map<String, dynamic>.from(exJoined.first as Map)
                : <String, dynamic>{};

        if (ex.isEmpty) continue;

        uniqueExercisesByDay.putIfAbsent(day, () => {});
        setCountsByDayByName.putIfAbsent(day, () => {});
        legsVolumeByDay.putIfAbsent(day, () => 0.0);
        coreVolumeByDay.putIfAbsent(day, () => 0.0);

        uniqueExercisesByDay[day]![ex['id'].toString()] = ex;

        final exName = (ex['name'] ?? '').toString().trim();
        if (exName.isNotEmpty) {
          setCountsByDayByName[day]![exName] = (setCountsByDayByName[day]![exName] ?? 0) + 1;
        }

        final mg = (ex['primary_muscle_group'] ?? '').toString();
        if (_isLegsGroup(mg)) legsVolumeByDay[day] = (legsVolumeByDay[day] ?? 0.0) + sessionVolume;
        if (_isCoreGroup(mg)) coreVolumeByDay[day] = (coreVolumeByDay[day] ?? 0.0) + sessionVolume;
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
            label = (legsVol >= coreVol) ? 'Legs' : 'Core';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load workouts: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ===================== Suggest routine UI =====================

  String _suggestedLabel(SuggestedDayType t) {
    switch (t) {
      case SuggestedDayType.push:
        return 'Push';
      case SuggestedDayType.pull:
        return 'Pull';
      case SuggestedDayType.legsCore:
        return 'Legs/Core';
    }
  }

  String _choiceLabel(SuggestedDayTypeChoice c) {
    switch (c) {
      case SuggestedDayTypeChoice.auto:
        return 'Auto (Rotate)';
      case SuggestedDayTypeChoice.push:
        return 'Push';
      case SuggestedDayTypeChoice.pull:
        return 'Pull';
      case SuggestedDayTypeChoice.legsCore:
        return 'Legs/Core';
    }
  }

  Future<void> _openSuggestRoutineDialog() async {
    final minutesController = TextEditingController(text: _lastSuggestedMinutes.toString());
    SuggestedDayTypeChoice choice = _defaultChoice;

    final res = await showDialog<_SuggestDialogResult>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Suggest routine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Workout length (minutes)',
                hintText: 'e.g. 30',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SuggestedDayTypeChoice>(
              value: choice,
              decoration: const InputDecoration(
                labelText: 'Day type',
                border: OutlineInputBorder(),
              ),
              items: SuggestedDayTypeChoice.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(_choiceLabel(c))))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                choice = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(minutesController.text.trim());
              if (m == null || m <= 0) return;
              Navigator.pop(context, _SuggestDialogResult(minutes: m, choice: choice));
            },
            child: const Text('Suggest'),
          ),
        ],
      ),
    );

    if (res == null) return;
    _lastSuggestedMinutes = res.minutes;
    await _persistSuggestedRoutineToPrefs();

    await _buildSuggestedRoutine(minutes: res.minutes, choice: res.choice, randomize: false);
  }

  Future<void> _buildSuggestedRoutine({
    required int minutes,
    required SuggestedDayTypeChoice choice,
    required bool randomize,
  }) async {
    if (_isSuggesting) return;

    setState(() => _isSuggesting = true);

    try {
      final fixedType = randomize ? _suggestedRoutine?.dayType : null;

      final routine = await _suggestionService.buildRoutine(
        minutes: minutes,
        choice: choice,
        randomize: randomize,
        fixedDayTypeForRandomize: fixedType,
      );

      if (!mounted) return;
      setState(() => _suggestedRoutine = routine);

      // ✅ Persist after any change
      await _persistSuggestedRoutineToPrefs();

      if (routine.exercises.isEmpty && routine.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(routine.message!)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to build suggestion: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  Future<void> _confirmAndClearSuggestedRoutine() async {
    final hasRoutine = _suggestedRoutine != null;
    if (!hasRoutine) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove suggested routine?'),
        content: const Text(
          'This will clear your current suggested routine. You can always generate another later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _suggestedRoutine = null);
    await _clearSuggestedRoutinePersisted();
  }

  Future<bool> _handleBackPressedWithWarning() async {
    // If there's an active suggested routine, warn once per app session.
    if (_suggestedRoutine != null && !_didShowCloseWarningThisSession) {
      _didShowCloseWarningThisSession = true;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Careful—don’t lose your routine'),
          content: const Text(
            'If you close the app mid-workout, your suggested routine might not be shown again unless it’s saved. '
            'Good news: Fit Quest now saves your current suggestion automatically.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
          ],
        ),
      );

      // Don’t block the back action permanently; after warning, allow normal behavior.
      // Persist just in case.
      await _persistSuggestedRoutineToPrefs();
    }

    return true; // allow pop
  }

  Widget _buildSuggestedRoutineCard() {
    final s = _suggestedRoutine;
    if (s == null) return const SizedBox.shrink();

    final title = _suggestedLabel(s.dayType);
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
                const Icon(Icons.casino), // you can swap this to a custom icon later
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
                  onPressed: _confirmAndClearSuggestedRoutine,
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
                onPressed: _isSuggesting || s.exercises.isEmpty
                    ? null
                    : () async {
                        await _buildSuggestedRoutine(
                          minutes: s.minutes,
                          choice: SuggestedDayTypeChoice.auto, // ignored during randomize; type stays fixed
                          randomize: true,
                        );
                      },
              ),
            ),
            const SizedBox(height: 10),
            if (s.exercises.isEmpty)
              Text(s.message ?? 'No suggestions available.')
            else
              ...s.exercises.map((ex) {
                final name = (ex['name'] ?? '').toString();
                final mg = (ex['primary_muscle_group'] ?? '').toString();
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
                            equipmentName.isEmpty ? '$name ($mg)' : '$name ($mg)  •  $equipmentName',
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

    // Wrap entire page in a PopScope to show a warning once when leaving.
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        // onPopInvoked runs after the pop attempt; for a "before pop" warning,
        // we handle it by showing a dialog once (non-blocking) and persisting state.
        if (!didPop) return;
        await _handleBackPressedWithWarning();
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
                  onPressed: _isSuggesting ? null : _openSuggestRoutineDialog,
                  icon: _isSuggesting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.casino),
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

            _buildSuggestedRoutineCard(),
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

class _SuggestDialogResult {
  final int minutes;
  final SuggestedDayTypeChoice choice;

  _SuggestDialogResult({
    required this.minutes,
    required this.choice,
  });
}
