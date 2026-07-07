// lib/services/suggestion_service.dart
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

enum SuggestedDayType { push, pull, legsCore }

enum SuggestedDayTypeChoice { auto, push, pull, legsCore }

class SuggestedRoutine {
  final SuggestedDayType dayType;
  final int minutes;
  final List<Map<String, dynamic>> exercises;
  final String? message;

  const SuggestedRoutine({
    required this.dayType,
    required this.minutes,
    required this.exercises,
    this.message,
  });
}

class SuggestionService {
  final SupabaseClient supabase;

  SuggestionService(this.supabase);

  // ---------- Public API ----------

  Future<SuggestedRoutine> buildRoutine({
    required int minutes,
    required SuggestedDayTypeChoice choice,
    required bool randomize,
    SuggestedDayType? fixedDayTypeForRandomize,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const SuggestedRoutine(
        dayType: SuggestedDayType.push,
        minutes: 0,
        exercises: [],
        message: 'You must be logged in.',
      );
    }

    final totalExercisesTarget = (minutes ~/ 5).clamp(1, 100);

    // Determine day type (rotation or user-selected).
    final SuggestedDayType dayType =
        (randomize && fixedDayTypeForRandomize != null)
        ? fixedDayTypeForRandomize
        : await _resolveSuggestedDayType(choice);

    final sessionsWindow = await _loadRecentSessionsWindow(user.id, days: 120);

    // Exclude exercises used on the most recent day of this same day type.
    final DateTime? lastSameTypeDay = _mostRecentDayForTypeFromSessions(
      sessionsWindow,
      dayType,
    );

    final Set<String> excludeIds = <String>{};
    if (lastSameTypeDay != null) {
      excludeIds.addAll(
        _exerciseIdsUsedOnLocalDay(sessionsWindow, lastSameTypeDay),
      );
    }

    final exerciseType = _suggestedDayTypeToExerciseType(dayType);
    final desiredGroups = _balancedMuscleGroupsForRoutine(
      dayType: dayType,
      exerciseCount: totalExercisesTarget,
    );

    if (desiredGroups.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message: 'No suggestions available.',
      );
    }

    final candidatesByGroup = <String, List<Map<String, dynamic>>>{};
    for (final group in desiredGroups.toSet()) {
      candidatesByGroup[group] = await _loadReplacementCandidates(
        muscleGroup: group,
        exerciseType: exerciseType,
        excludeIds: excludeIds,
      );
    }

    final usedIds = <String>{};
    final picked = <Map<String, dynamic>>[];

    for (final group in desiredGroups) {
      final candidates = List<Map<String, dynamic>>.from(
        candidatesByGroup[group] ?? const [],
      );

      if (randomize && candidates.length > 1) {
        _softShuffleCandidates(candidates);
      }

      Map<String, dynamic>? selected;
      for (final candidate in candidates) {
        final id = (candidate['id'] ?? '').toString();
        if (id.trim().isEmpty || usedIds.contains(id)) continue;

        selected = Map<String, dynamic>.from(candidate);
        usedIds.add(id);
        break;
      }

      if (selected != null) picked.add(selected);
    }

    // If exclusions left the routine short, fill from equipment exercises in the
    // correct day type while keeping the same no-duplicates rule.
    if (picked.length < totalExercisesTarget) {
      final fallbackCandidates = <Map<String, dynamic>>[];
      for (final group in desiredGroups.toSet()) {
        fallbackCandidates.addAll(
          await _loadReplacementCandidates(
            muscleGroup: group,
            exerciseType: exerciseType,
          ),
        );
      }

      if (randomize && fallbackCandidates.length > 1) {
        _softShuffleCandidates(fallbackCandidates);
      }

      for (final candidate in fallbackCandidates) {
        if (picked.length >= totalExercisesTarget) break;

        final id = (candidate['id'] ?? '').toString();
        if (id.trim().isEmpty || usedIds.contains(id)) continue;

        picked.add(Map<String, dynamic>.from(candidate));
        usedIds.add(id);
      }
    }

    final finalPicked = picked.take(totalExercisesTarget).toList();

