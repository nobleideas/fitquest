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

    // Load data needed for fairness + exclusions.
    final allExercises = await _loadMyExercises(user.id);
    if (allExercises.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message: 'No exercises found.',
      );
    }

    final sessionsWindow = await _loadRecentSessionsWindow(user.id, days: 120);

    // Exclude: exercises used on MOST RECENT day of this same type.
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

    // Fairness metric A: distinct local days in last 30 days
    final daysUsed30 = await _loadDaysUsed30ByExerciseId(user.id);

    // Tie-breaker: last performed time
    final lastPerformedById = _lastPerformedByExerciseIdFromSessions(
      sessionsWindow,
    );

    // Build pool per constraints.
    final pool = _buildEligiblePool(
      allExercises: allExercises,
      dayType: dayType,
      excludeIds: excludeIds,
    );

    if (pool.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message: 'No suggestions available.',
      );
    }

    // Group by canonical muscle group and decide how many to take from each group.
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final ex in pool) {
      final mg = _canonicalMuscleGroup(
        (ex['primary_muscle_group'] ?? '').toString(),
      );
      if (mg.isEmpty) continue;
      byGroup.putIfAbsent(mg, () => []).add(ex);
    }

    final groupsWanted = _groupsForDayType(dayType);
    final groupsAvailable = groupsWanted
        .where((g) => (byGroup[g]?.isNotEmpty ?? false))
        .toList();

    if (groupsAvailable.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message: 'No suggestions available.',
      );
    }

    // Distribute target roughly evenly across available groups.
    final base = totalExercisesTarget ~/ groupsAvailable.length;
    final rem = totalExercisesTarget % groupsAvailable.length;

    final takeCount = <String, int>{};
    for (int i = 0; i < groupsAvailable.length; i++) {
      takeCount[groupsAvailable[i]] = base + (i < rem ? 1 : 0);
    }

    // Pick exercises: fairness-first, randomize = weighted sampling (still fairness-biased).
    final picked = <Map<String, dynamic>>[];

    for (final g in groupsAvailable) {
      final list = List<Map<String, dynamic>>.from(byGroup[g] ?? const []);
      final need = takeCount[g] ?? 0;
      if (need <= 0 || list.isEmpty) continue;

      list.sort((a, b) => _compareFairA(a, b, daysUsed30, lastPerformedById));

      if (randomize) {
        picked.addAll(_weightedSampleNoReplace(list, need, daysUsed30));
      } else {
        picked.addAll(list.take(need));
      }
    }

    // Fill any remaining from the whole pool, still fairness-first / weighted.
    if (picked.length < totalExercisesTarget) {
      final already = picked
          .map((e) => (e['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      final remaining = pool.where((ex) {
        final id = (ex['id'] ?? '').toString();
        return id.isNotEmpty && !already.contains(id);
      }).toList();

      remaining.sort(
        (a, b) => _compareFairA(a, b, daysUsed30, lastPerformedById),
      );

      final need = totalExercisesTarget - picked.length;

      if (randomize) {
        picked.addAll(_weightedSampleNoReplace(remaining, need, daysUsed30));
      } else {
        picked.addAll(remaining.take(need));
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
        return const ['back', 'arms'];
      case SuggestedDayType.legsCore:
        return const ['legs', 'core'];
    }
  }

  // ---------- Fairness (A) ----------

  Future<Map<String, int>> _loadDaysUsed30ByExerciseId(String userId) async {
    final sinceUtc = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();

    final rowsRaw = await supabase
        .from('exercise_sessions')
        .select('exercise_id, created_at')
        .eq('user_id', userId)
        .gte('created_at', sinceUtc);

    final rows = List<Map<String, dynamic>>.from(rowsRaw as List);

    final Map<String, Set<String>> daySets = {};

    for (final r in rows) {
      final id = (r['exercise_id'] ?? '').toString();
      if (id.isEmpty) continue;

      final dt = DateTime.tryParse((r['created_at'] ?? '').toString());
      if (dt == null) continue;

      final local = dt.toLocal();
      final dayKey = _dayKeyLocal(local);

      daySets.putIfAbsent(id, () => <String>{}).add(dayKey);
    }

    return {for (final e in daySets.entries) e.key: e.value.length};
  }

  int _compareFairA(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    Map<String, int> daysUsed30,
    Map<String, DateTime> lastPerformed,
  ) {
    final aId = (a['id'] ?? '').toString();
    final bId = (b['id'] ?? '').toString();

    final aDays = daysUsed30[aId] ?? 0;
    final bDays = daysUsed30[bId] ?? 0;
    if (aDays != bDays) return aDays.compareTo(bDays);

    final never = DateTime.fromMillisecondsSinceEpoch(0);
    final aLast = lastPerformed[aId] ?? never;
    final bLast = lastPerformed[bId] ?? never;
    final t = aLast.compareTo(bLast);
    if (t != 0) return t;

    final an = (a['name'] ?? '').toString().toLowerCase();
    final bn = (b['name'] ?? '').toString().toLowerCase();
    return an.compareTo(bn);
  }

  // Weighted random: favors under-used in last 30 days.
  List<Map<String, dynamic>> _weightedSampleNoReplace(
    List<Map<String, dynamic>> items,
    int k,
    Map<String, int> daysUsed30,
  ) {
    final rng = Random(DateTime.now().microsecondsSinceEpoch);
    final pool = List<Map<String, dynamic>>.from(items);
    final out = <Map<String, dynamic>>[];

    while (out.length < k && pool.isNotEmpty) {
      final picked = _weightedPickOne(pool, daysUsed30, rng);
      if (picked == null) break;

      out.add(picked);
      final pickedId = (picked['id'] ?? '').toString();
      pool.removeWhere((e) => (e['id'] ?? '').toString() == pickedId);
    }

    return out;
  }

  Map<String, dynamic>? _weightedPickOne(
    List<Map<String, dynamic>> items,
    Map<String, int> daysUsed30,
    Random rng,
  ) {
    if (items.isEmpty) return null;

    double total = 0;
    final weights = <double>[];

    for (final ex in items) {
      final id = (ex['id'] ?? '').toString();
      final d = daysUsed30[id] ?? 0;

      // ✅ A: distinct workout-days distribution
      final w = 1.0 / (1.0 + d); // 0 days => 1.0, 4 days => 0.2
      weights.add(w);
      total += w;
    }

    var roll = rng.nextDouble() * total;
    for (int i = 0; i < items.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return items[i];
    }

    return items.last;
  }

  // ---------- Eligibility rules ----------

  List<Map<String, dynamic>> _buildEligiblePool({
    required List<Map<String, dynamic>> allExercises,
    required SuggestedDayType dayType,
    required Set<String> excludeIds,
  }) {
    final wantedGroups = _groupsForDayType(dayType);

    return allExercises.where((ex) {
      final id = (ex['id'] ?? '').toString();
      if (id.isEmpty) return false;
      if (excludeIds.contains(id)) return false;

      final name = (ex['name'] ?? '').toString().trim();
      if (name.isEmpty) return false;

      final mg = _canonicalMuscleGroup(
        (ex['primary_muscle_group'] ?? '').toString(),
      );
      if (!wantedGroups.contains(mg)) return false;

      // Push/Pull days must match "type" column.
      if (dayType == SuggestedDayType.push) {
        return (ex['type'] ?? '').toString().toLowerCase() == 'push';
      }
      if (dayType == SuggestedDayType.pull) {
        return (ex['type'] ?? '').toString().toLowerCase() == 'pull';
      }

      // Legs/Core day: muscle group only (type can be push/pull in your schema).
      return true;
    }).toList();
  }

  String _canonicalMuscleGroup(String mg) {
    final g = mg.trim().toLowerCase();

    if (g.isEmpty) {
      return '';
    }

    // Your exact values
    if (g == 'legs') {
      return 'legs';
    }

    if (g == 'core') {
      return 'core';
    }

    // Upper body mapping (you said: chest, shoulders, arms, back)
    if (g.contains('chest') || g.contains('pec')) {
      return 'chest';
    }

    if (g.contains('shoulder') || g.contains('delt')) {
      return 'shoulders';
    }

    if (g.contains('arm') ||
        g.contains('bicep') ||
        g.contains('tricep') ||
        g.contains('forearm')) {
      return 'arms';
    }

    if (g.contains('back') || g.contains('lat') || g.contains('trap')) {
      return 'back';
    }

    return g;
  }

  // ---------- Exercise loading ----------

  Future<List<Map<String, dynamic>>> _loadMyExercises(String userId) async {
    final rowsRaw = await supabase
        .from('exercises')
        .select(
          'id, name, type, primary_muscle_group, video_url, equipment:equipment_id(name)',
        )
        .eq('user_id', userId);

    final list = List<Map<String, dynamic>>.from(rowsRaw as List);

    for (final ex in list) {
      final equipment = ex['equipment'];
      if (equipment is Map) {
        ex['equipment_name'] = (equipment['name'] ?? '').toString();
      } else {
        ex['equipment_name'] = '';
      }
    }

    return list;
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

  Map<String, DateTime> _lastPerformedByExerciseIdFromSessions(
    List<_SessionRow> sessions,
  ) {
    final Map<String, DateTime> last = {};
    for (final s in sessions) {
      if (!last.containsKey(s.exerciseId)) {
        last[s.exerciseId] = s.createdAtLocal;
      }
    }
    return last;
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
