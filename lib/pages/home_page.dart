import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/suggestion_service.dart';
import '../services/friend_profile_service.dart';
import 'exercise_session_page.dart';
import 'friend_profile_page.dart';
import 'meal_tracker_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class DayWorkoutSummary {
  final DateTime day;
  final String userId;
  final String username;
  final bool isCurrentUser;
  final List<String> exerciseNames;
  final Map<String, int> exerciseSetCountsByName;
  final Map<String, int> muscleGroupCounts;
  final String dayTypeLabel;
  final int workoutDurationMinutes;
  final DateTime sortTime;

  DayWorkoutSummary({
    required this.day,
    required this.userId,
    required this.username,
    required this.isCurrentUser,
    required this.exerciseNames,
    required this.exerciseSetCountsByName,
    required this.muscleGroupCounts,
    required this.dayTypeLabel,
    required this.workoutDurationMinutes,
    required this.sortTime,
  });

  String get displayOwner {
    if (isCurrentUser) return 'You';
    final clean = username.trim();
    if (clean.isEmpty) return 'Friend';
    return clean.startsWith('@') ? clean : '@$clean';
  }
}


enum WorkoutFilter { all, push, pull, legs, core }

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  List<DayWorkoutSummary> workoutFeed = [];

  WorkoutFilter _selectedFilter = WorkoutFilter.all;
  bool _showFriends = true;

  final FriendProfileService _friendProfileService = FriendProfileService();

  bool _isSubmittingReport = false;
  final TextEditingController _reportController = TextEditingController();
  String _reportType = 'bug';

  String? _username;

  // -------- Suggestion state (minimal + clean) --------
  final SuggestedDayTypeChoice _defaultChoice = SuggestedDayTypeChoice.auto;
  SuggestedRoutine? _suggestedRoutine;
  bool _isSuggesting = false;
  int _lastSuggestedMinutes = 30;

  // Keeps individual exercise shuffles from repeating the same replacements
  // until every valid same-muscle replacement has been offered.
  final Map<String, Set<String>> _individualRandomizeHistoryBySlot = {};

  // ---------- Persisted suggestion ----------
  static const String _prefsKeySuggestedRoutine = 'home.suggested_routine.v1';
  static const String _prefsKeyLastSuggestedMinutes =
      'home.last_suggested_minutes.v1';

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
        message: (message != null && message.trim().isNotEmpty)
            ? message.trim()
            : null,
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
        final enrichedRoutine =
            await _suggestionService.enrichRoutineVideoAvailability(routine);

        if (!mounted) return;
        setState(() => _suggestedRoutine = enrichedRoutine);
        await _persistSuggestedRoutineToPrefs();
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

  Future<void> _openExerciseSessionFromSuggestion(
    Map<String, dynamic> ex,
  ) async {
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
                    DropdownMenuItem(
                      value: 'suggestion',
                      child: Text('Suggestion'),
                    ),
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
                onPressed: _isSubmittingReport
                    ? null
                    : () => Navigator.pop(context),
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
        const SnackBar(
          content: Text('You must be logged in to submit a report.'),
        ),
      );
      return;
    }

    final msg = _reportController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a message.')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit report: $e')));
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

  String? _workoutCategory({
    required String muscleGroup,
    required String type,
  }) {
    if (_isLegsGroup(muscleGroup)) return 'Legs';
    if (_isCoreGroup(muscleGroup)) return 'Core';

    switch (type.trim().toLowerCase()) {
      case 'push':
        return 'Push';
      case 'pull':
        return 'Pull';
      default:
        return null;
    }
  }

  String _dominantWorkoutType({
    required Map<String, int> exerciseCounts,
    required Map<String, double> volumeByType,
  }) {
    const categories = ['Push', 'Pull', 'Legs', 'Core'];

    var best = 'Push';
    var bestCount = -1;
    var bestVolume = -1.0;

    for (final category in categories) {
      final count = exerciseCounts[category] ?? 0;
      final volume = volumeByType[category] ?? 0.0;

      if (count > bestCount || (count == bestCount && volume > bestVolume)) {
        best = category;
        bestCount = count;
        bestVolume = volume;
      }
    }

    return best;
  }


  String _filterLabel(WorkoutFilter filter) {
    switch (filter) {
      case WorkoutFilter.all:
        return 'All';
      case WorkoutFilter.push:
        return 'Push';
      case WorkoutFilter.pull:
        return 'Pull';
      case WorkoutFilter.legs:
        return 'Legs';
      case WorkoutFilter.core:
        return 'Core';
    }
  }

  bool _matchesWorkoutFilter(DayWorkoutSummary summary) {
    if (_selectedFilter == WorkoutFilter.all) return true;

    final label = summary.dayTypeLabel.trim().toLowerCase();

    switch (_selectedFilter) {
      case WorkoutFilter.all:
        return true;
      case WorkoutFilter.push:
        return label == 'push';
      case WorkoutFilter.pull:
        return label == 'pull';
      case WorkoutFilter.legs:
        return label == 'legs';
      case WorkoutFilter.core:
        return label == 'core';
    }
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  List<DayWorkoutSummary> _workoutEntries() {
    final list = workoutFeed.where((summary) {
      if (!_showFriends && !summary.isCurrentUser) return false;
      return _matchesWorkoutFilter(summary);
    }).toList()
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

    return list;
  }

  String _buildShareText(
    List<DayWorkoutSummary> entries, {
    String? titleOverride,
  }) {
    final b = StringBuffer();

    final title =
        titleOverride ??
        (_selectedFilter == WorkoutFilter.all
            ? 'Fit Quest — Workout Summary for ${_shareHandle()}'
            : 'Fit Quest — ${_filterLabel(_selectedFilter)} Workout Summary for ${_shareHandle()}');
    b.writeln(title);
    b.writeln('');

    if (entries.isEmpty) {
      b.writeln('No workouts found.');
      return b.toString().trim();
    }

    for (final s in entries) {
      final date = s.day;

      final durationText = ' • ${s.workoutDurationMinutes} min';
      b.writeln('${_formatDate(date)}$durationText — ${s.dayTypeLabel}');

      final muscles = s.muscleGroupCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (muscles.isNotEmpty) {
        b.writeln(
          'Muscles: ${muscles.map((e) => '${e.key}(${e.value})').join(', ')}',
        );
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
    List<DayWorkoutSummary> entries, {
    String? subject,
  }) async {
    await _loadUsernameIfNeeded();
    final text = _buildShareText(entries);
    await Share.share(text, subject: subject ?? 'Workout Summary');
  }

  Future<void> _openSharePicker() async {
    final entries = _workoutEntries()
        .where((summary) => summary.isCurrentUser)
        .toList();
    if (entries.isEmpty) return;

    final selected = <DateTime>{};

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          void toggleAll(bool select) {
            setLocal(() {
              selected.clear();
              if (select) selected.addAll(entries.map((e) => e.day));
            });
          }

          return AlertDialog(
            title: const Text('Share workouts'),
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
                        final s = entries[i];
                        final day = s.day;

                        final isChecked = selected.contains(day);

                        final subtitleParts = <String>[];
                        if (s.exerciseNames.isNotEmpty) {
                          subtitleParts.add(
                            '${s.exerciseNames.length} exercises',
                          );
                        }
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
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _shareEntries(
                    entries,
                    subject: 'Workout Summary',
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
                        final picked = entries
                            .where((e) => selected.contains(e.day))
                            .toList();
                        Navigator.pop(context);
                        await _shareEntries(
                          picked,
                          subject: 'Workout Summary',
                        );
                      },
              ),
            ],
          );
        },
      ),
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

  DateTime? _friendRowCreatedAtLocal(Map<String, dynamic> row) {
    final value = row['created_at'];
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _friendRowMuscleGroup(Map<String, dynamic> row) {
    final value = row['primary_muscle_group'] ??
        row['muscle_group'] ??
        row['exercise_primary_muscle_group'] ??
        row['exercise_muscle_group'];
    return (value ?? '').toString();
  }

  String _friendRowType(Map<String, dynamic> row) {
    return (row['type'] ?? row['exercise_type'] ?? '').toString();
  }

  List<DayWorkoutSummary> _buildFriendWorkoutSummaries(
    FriendWorkoutFeedData friend,
  ) {
    final byDay = <DateTime, List<Map<String, dynamic>>>{};

    for (final row in friend.history) {
      final local = _friendRowCreatedAtLocal(row);
      if (local == null) continue;

      final day = DateTime(local.year, local.month, local.day);
      byDay.putIfAbsent(day, () => <Map<String, dynamic>>[]).add(row);
    }

    final summaries = <DayWorkoutSummary>[];

    for (final entry in byDay.entries) {
      final day = entry.key;
      final rows = entry.value;

      DateTime? first;
      DateTime? last;

      final setsByName = <String, int>{};
      final firstTimeByName = <String, DateTime>{};
      final firstRowByName = <String, Map<String, dynamic>>{};

      final volumeByType = <String, double>{
        'Push': 0,
        'Pull': 0,
        'Legs': 0,
        'Core': 0,
      };

      for (final row in rows) {
        final local = _friendRowCreatedAtLocal(row);

        if (local != null) {
          if (first == null || local.isBefore(first)) first = local;
          if (last == null || local.isAfter(last)) last = local;
        }

        final name = (row['exercise_name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          setsByName[name] = (setsByName[name] ?? 0) + 1;

          if (local != null) {
            final existing = firstTimeByName[name];
            if (existing == null || local.isBefore(existing)) {
              firstTimeByName[name] = local;
              firstRowByName[name] = row;
            }
          } else {
            firstRowByName.putIfAbsent(name, () => row);
          }
        }

        final mg = _friendRowMuscleGroup(row);
        final type = _friendRowType(row);
        final volume = _numToDouble(row['weight']) * _numToInt(row['reps']);
        final category = _workoutCategory(
          muscleGroup: mg,
          type: type,
        );

        if (category != null) {
          volumeByType[category] = (volumeByType[category] ?? 0) + volume;
        }
      }

      final names = setsByName.keys.toList()
        ..sort((a, b) {
          final aTime = firstTimeByName[a];
          final bTime = firstTimeByName[b];

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return aTime.compareTo(bTime);
        });

      final muscleCounts = <String, int>{};
      final exerciseCountsByType = <String, int>{
        'Push': 0,
        'Pull': 0,
        'Legs': 0,
        'Core': 0,
      };

      for (final name in names) {
        final row = firstRowByName[name];
        if (row == null) continue;

        final mg = _friendRowMuscleGroup(row);
        if (mg.trim().isNotEmpty) {
          muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;
        }

        final category = _workoutCategory(
          muscleGroup: mg,
          type: _friendRowType(row),
        );

        if (category != null) {
          exerciseCountsByType[category] =
              (exerciseCountsByType[category] ?? 0) + 1;
        }
      }

      final label = _dominantWorkoutType(
        exerciseCounts: exerciseCountsByType,
        volumeByType: volumeByType,
      );

      var durationMinutes = 0;
      if (first != null && last != null) {
        durationMinutes = last.difference(first).inMinutes;
        if (durationMinutes < 0) durationMinutes = 0;
      }

      summaries.add(
        DayWorkoutSummary(
          day: day,
          userId: friend.userId,
          username: friend.username,
          isCurrentUser: false,
          exerciseNames: names,
          exerciseSetCountsByName: setsByName,
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: label,
          workoutDurationMinutes: durationMinutes,
          sortTime: last ?? first ?? day,
        ),
      );
    }

    return summaries;
  }

  Future<void> _openFriendProfile(DayWorkoutSummary summary) async {
    if (summary.isCurrentUser || summary.userId.trim().isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfilePage(
          friendUserId: summary.userId,
          friendUsername: summary.username,
        ),
      ),
    );
  }

  Future<void> _openMealTracker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MealTrackerPage(),
      ),
    );
  }

  Future<void> _loadRecentExercises() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => workoutFeed = []);
        return;
      }

      await _loadUsernameIfNeeded();

      // Supabase limits the number of rows returned by a single request.
      // Because every logged set is stored as its own exercise_sessions row,
      // load the complete workout history in pages.
      final List<Map<String, dynamic>> sessions = [];
      const int pageSize = 1000;
      int from = 0;

      while (true) {
        final pageRaw = await supabase
            .from('exercise_sessions')
            .select(
              'created_at, weight, reps, exercises!inner(id, name, type, primary_muscle_group)',
            )
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .range(from, from + pageSize - 1);

        final page = (pageRaw as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();

        sessions.addAll(page);

        if (page.length < pageSize) {
          break;
        }

        from += pageSize;
      }

      final Set<DateTime> workoutDays = {};
      final Map<DateTime, Map<String, Map<String, dynamic>>>
      uniqueExercisesByDay = {};
      final Map<DateTime, Map<String, int>> setCountsByDayByName = {};
      final Map<DateTime, Map<String, DateTime>> firstSessionByExerciseByDay = {};
      final Map<DateTime, DateTime> firstSessionLocalByDay = {};
      final Map<DateTime, DateTime> lastSessionLocalByDay = {};
      final Map<DateTime, Map<String, double>> volumeByDayByType = {};

      for (final row in sessions) {
        final local = DateTime.parse(row['created_at']).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        workoutDays.add(day);

        final currentFirst = firstSessionLocalByDay[day];
        final currentLast = lastSessionLocalByDay[day];
        if (currentFirst == null || local.isBefore(currentFirst)) {
          firstSessionLocalByDay[day] = local;
        }
        if (currentLast == null || local.isAfter(currentLast)) {
          lastSessionLocalByDay[day] = local;
        }

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
        firstSessionByExerciseByDay.putIfAbsent(day, () => {});
        volumeByDayByType.putIfAbsent(
          day,
          () => <String, double>{
            'Push': 0,
            'Pull': 0,
            'Legs': 0,
            'Core': 0,
          },
        );

        final exerciseId = ex['id'].toString();
        uniqueExercisesByDay[day]![exerciseId] = ex;

        final existingFirstExerciseSession =
            firstSessionByExerciseByDay[day]![exerciseId];
        if (existingFirstExerciseSession == null ||
            local.isBefore(existingFirstExerciseSession)) {
          firstSessionByExerciseByDay[day]![exerciseId] = local;
        }

        final exName = (ex['name'] ?? '').toString().trim();
        if (exName.isNotEmpty) {
          setCountsByDayByName[day]![exName] =
              (setCountsByDayByName[day]![exName] ?? 0) + 1;
        }

        final mg = (ex['primary_muscle_group'] ?? '').toString();
        final type = (ex['type'] ?? '').toString();
        final category = _workoutCategory(
          muscleGroup: mg,
          type: type,
        );

        if (category != null) {
          volumeByDayByType[day]![category] =
              (volumeByDayByType[day]![category] ?? 0) + sessionVolume;
        }
      }

      final orderedUniqueDays = workoutDays.toList()
        ..sort((a, b) => b.compareTo(a));

      final List<DayWorkoutSummary> ownSummaries = [];

      for (final day in orderedUniqueDays) {
        final uniqueExercises = (uniqueExercisesByDay[day] ?? {}).values
            .toList()
          ..sort((a, b) {
            final aId = (a['id'] ?? '').toString();
            final bId = (b['id'] ?? '').toString();

            final aTime = firstSessionByExerciseByDay[day]?[aId];
            final bTime = firstSessionByExerciseByDay[day]?[bId];

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

        final names = uniqueExercises
            .map((e) => (e['name'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();

        final Map<String, int> muscleCounts = {};
        final exerciseCountsByType = <String, int>{
          'Push': 0,
          'Pull': 0,
          'Legs': 0,
          'Core': 0,
        };

        for (final e in uniqueExercises) {
          final mg = (e['primary_muscle_group'] ?? '').toString();
          if (mg.isNotEmpty) {
            muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;
          }

          final category = _workoutCategory(
            muscleGroup: mg,
            type: (e['type'] ?? '').toString(),
          );

          if (category != null) {
            exerciseCountsByType[category] =
                (exerciseCountsByType[category] ?? 0) + 1;
          }
        }

        final label = _dominantWorkoutType(
          exerciseCounts: exerciseCountsByType,
          volumeByType: volumeByDayByType[day] ?? const {},
        );

        int durationMin = 0;
        final first = firstSessionLocalByDay[day];
        final last = lastSessionLocalByDay[day];
        if (first != null && last != null) {
          durationMin = last.difference(first).inMinutes;
          if (durationMin < 0) durationMin = 0;
        }

        ownSummaries.add(
          DayWorkoutSummary(
            day: day,
            userId: user.id,
            username: _username ?? '',
            isCurrentUser: true,
            exerciseNames: names,
            exerciseSetCountsByName: Map<String, int>.from(
              setCountsByDayByName[day] ?? const {},
            ),
            muscleGroupCounts: muscleCounts,
            dayTypeLabel: label,
            workoutDurationMinutes: durationMin,
            sortTime: last ?? first ?? day,
          ),
        );
      }

      final friendFeed =
          await _friendProfileService.loadAcceptedFriendWorkoutFeed();

      final friendSummaries = <DayWorkoutSummary>[];
      for (final friend in friendFeed) {
        friendSummaries.addAll(_buildFriendWorkoutSummaries(friend));
      }

      final merged = <DayWorkoutSummary>[
        ...ownSummaries,
        ...friendSummaries,
      ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));

      if (!mounted) return;
      setState(() => workoutFeed = merged);
    } catch (e, st) {
      debugPrint('Error loading workout summary: $e');
      debugPrint('$st');
      if (!mounted) return;

      setState(() => workoutFeed = []);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load workouts: $e')));
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
    final minutesController = TextEditingController(
      text: _lastSuggestedMinutes.toString(),
    );
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
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(_choiceLabel(c)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                choice = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(minutesController.text.trim());
              if (m == null || m <= 0) return;
              Navigator.pop(
                context,
                _SuggestDialogResult(minutes: m, choice: choice),
              );
            },
            child: const Text('Suggest'),
          ),
        ],
      ),
    );

    if (res == null) return;
    _lastSuggestedMinutes = res.minutes;
    await _persistSuggestedRoutineToPrefs();

    await _buildSuggestedRoutine(
      minutes: res.minutes,
      choice: res.choice,
      randomize: false,
    );
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

      final enrichedRoutine =
          await _suggestionService.enrichRoutineVideoAvailability(routine);

      if (!mounted) return;
      _individualRandomizeHistoryBySlot.clear();
      setState(() => _suggestedRoutine = enrichedRoutine);

      // ✅ Persist after any change
      await _persistSuggestedRoutineToPrefs();

      if (enrichedRoutine.exercises.isEmpty &&
          enrichedRoutine.message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(enrichedRoutine.message!)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to build suggestion: $e')));
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }


  Future<void> _randomizeSuggestedExerciseAt(int index) async {
    final current = _suggestedRoutine;
    if (current == null || _isSuggesting) return;
    if (index < 0 || index >= current.exercises.length) return;

    final currentExerciseId = (current.exercises[index]['id'] ?? '').toString();

    setState(() => _isSuggesting = true);

    try {
      final updatedRoutine = await _suggestionService.randomizeExerciseInRoutine(
        routine: current,
        index: index,
        individualRandomizeHistoryBySlot: _individualRandomizeHistoryBySlot,
      );

      final enrichedRoutine =
          await _suggestionService.enrichRoutineVideoAvailability(
        updatedRoutine,
      );

      if (!mounted) return;

      final updatedExerciseId = index < enrichedRoutine.exercises.length
          ? (enrichedRoutine.exercises[index]['id'] ?? '').toString()
          : currentExerciseId;

      if (updatedExerciseId == currentExerciseId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No replacement exercise available for this muscle group.'),
          ),
        );
        return;
      }

      setState(() => _suggestedRoutine = enrichedRoutine);

      await _persistSuggestedRoutineToPrefs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to randomize exercise: $e')),
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );

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
                const Icon(Icons.casino),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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
                          choice: SuggestedDayTypeChoice
                              .auto, // ignored during randomize; type stays fixed
                          randomize: true,
                        );
                      },
              ),
            ),
            const SizedBox(height: 10),
            if (s.exercises.isEmpty)
              Text(s.message ?? 'No suggestions available.')
            else
              ...s.exercises.asMap().entries.map((entry) {
                final index = entry.key;
                final ex = entry.value;
                final name = (ex['name'] ?? '').toString();
                final mg = (ex['primary_muscle_group'] ?? '').toString();
                final equipmentName = (ex['equipment_name'] ?? '')
                    .toString()
                    .trim();
                final hasTrainerVideo =
                    ex['has_trainer_video'] == true;
                final hasUserVideo = ex['has_user_video'] == true;

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openExerciseSessionFromSuggestion(ex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Randomize this exercise',
                          onPressed: _isSuggesting
                              ? null
                              : () => _randomizeSuggestedExerciseAt(index),
                          icon: const Icon(Icons.shuffle, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        if (hasTrainerVideo) ...[
                          const Tooltip(
                            message: 'Trainer form video available',
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            equipmentName.isEmpty
                                ? '$name ($mg)'
                                : '$name ($mg)  •  $equipmentName',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (hasUserVideo) ...[
                          const Tooltip(
                            message: 'Your form video uploaded',
                            child: Icon(
                              Icons.person_pin_circle_rounded,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
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

  Widget _buildWorkoutFilterBar() {
    return Row(
      children: WorkoutFilter.values.map((filter) {
        final selected = _selectedFilter == filter;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                backgroundColor: selected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15)
                    : null,
                side: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                setState(() => _selectedFilter = filter);
              },
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _filterLabel(filter),
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w600,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFriendsToggle() {
    return Row(
      children: [
        const Icon(Icons.people_outline, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Show friends in workout summary',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Switch(
          value: _showFriends,
          onChanged: (value) {
            setState(() => _showFriends = value);
          },
        ),
      ],
    );
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    final entries = _workoutEntries();

    // ✅ BEFORE-pop handling: prevent pop, show warning once, then pop manually.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final allow = await _handleBackPressedWithWarning();
        if (!mounted) return;

        if (allow) {
          Navigator.of(context).pop(result);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Meal Tracker',
                  onPressed: _openMealTracker,
                  icon: const Icon(Icons.restaurant),
                ),
                IconButton(
                  tooltip: 'Suggest Routine',
                  onPressed: _isSuggesting ? null : _openSuggestRoutineDialog,
                  icon: _isSuggesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.casino),
                ),
                IconButton(
                  tooltip: 'Report a bug / suggestion',
                  onPressed: _isSubmittingReport ? null : _openReportDialog,
                  icon: const Icon(Icons.bug_report_outlined),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed:
                      entries.any((s) => s.isCurrentUser) ? _openSharePicker : null,
                  icon: const Icon(Icons.share),
                ),
              ],
            ),
            Text(
              'Workout Summary',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),

            _buildSuggestedRoutineCard(),
            if (_suggestedRoutine != null) const SizedBox(height: 12),

            _buildWorkoutFilterBar(),
            const SizedBox(height: 10),
            _buildFriendsToggle(),
            const SizedBox(height: 12),

            if (workoutFeed.isEmpty)
              const Text('No workouts logged yet.')
            else if (entries.isEmpty)
              const Text('No workouts match the current filters.')
            else
              ...entries.map((s) {
                final date = s.day;

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
                                Text(
                                  _formatDate(date),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${s.workoutDurationMinutes} min',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: s.isCurrentUser
                                ? Text(
                                    s.displayOwner,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  )
                                : InkWell(
                                    onTap: () => _openFriendProfile(s),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        s.displayOwner,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                      ),
                                    ),
                                  ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              s.dayTypeLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
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

  _SuggestDialogResult({required this.minutes, required this.choice});
}
