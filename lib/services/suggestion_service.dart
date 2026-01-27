import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SuggestedDayType { push, pull, legsCore }

enum SuggestedDayTypeChoice { auto, push, pull, legsCore }

class SuggestedRoutine {
  final SuggestedDayType dayType;
  final int minutes;
  final List<Map<String, dynamic>> exercises;

  /// If exercises is empty, this message explains why.
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

  // ---------------- Public API ----------------

  /// Builds a suggested routine.
  ///
  /// Rules:
  /// - targetExercises = max(1, minutes ~/ 5)
  /// - auto day type rotates Push -> Pull -> Legs/Core (based on most recent logged day)
  /// - STRICT: excludes exercises used on the most recent day of the same type
  /// - randomize: produces new combinations and tries to avoid repeating recent sets
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

    final targetExercises = max(1, minutes ~/ 5);

    // Day type
    final SuggestedDayType dayType = (randomize && fixedDayTypeForRandomize != null)
        ? fixedDayTypeForRandomize
        : await _resolveDayType(choice);

    // Strict exclusion: last day of this same type
    final excludeIds = await _loadExerciseIdsUsedOnMostRecentTypeDay(dayType);

    // Load exercises
    final all = await _loadMyExercisesWithEquipment(user.id);

    // Build pool for this type, applying exclusions
    final pool = _buildPoolForType(all, dayType, excludeIds);