    if (finalPicked.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message: 'No suggestions available.',
      );
    }

    return SuggestedRoutine(
      dayType: dayType,
      minutes: minutes,
      exercises: finalPicked,
      message: null,
    );
  }

  Future<SuggestedRoutine> rebalancePushPullRoutineByMuscleGroup(
    SuggestedRoutine routine,
  ) async {
    if (routine.exercises.isEmpty) return routine;
    if (routine.dayType != SuggestedDayType.push &&
        routine.dayType != SuggestedDayType.pull) {
      return routine;
    }

    final exerciseType = _suggestedDayTypeToExerciseType(routine.dayType);
    if (exerciseType.isEmpty) return routine;

    final desiredGroups = _balancedMuscleGroupsForRoutine(
      dayType: routine.dayType,
      exerciseCount: routine.exercises.length,
    );
    if (desiredGroups.isEmpty) return routine;

    final candidatesByGroup = <String, List<Map<String, dynamic>>>{};
    for (final group in desiredGroups.toSet()) {
      candidatesByGroup[group] = await _loadReplacementCandidates(
        muscleGroup: group,
        exerciseType: exerciseType,
      );
    }

    final usedIds = <String>{};
    final balancedExercises = <Map<String, dynamic>>[];

    for (final group in desiredGroups) {
      final candidates = candidatesByGroup[group] ?? <Map<String, dynamic>>[];
      Map<String, dynamic>? picked;

      for (final candidate in candidates) {
        final id = (candidate['id'] ?? '').toString();
        if (id.trim().isEmpty || usedIds.contains(id)) continue;
        picked = Map<String, dynamic>.from(candidate);
        usedIds.add(id);
        break;
      }

      // If there are not enough unused exercises in this muscle group, only
      // keep the original slot if it already matches the desired group. This
      // prevents a shoulder slot from silently becoming back/arms.
      if (picked == null && routine.exercises.length > balancedExercises.length) {
        final original = Map<String, dynamic>.from(
          routine.exercises[balancedExercises.length],
        );
        final originalId = (original['id'] ?? '').toString();
        final originalGroup = _canonicalMuscleGroup(
          original['primary_muscle_group'],
        );

        if (originalGroup == group && !usedIds.contains(originalId)) {
          picked = original;
          if (originalId.trim().isNotEmpty) usedIds.add(originalId);
        }
      }

      if (picked != null) balancedExercises.add(picked);
    }

    if (balancedExercises.isEmpty) return routine;

    return SuggestedRoutine(
      minutes: routine.minutes,
      dayType: routine.dayType,
      exercises: balancedExercises,
      message: routine.message,
    );
  }

  Future<SuggestedRoutine> randomizeExerciseInRoutine({
    required SuggestedRoutine routine,
    required int index,
    required Map<String, Set<String>> individualRandomizeHistoryBySlot,
  }) async {
    if (index < 0 || index >= routine.exercises.length) return routine;

    final currentExercise = routine.exercises[index];
    final currentExerciseId = (currentExercise['id'] ?? '').toString();

    final desiredSlotMuscleGroup = desiredMuscleGroupForRoutineSlot(
      routine: routine,
      index: index,
    );
    final currentMuscleGroup = desiredSlotMuscleGroup.isNotEmpty
        ? desiredSlotMuscleGroup
        : _canonicalMuscleGroup(currentExercise['primary_muscle_group']);

    final currentExerciseType = (currentExercise['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final fallbackExerciseType = _suggestedDayTypeToExerciseType(
      routine.dayType,
    );
    final exerciseType = currentExerciseType.isNotEmpty
        ? currentExerciseType
        : fallbackExerciseType;

    if (currentMuscleGroup.isEmpty || exerciseType.isEmpty) return routine;

    final candidates = await _loadReplacementCandidates(
      muscleGroup: currentMuscleGroup,
      exerciseType: exerciseType,
    );

    final existingIds = routine.exercises.asMap().entries
        .where((entry) => entry.key != index)
        .map((entry) => (entry.value['id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    final historyKey = individualRandomizeHistoryKey(
      dayType: routine.dayType,
      index: index,
      muscleGroup: currentMuscleGroup,
      exerciseType: exerciseType,
    );

    final usedIds = individualRandomizeHistoryBySlot.putIfAbsent(
      historyKey,
      () => <String>{},
    );

    if (currentExerciseId.trim().isNotEmpty) usedIds.add(currentExerciseId);

    List<Map<String, dynamic>> available = candidates.where((candidate) {
      final candidateId = (candidate['id'] ?? '').toString();
      if (candidateId.trim().isEmpty) return false;
      if (candidateId == currentExerciseId) return false;
      if (existingIds.contains(candidateId)) return false;
      if (usedIds.contains(candidateId)) return false;
      return true;
    }).toList();

    // Once every valid replacement has been shown, start a new cycle while
    // still avoiding the current exercise and duplicates already in the routine.
    if (available.isEmpty) {
      usedIds.clear();
      if (currentExerciseId.trim().isNotEmpty) usedIds.add(currentExerciseId);

      available = candidates.where((candidate) {
        final candidateId = (candidate['id'] ?? '').toString();
        if (candidateId.trim().isEmpty) return false;
        if (candidateId == currentExerciseId) return false;
        if (existingIds.contains(candidateId)) return false;
        return true;
      }).toList();
    }

    if (available.isEmpty) return routine;

    final replacement = Map<String, dynamic>.from(available.first);
    final replacementId = (replacement['id'] ?? '').toString();
    if (replacementId.trim().isNotEmpty) usedIds.add(replacementId);

    final updatedExercises = routine.exercises
        .map((ex) => Map<String, dynamic>.from(ex))
        .toList();
    updatedExercises[index] = replacement;

    return SuggestedRoutine(
      minutes: routine.minutes,
      dayType: routine.dayType,
      exercises: updatedExercises,
      message: routine.message,
    );
  }

  String individualRandomizeHistoryKey({
    required SuggestedDayType dayType,
    required int index,
    required String muscleGroup,
    required String exerciseType,
  }) {
    return '${dayType.name}:$index:$exerciseType:$muscleGroup';
  }

  String desiredMuscleGroupForRoutineSlot({
    required SuggestedRoutine routine,
    required int index,
  }) {
    final desiredGroups = _balancedMuscleGroupsForRoutine(
      dayType: routine.dayType,
      exerciseCount: routine.exercises.length,
    );

    if (index >= 0 && index < desiredGroups.length) {
      return desiredGroups[index];
    }

    if (index >= 0 && index < routine.exercises.length) {
      return _canonicalMuscleGroup(
        routine.exercises[index]['primary_muscle_group'],
      );
    }

    return '';
  }

  String canonicalMuscleGroup(dynamic value) => _canonicalMuscleGroup(value);

  bool muscleGroupsMatch(dynamic a, dynamic b) {
    final left = _canonicalMuscleGroup(a);
    final right = _canonicalMuscleGroup(b);
    return left.isNotEmpty && left == right;
  }

  // ---------- Day type rotation / override ----------

  Future<SuggestedDayType> _resolveSuggestedDayType(
    SuggestedDayTypeChoice choice,
  ) async {
    switch (choice) {
      case SuggestedDayTypeChoice.push:
        return SuggestedDayType.push;
      case SuggestedDayTypeChoice.pull:
        return SuggestedDayType.pull;
      case SuggestedDayTypeChoice.legsCore:
        return SuggestedDayType.legsCore;
      case SuggestedDayTypeChoice.auto:
        final user = supabase.auth.currentUser;
        if (user == null) return SuggestedDayType.push;

        final sessionsWindow = await _loadRecentSessionsWindow(
          user.id,
          days: 120,
        );
        final lastType = _lastCompletedTypeFromSessions(sessionsWindow);
        return _nextRotationType(lastType);
    }
  }

  SuggestedDayType _nextRotationType(SuggestedDayType last) {
    switch (last) {
      case SuggestedDayType.push:
        return SuggestedDayType.pull;
      case SuggestedDayType.pull:
        return SuggestedDayType.legsCore;
      case SuggestedDayType.legsCore:
        return SuggestedDayType.push;
    }
  }

  List<String> _groupsForDayType(SuggestedDayType t) {
    switch (t) {
      case SuggestedDayType.push:
        return const ['chest', 'shoulders', 'arms'];
      case SuggestedDayType.pull:
        return const ['back', 'shoulders', 'arms'];
      case SuggestedDayType.legsCore:
        return const ['legs', 'core'];
    }
  }

  String _suggestedDayTypeToExerciseType(SuggestedDayType dayType) {
    switch (dayType) {
      case SuggestedDayType.push:
        return 'push';
      case SuggestedDayType.pull:
        return 'pull';
      case SuggestedDayType.legsCore:
        return '';
    }
  }

  List<String> _balancedMuscleGroupsForRoutine({
    required SuggestedDayType dayType,
    required int exerciseCount,
  }) {
    if (exerciseCount <= 0) return <String>[];

    final groups = _groupsForDayType(dayType);
    if (groups.isEmpty) return <String>[];

    final baseCount = exerciseCount ~/ groups.length;
    var remainder = exerciseCount % groups.length;
    final result = <String>[];

    // Keep the same grouped layout the original push day used:
    // chest/back first, then shoulders/core, then arms. Extra exercises go to
    // earlier groups first, so 8 upper-body exercises becomes 3 / 3 / 2.
    for (final group in groups) {
      final countForGroup = baseCount + (remainder > 0 ? 1 : 0);
      if (remainder > 0) remainder--;
      for (var i = 0; i < countForGroup; i++) {
        result.add(group);
      }
    }

    return result;
  }

  // ---------- Candidate loading / priority ----------

  Future<Map<String, dynamic>> _loadExerciseHistoryForCandidates({
    required Set<String> candidateIds,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null || candidateIds.isEmpty) {
      return {
        'lastCompletedByExerciseId': <String, DateTime>{},
      };
    }

    final sessionRows = await supabase
        .from('exercise_sessions')
        .select('created_at, exercises!inner(id)')
        .eq('user_id', user.id)
        .order('created_at', ascending: true);

    final lastCompletedByExerciseId = <String, DateTime>{};

    for (final row in sessionRows) {
      final session = Map<String, dynamic>.from(row as Map);
      final exJoined = session['exercises'];
      final Map<String, dynamic> ex = exJoined is Map
          ? Map<String, dynamic>.from(exJoined)
          : (exJoined is List && exJoined.isNotEmpty)
          ? Map<String, dynamic>.from(exJoined.first as Map)
          : <String, dynamic>{};

      final id = (ex['id'] ?? '').toString();
      if (id.isEmpty || !candidateIds.contains(id)) continue;

      final createdAtRaw = session['created_at'];
      if (createdAtRaw != null) {
        final createdAt = DateTime.tryParse(createdAtRaw.toString());
        if (createdAt != null) lastCompletedByExerciseId[id] = createdAt;
      }
    }

    return {
      'lastCompletedByExerciseId': lastCompletedByExerciseId,
    };
  }

  void _sortExercisesBySuggestionPriority(
    List<Map<String, dynamic>> candidates, {
    required Map<String, DateTime> lastCompletedByExerciseId,
  }) {
    candidates.sort((a, b) {
      final aId = (a['id'] ?? '').toString();
      final bId = (b['id'] ?? '').toString();

      final aLast = lastCompletedByExerciseId[aId];
      final bLast = lastCompletedByExerciseId[bId];

      // Never completed exercises have top priority.
      if (aLast == null && bLast != null) return -1;
      if (aLast != null && bLast == null) return 1;

      // Then choose the exercise completed the longest time ago.
      if (aLast != null && bLast != null) {
        final lastCompare = aLast.compareTo(bLast);
        if (lastCompare != 0) return lastCompare;
      }

      // Reps, weight, and set count are intentionally ignored. Any completed
      // session record counts the same. Name is only a stable tie-breaker.
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
  }

  void _softShuffleCandidates(List<Map<String, dynamic>> candidates) {
    // Keeps the least-recently-completed priority meaningful while still making
    // full-routine randomize feel different. It only shuffles within small
    // priority bands instead of ignoring completion history completely.
    final rng = Random(DateTime.now().microsecondsSinceEpoch);

    for (var start = 0; start < candidates.length; start += 3) {
      final end = min(start + 3, candidates.length);
      final band = candidates.sublist(start, end)..shuffle(rng);
      for (var i = 0; i < band.length; i++) {
        candidates[start + i] = band[i];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadReplacementCandidates({
    required String muscleGroup,
    required String exerciseType,
    Set<String> excludeIds = const <String>{},
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];

    final canonicalMuscleGroup = _canonicalMuscleGroup(muscleGroup);
    final normalizedExerciseType = exerciseType.trim().toLowerCase();

    if (canonicalMuscleGroup.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final dynamic exerciseRows = normalizedExerciseType.isEmpty
        ? await supabase
              .from('exercises')
              .select('''
                id,
                name,
                type,
                primary_muscle_group,
                equipment_id,
                video_url,
                equipment:equipment_id (
                  name,
                  kind
                )
              ''')
              .eq('user_id', user.id)
        : await supabase
              .from('exercises')
              .select('''
                id,
                name,
                type,
                primary_muscle_group,
                equipment_id,
                video_url,
                equipment:equipment_id (
                  name,
                  kind
                )
              ''')
              .eq('user_id', user.id)
              .eq('type', normalizedExerciseType);

    final candidates = <Map<String, dynamic>>[];

    for (final row in exerciseRows) {
      final ex = Map<String, dynamic>.from(row as Map);
      final id = (ex['id'] ?? '').toString();

      if (id.trim().isEmpty || excludeIds.contains(id)) continue;

      final equipment = ex['equipment'] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(ex['equipment'] as Map);

      // Only standalone equipment exercises are allowed in suggested routines.
      // Exercises that live inside a routine are intentionally excluded.
      if ((equipment['kind'] ?? '').toString().toLowerCase() != 'equipment') {
        continue;
      }

      ex['equipment_name'] = (equipment['name'] ?? '').toString();

      if (_canonicalMuscleGroup(ex['primary_muscle_group']) ==
          canonicalMuscleGroup) {
        candidates.add(ex);
      }
    }

    if (candidates.isEmpty) return candidates;

    final candidateIds = candidates
        .map((ex) => (ex['id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    final history = await _loadExerciseHistoryForCandidates(
      candidateIds: candidateIds,
    );

    _sortExercisesBySuggestionPriority(
      candidates,
      lastCompletedByExerciseId: Map<String, DateTime>.from(
        history['lastCompletedByExerciseId'] as Map,
      ),
    );

    return candidates;
  }

  // ---------- Muscle group helpers ----------

  String _canonicalMuscleGroup(dynamic value) {
    final mg = (value ?? '').toString().trim().toLowerCase();

    if (mg == 'shoulder' ||
        mg == 'shoulders' ||
        mg == 'delt' ||
        mg == 'delts' ||
        mg == 'deltoid' ||
        mg == 'deltoids') {
      return 'shoulders';
    }
    if (mg == 'arm' ||
        mg == 'arms' ||
        mg == 'bicep' ||
        mg == 'biceps' ||
        mg == 'tricep' ||
        mg == 'triceps' ||
        mg == 'forearm' ||
        mg == 'forearms') {
      return 'arms';
    }
    if (mg == 'chest' || mg == 'pec' || mg == 'pecs') return 'chest';
    if (mg == 'back' ||
        mg == 'lats' ||
        mg == 'lat' ||
        mg == 'trap' ||
        mg == 'traps') {
      return 'back';
    }
    if (mg == 'leg' || mg == 'legs') return 'legs';
    if (mg == 'core' || mg == 'abs' || mg == 'abdominals') return 'core';
    return mg;
  }

  // ---------- Session window helpers (used for type detection + exclusions) ----------

  String _dayKeyLocal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _toLocalDay(DateTime dtLocal) =>
      DateTime(dtLocal.year, dtLocal.month, dtLocal.day);

  Future<List<_SessionRow>> _loadRecentSessionsWindow(
    String userId, {
    required int days,
  }) async {
    final sinceUtc = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();

    final rowsRaw = await supabase
        .from('exercise_sessions')
        .select(
          'exercise_id, created_at, exercises!inner(type, primary_muscle_group)',
        )
        .eq('user_id', userId)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(rowsRaw as List);

    final out = <_SessionRow>[];

    for (final r in rows) {
      final exId = (r['exercise_id'] ?? '').toString();
      if (exId.isEmpty) continue;

      final dt = DateTime.tryParse((r['created_at'] ?? '').toString());
      if (dt == null) continue;

      // Joined exercises row sometimes comes as Map, sometimes List<Map>
      final exJoined = r['exercises'];
      final Map<String, dynamic> ex = exJoined is Map
          ? Map<String, dynamic>.from(exJoined)
          : (exJoined is List && exJoined.isNotEmpty && exJoined.first is Map)
          ? Map<String, dynamic>.from(exJoined.first as Map)
          : <String, dynamic>{};

      final type = (ex['type'] ?? '').toString().toLowerCase();
      final mg = (ex['primary_muscle_group'] ?? '').toString();

      out.add(
        _SessionRow(
          exerciseId: exId,
          createdAtLocal: dt.toLocal(),
          type: type,
          primaryMuscleGroup: mg,
        ),
      );
    }

    return out;
  }

  Set<String> _exerciseIdsUsedOnLocalDay(
    List<_SessionRow> sessions,
    DateTime dayLocal,
  ) {
    final target = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final ids = <String>{};

    for (final s in sessions) {
      final d = _toLocalDay(s.createdAtLocal);
      if (d == target) ids.add(s.exerciseId);
    }

    return ids;
  }

  SuggestedDayType _lastCompletedTypeFromSessions(List<_SessionRow> sessions) {
    if (sessions.isEmpty) return SuggestedDayType.push;

    // Find most recent local workout day
    final mostRecentLocalDay = _toLocalDay(sessions.first.createdAtLocal);

    // Aggregate that day's composition
    int push = 0;
    int pull = 0;
    int legsCore = 0;

    for (final s in sessions) {
      final d = _toLocalDay(s.createdAtLocal);
      if (d != mostRecentLocalDay) break;

      final mg = _canonicalMuscleGroup(s.primaryMuscleGroup);
      if (mg == 'legs' || mg == 'core') {
        legsCore++;
      } else {
        if (s.type == 'push') push++;
        if (s.type == 'pull') pull++;
      }
    }

    if (legsCore > 0) return SuggestedDayType.legsCore;
    return (pull > push) ? SuggestedDayType.pull : SuggestedDayType.push;
  }

  DateTime? _mostRecentDayForTypeFromSessions(
    List<_SessionRow> sessions,
    SuggestedDayType t,
  ) {
    if (sessions.isEmpty) return null;

    // Group by day key
    final Map<String, List<_SessionRow>> byDay = {};
    for (final s in sessions) {
      final dayKey = _dayKeyLocal(s.createdAtLocal);
      byDay.putIfAbsent(dayKey, () => []).add(s);
    }

    // Ordered unique days from newest to oldest (sessions are already ordered desc)
    final orderedDays = <DateTime>[];
    for (final s in sessions) {
      final d = _toLocalDay(s.createdAtLocal);
      if (orderedDays.isEmpty || orderedDays.last != d) {
        orderedDays.add(d);
      }
    }

    for (final day in orderedDays) {
      final key = _dayKeyLocal(day);
      final dayRows = byDay[key] ?? const [];

      final dayType = _classifyDayType(dayRows);
      if (dayType == t) return day;
    }

    return null;
  }

  SuggestedDayType _classifyDayType(List<_SessionRow> dayRows) {
    int push = 0;
    int pull = 0;
    int legsCore = 0;

    for (final s in dayRows) {
      final mg = _canonicalMuscleGroup(s.primaryMuscleGroup);
      if (mg == 'legs' || mg == 'core') {
        legsCore++;
      } else {
        if (s.type == 'push') push++;
        if (s.type == 'pull') pull++;
      }
    }

    if (legsCore > 0) return SuggestedDayType.legsCore;
    return (pull > push) ? SuggestedDayType.pull : SuggestedDayType.push;
  }
}

class _SessionRow {
  final String exerciseId;
  final DateTime createdAtLocal;
  final String type; // push/pull
  final String primaryMuscleGroup;

  _SessionRow({
    required this.exerciseId,
    required this.createdAtLocal,
    required this.type,
    required this.primaryMuscleGroup,
  });
}