    if (pool.isEmpty) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message:
            'No suggestions available.\n\nYou may have used all available ${_dayTypeLabel(dayType)} exercises on your last ${_dayTypeLabel(dayType)} day, or you may not have enough exercises saved yet.',
      );
    }

    // Split into groups and compute take counts
    final groupNames = _groupsForDayType(dayType);

    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final ex in pool) {
      final g = _canonicalGroup((ex['primary_muscle_group'] ?? '').toString());
      if (groupNames.contains(g)) {
        byGroup.putIfAbsent(g, () => []).add(ex);
      }
    }

    // If somehow group split is empty (odd data), treat as one group "all"
    final effectiveGroups = byGroup.isEmpty ? <String>['all'] : groupNames.where(byGroup.containsKey).toList();
    final takeCounts = _computeTakeCounts(targetExercises, effectiveGroups);

    final prefs = await SharedPreferences.getInstance();

    if (randomize) {
      // Randomize should create NEW SETS, not just shuffle order
      final result = await _pickRandomizedSetWithHistory(
        prefs: prefs,
        userId: user.id,
        dayType: dayType,
        byGroup: byGroup.isEmpty ? {'all': pool} : byGroup,
        effectiveGroups: effectiveGroups,
        takeCounts: takeCounts,
        targetExercises: targetExercises,
      );

      if (result.length < targetExercises) {
        return SuggestedRoutine(
          dayType: dayType,
          minutes: minutes,
          exercises: const [],
          message:
              'No suggestions available.\n\nNot enough eligible exercises after excluding your last ${_dayTypeLabel(dayType)} day.',
        );
      }

      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: result,
      );
    }

    // Non-randomize: EVEN rotation via persistent cursors (round-robin per group)
    final picked = <Map<String, dynamic>>[];
    for (final g in effectiveGroups) {
      final list = List<Map<String, dynamic>>.from((byGroup[g] ?? const []));

      if (list.isEmpty) continue;
      list.sort((a, b) => _name(a).compareTo(_name(b)));

      final need = takeCounts[g] ?? 0;
      if (need <= 0) continue;

      final cursorKey = _prefKeyCursor(user.id, dayType, g);
      final cursor = prefs.getInt(cursorKey) ?? 0;

      final taken = _takeRoundRobin(list, need, cursor);
      picked.addAll(taken.items);

      // advance cursor (mod list length)
      final nextCursor = list.isEmpty ? 0 : taken.nextCursor;
      await prefs.setInt(cursorKey, nextCursor);
    }

    // Fill remainder from pool (still strict exclusions apply)
    if (picked.length < targetExercises) {
      final already = picked.map((e) => (e['id'] ?? '').toString()).toSet();
      final remaining = pool.where((ex) {
        final id = (ex['id'] ?? '').toString();
        return id.isNotEmpty && !already.contains(id);
      }).toList();

      if (remaining.isEmpty) {
        return SuggestedRoutine(
          dayType: dayType,
          minutes: minutes,
          exercises: const [],
          message:
              'No suggestions available.\n\nNot enough eligible exercises after excluding your last ${_dayTypeLabel(dayType)} day.',
        );
      }

      remaining.sort((a, b) => _name(a).compareTo(_name(b)));

      // Use an "all" cursor so filler rotates too
      final cursorKey = _prefKeyCursor(user.id, dayType, 'all');
      final cursor = prefs.getInt(cursorKey) ?? 0;

      final need = targetExercises - picked.length;
      final taken = _takeRoundRobin(remaining, need, cursor);
      picked.addAll(taken.items);

      final nextCursor = remaining.isEmpty ? 0 : taken.nextCursor;
      await prefs.setInt(cursorKey, nextCursor);
    }

    if (picked.length < targetExercises) {
      return SuggestedRoutine(
        dayType: dayType,
        minutes: minutes,
        exercises: const [],
        message:
            'No suggestions available.\n\nNot enough eligible exercises after excluding your last ${_dayTypeLabel(dayType)} day.',
      );
    }

    return SuggestedRoutine(
      dayType: dayType,
      minutes: minutes,
      exercises: picked.take(targetExercises).toList(),
    );
  }

  // ---------------- Day type selection ----------------

  Future<SuggestedDayType> _resolveDayType(SuggestedDayTypeChoice choice) async {
    switch (choice) {
      case SuggestedDayTypeChoice.push:
        return SuggestedDayType.push;
      case SuggestedDayTypeChoice.pull:
        return SuggestedDayType.pull;
      case SuggestedDayTypeChoice.legsCore:
        return SuggestedDayType.legsCore;
      case SuggestedDayTypeChoice.auto:
        final last = await _lastCompletedCanonicalDayType();
        return _nextRotationType(last);
    }
  }

  Future<SuggestedDayType> _lastCompletedCanonicalDayType() async {
    // Find most recent local workout day overall and label it.
    final rows = await _loadRecentSessionsWithExerciseMeta(daysBack: 120);
    if (rows.isEmpty) return SuggestedDayType.push;

    // Group by local day and keep newest day
    final Map<String, _DayAgg> byDay = {};
    for (final r in rows) {
      final dt = DateTime.tryParse((r['created_at'] ?? '').toString());
      if (dt == null) continue;

      final local = dt.toLocal();
      final dayKey = _dayKeyLocal(local);

      final ex = (r['exercises'] is Map)
          ? Map<String, dynamic>.from(r['exercises'] as Map)
          : null;
      if (ex == null) continue;

      final exId = (ex['id'] ?? '').toString();
      if (exId.isEmpty) continue;

      final type = (ex['type'] ?? '').toString().toLowerCase();
      final mg = (ex['primary_muscle_group'] ?? '').toString().toLowerCase();

      byDay.putIfAbsent(dayKey, () => _DayAgg());
      byDay[dayKey]!.add(exId: exId, type: type, mg: mg);
    }

    if (byDay.isEmpty) return SuggestedDayType.push;

    final newestKey = (byDay.keys.toList()..sort((a, b) => b.compareTo(a))).first;
    final agg = byDay[newestKey]!;

    // If any legs/core present, call it legsCore
    if (agg.legsCount > 0 || agg.coreCount > 0) return SuggestedDayType.legsCore;

    // Else pull vs push based on unique exercises that day
    if (agg.pullCount > agg.pushCount) return SuggestedDayType.pull;
    return SuggestedDayType.push;
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

  // ---------------- Strict exclusion ----------------

  Future<Set<String>> _loadExerciseIdsUsedOnMostRecentTypeDay(SuggestedDayType type) async {
    // We only exclude the last SAME-TYPE day, per your requirement.
    final rows = await _loadRecentSessionsWithExerciseMeta(daysBack: 180);
    if (rows.isEmpty) return {};

    // Walk newest -> oldest, find first day that matches type, collect exercise_ids on that day.
    String? matchedDayKey;
    final ids = <String>{};

    for (final r in rows) {
      final dt = DateTime.tryParse((r['created_at'] ?? '').toString());
      if (dt == null) continue;

      final local = dt.toLocal();
      final dayKey = _dayKeyLocal(local);

      final ex = (r['exercises'] is Map)
          ? Map<String, dynamic>.from(r['exercises'] as Map)
          : null;
      if (ex == null) continue;

      final exId = (ex['id'] ?? '').toString();
      if (exId.isEmpty) continue;

      final exType = (ex['type'] ?? '').toString().toLowerCase();
      final mg = (ex['primary_muscle_group'] ?? '').toString().toLowerCase();

      final isTypeDay = _matchesTypeDay(type, exType, mg);

      if (matchedDayKey == null) {
        if (!isTypeDay) continue;
        matchedDayKey = dayKey;
      }

      // once matched, only collect from that same day
      if (dayKey != matchedDayKey) break;

      ids.add(exId);
    }

    return ids;
  }

  bool _matchesTypeDay(SuggestedDayType type, String exType, String mg) {
    switch (type) {
      case SuggestedDayType.push:
        return exType == 'push';
      case SuggestedDayType.pull:
        return exType == 'pull';
      case SuggestedDayType.legsCore:
        return mg == 'legs' || mg == 'core';
    }
  }

  // ---------------- Pool building ----------------

  List<Map<String, dynamic>> _buildPoolForType(
    List<Map<String, dynamic>> all,
    SuggestedDayType type,
    Set<String> excludeIds,
  ) {
    return all.where((ex) {
      final id = (ex['id'] ?? '').toString();
      if (id.isEmpty) return false;
      if (excludeIds.contains(id)) return false;

      final name = (ex['name'] ?? '').toString().trim();
      if (name.isEmpty) return false;

      final exType = (ex['type'] ?? '').toString().toLowerCase();
      final mg = (ex['primary_muscle_group'] ?? '').toString().toLowerCase();

      switch (type) {
        case SuggestedDayType.push:
          return exType == 'push' && (mg == 'chest' || mg == 'shoulders' || mg == 'arms');
        case SuggestedDayType.pull:
          return exType == 'pull' && (mg == 'back' || mg == 'arms');
        case SuggestedDayType.legsCore:
          return mg == 'legs' || mg == 'core';
      }
    }).toList();
  }

  // ---------------- Randomize: new sets + history ----------------

  Future<List<Map<String, dynamic>>> _pickRandomizedSetWithHistory({
    required SharedPreferences prefs,
    required String userId,
    required SuggestedDayType dayType,
    required Map<String, List<Map<String, dynamic>>> byGroup,
    required List<String> effectiveGroups,
    required Map<String, int> takeCounts,
    required int targetExercises,
  }) async {
    // Save last N suggestion "sets" to avoid immediate repetition
    const maxHistory = 10;
    const maxAttempts = 8;

    final historyKey = _prefKeyHistory(userId, dayType);
    final history = _readStringList(prefs, historyKey);

    final rng = Random(DateTime.now().microsecondsSinceEpoch);

    List<Map<String, dynamic>> best = const [];
    int bestScore = -1;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final candidate = <Map<String, dynamic>>[];

      for (final g in effectiveGroups) {
        final list = List<Map<String, dynamic>>.from(byGroup[g] ?? const []);
        if (list.isEmpty) continue;

        final need = takeCounts[g] ?? 0;
        if (need <= 0) continue;

        list.shuffle(rng);
        candidate.addAll(list.take(min(need, list.length)));
      }

      // Fill remainder from combined pool if needed
      if (candidate.length < targetExercises) {
        final already = candidate.map((e) => (e['id'] ?? '').toString()).toSet();

        final combined = <Map<String, dynamic>>[];
        for (final g in byGroup.keys) {
          combined.addAll(byGroup[g] ?? const []);
        }

        final remaining = combined.where((ex) {
          final id = (ex['id'] ?? '').toString();
          return id.isNotEmpty && !already.contains(id);
        }).toList();

        remaining.shuffle(rng);

        for (final ex in remaining) {
          if (candidate.length >= targetExercises) break;
          candidate.add(ex);
        }
      }

      if (candidate.length < targetExercises) {
        // Not enough options in this strict pool
        continue;
      }

      // Normalize signature = sorted ids joined
      final ids = candidate
          .map((e) => (e['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList()
        ..sort();
      final sig = ids.join('|');

      // score = how "new" is it vs history (0 = already seen)
      final isNew = !history.contains(sig);
      final score = isNew ? 100 : 0;

      if (score > bestScore) {
        bestScore = score;
        best = candidate.take(targetExercises).toList();
      }

      if (isNew) {
        // Write history and return immediately
        history.insert(0, sig);
        if (history.length > maxHistory) history.removeRange(maxHistory, history.length);
        await prefs.setString(historyKey, jsonEncode(history));
        return candidate.take(targetExercises).toList();
      }
    }

    // If we couldn't produce a new set, still return the best candidate we found (if any)
    if (best.isNotEmpty) return best.take(targetExercises).toList();

    return const [];
  }

  // ---------------- Even rotation: round-robin ----------------

  _RoundRobinResult _takeRoundRobin(List<Map<String, dynamic>> list, int need, int cursor) {
    if (list.isEmpty || need <= 0) return const _RoundRobinResult(items: [], nextCursor: 0);

    final n = list.length;
    final start = cursor % n;

    final items = <Map<String, dynamic>>[];
    int idx = start;

    for (int i = 0; i < need; i++) {
      items.add(list[idx]);
      idx = (idx + 1) % n;
      if (items.length >= n) break; // can't take more unique than list size
    }

    final nextCursor = (start + items.length) % n;
    return _RoundRobinResult(items: items, nextCursor: nextCursor);
  }

  // ---------------- Helpers ----------------

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

  Map<String, int> _computeTakeCounts(int total, List<String> groups) {
    if (groups.isEmpty) return {'all': total};

    final base = total ~/ groups.length;
    final rem = total % groups.length;

    final m = <String, int>{};
    for (int i = 0; i < groups.length; i++) {
      m[groups[i]] = base + (i < rem ? 1 : 0);
    }
    return m;
  }

  String _canonicalGroup(String mg) => mg.trim().toLowerCase();

  String _name(Map<String, dynamic> ex) =>
      ((ex['name'] ?? '').toString().toLowerCase());

  String _dayTypeLabel(SuggestedDayType t) {
    switch (t) {
      case SuggestedDayType.push:
        return 'Push';
      case SuggestedDayType.pull:
        return 'Pull';
      case SuggestedDayType.legsCore:
        return 'Legs/Core';
    }
  }

  // ---------------- Supabase loading ----------------

  Future<List<Map<String, dynamic>>> _loadMyExercisesWithEquipment(String userId) async {
    final rows = await supabase
        .from('exercises')
        .select('id, name, type, primary_muscle_group, video_url, equipment:equipment_id(name)')
        .eq('user_id', userId);

    final list = rows is List ? List<Map<String, dynamic>>.from(rows) : <Map<String, dynamic>>[];

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

  Future<List<Map<String, dynamic>>> _loadRecentSessionsWithExerciseMeta({required int daysBack}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final sinceUtc = DateTime.now().toUtc().subtract(Duration(days: daysBack)).toIso8601String();

    final rows = await supabase
        .from('exercise_sessions')
        .select('created_at, exercises!inner(id, type, primary_muscle_group)')
        .eq('user_id', user.id)
        .gte('created_at', sinceUtc)
        .order('created_at', ascending: false);

    return rows is List ? List<Map<String, dynamic>>.from(rows) : <Map<String, dynamic>>[];
  }

  // ---------------- Pref keys ----------------

  String _prefKeyCursor(String userId, SuggestedDayType t, String group) =>
      'suggest_cursor_v1_${userId}_${t.name}_$group';

  String _prefKeyHistory(String userId, SuggestedDayType t) =>
      'suggest_history_v1_${userId}_${t.name}';

  // ---------------- Pref list helpers ----------------

  List<String> _readStringList(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return <String>[];
  }

  String _dayKeyLocal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DayAgg {
  final Set<String> uniqueExerciseIds = {};
  int pushCount = 0;
  int pullCount = 0;
  int legsCount = 0;
  int coreCount = 0;

  void add({required String exId, required String type, required String mg}) {
    // Only count once per exercise per day (unique)
    if (uniqueExerciseIds.contains(exId)) return;
    uniqueExerciseIds.add(exId);

    if (type == 'push') pushCount++;
    if (type == 'pull') pullCount++;
    if (mg == 'legs') legsCount++;
    if (mg == 'core') coreCount++;
  }
}

class _RoundRobinResult {
  final List<Map<String, dynamic>> items;
  final int nextCursor;

  const _RoundRobinResult({
    required this.items,
    required this.nextCursor,
  });
}
