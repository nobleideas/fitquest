import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../services/equipment_service.dart';

class FriendProfilePage extends StatefulWidget {
  final String friendUserId;
  final String friendUsername;

  const FriendProfilePage({
    super.key,
    required this.friendUserId,
    required this.friendUsername,
  });

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late final TabController _tabController;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _equipment = []; // friend containers (equipment+routines)
  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  String _kindValue(Map<String, dynamic> item) {
    return (item['kind'] ?? 'equipment').toString().toLowerCase().trim();
  }

  List<Map<String, dynamic>> get _friendEquipmentOnly =>
      _equipment.where((e) => _kindValue(e) != 'routine').toList();

  List<Map<String, dynamic>> get _friendRoutinesOnly =>
      _equipment.where((e) => _kindValue(e) == 'routine').toList();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final friendId = widget.friendUserId;

      final results = await Future.wait<dynamic>([
        supabase.rpc(
          'get_friend_workout_history',
          params: {'friend_user_id': friendId, 'max_rows': 250},
        ),
        supabase.rpc(
          'get_friend_equipment',
          params: {'friend_user_id': friendId},
        ),
        supabase.rpc(
          'get_friend_exercises',
          params: {'friend_user_id': friendId},
        ),
      ]);

      final historyRaw = results[0];
      final equipmentRaw = results[1];
      final exercisesRaw = results[2];

      final history = historyRaw is List
          ? List<Map<String, dynamic>>.from(historyRaw)
          : <Map<String, dynamic>>[];
      final equipment = equipmentRaw is List
          ? List<Map<String, dynamic>>.from(equipmentRaw)
          : <Map<String, dynamic>>[];
      final exercises = exercisesRaw is List
          ? List<Map<String, dynamic>>.from(exercisesRaw)
          : <Map<String, dynamic>>[];

      setState(() {
        _history = history;
        _equipment = equipment;
        _exercises = exercises;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDateTime(dynamic ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts.toString());
    if (dt == null) return ts.toString();
    final local = dt.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh =
        (local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return "$m/$d/$y • $hh:$mm $ap";
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.friendUsername.isNotEmpty ? "@${widget.friendUsername}" : "Friend";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "History"),
            Tab(text: "Equipment"),
            Tab(text: "Routines"),
            Tab(text: "Exercises"),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _BlockedOrErrorView(
                  message:
                      "Couldn't load friend data.\n\nThis usually means you aren't accepted friends yet (or an RPC error occurred).\n\n$_error",
                  onRetry: _loadAll,
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _HistoryTab(history: _history, fmtDateTime: _fmtDateTime),

                    // Equipment tab (copies into kind='equipment')
                    _CopyableContainerTab(
                      titleSingular: 'equipment',
                      titlePlural: 'equipment',
                      emptyMessage: "No equipment found.",
                      leadingIcon: Icons.fitness_center,
                      friendContainers: _friendEquipmentOnly,
                      friendExercises: _exercises,
                      insertKind: 'equipment',
                    ),

                    // Routines tab (copies into kind='routine')
                    _CopyableContainerTab(
                      titleSingular: 'routine',
                      titlePlural: 'routines',
                      emptyMessage: "No routines found.",
                      leadingIcon: Icons.view_list,
                      friendContainers: _friendRoutinesOnly,
                      friendExercises: _exercises,
                      insertKind: 'routine',
                    ),

                    // Exercises tab (adds exercises to my equipment OR my routines)
                    _ExercisesTab(
                      exercises: _exercises,
                      friendEquipment: _equipment,
                    ),
                  ],
                ),
    );
  }
}

class _BlockedOrErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _BlockedOrErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

// ---------------- HISTORY TAB ----------------

enum _FriendHistoryView { summary, detailed }

class _FriendDayWorkoutSummary {
  final DateTime day;
  final List<String> exerciseNames;
  final Map<String, int> exerciseSetCountsByName;
  final Map<String, int> muscleGroupCounts;
  final String dayTypeLabel;
  final int workoutDurationMinutes;

  _FriendDayWorkoutSummary({
    required this.day,
    required this.exerciseNames,
    required this.exerciseSetCountsByName,
    required this.muscleGroupCounts,
    required this.dayTypeLabel,
    required this.workoutDurationMinutes,
  });
}

class _HistoryTab extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final String Function(dynamic) fmtDateTime;

  const _HistoryTab({required this.history, required this.fmtDateTime});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  _FriendHistoryView _view = _FriendHistoryView.summary;

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

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  String _rowMuscleGroup(Map<String, dynamic> row) {
    final v = row['primary_muscle_group'] ??
        row['muscle_group'] ??
        row['exercise_primary_muscle_group'] ??
        row['exercise_muscle_group'];
    return (v ?? '').toString();
  }

  String _rowType(Map<String, dynamic> row) {
    final v = row['type'] ?? row['exercise_type'];
    return (v ?? '').toString();
  }

  DateTime? _rowCreatedAtLocal(Map<String, dynamic> row) {
    final ts = row['created_at'];
    if (ts == null) return null;
    final dt = DateTime.tryParse(ts.toString());
    return dt?.toLocal();
  }

  List<_FriendDayWorkoutSummary> _buildSummaries() {
    final rows = widget.history;

    final Map<DateTime, List<Map<String, dynamic>>> byDay = {};
    for (final row in rows) {
      final local = _rowCreatedAtLocal(row);
      if (local == null) continue;
      final day = DateTime(local.year, local.month, local.day);
      byDay.putIfAbsent(day, () => []).add(row);
    }

    final summaries = <_FriendDayWorkoutSummary>[];

    for (final entry in byDay.entries) {
      final day = entry.key;
      final dayRows = entry.value;

      DateTime? first;
      DateTime? last;
      for (final r in dayRows) {
        final dt = _rowCreatedAtLocal(r);
        if (dt == null) continue;
        if (first == null || dt.isBefore(first)) first = dt;
        if (last == null || dt.isAfter(last)) last = dt;
      }
      int durationMin = 0;
      if (first != null && last != null) {
        durationMin = last.difference(first).inMinutes;
        if (durationMin < 0) durationMin = 0;
      }

      final Map<String, int> setsByName = {};
      for (final r in dayRows) {
        final name = (r['exercise_name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        setsByName[name] = (setsByName[name] ?? 0) + 1;
      }

      final names = setsByName.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      final Map<String, Map<String, dynamic>> firstRowByExerciseName = {};
      for (final r in dayRows) {
        final name = (r['exercise_name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        firstRowByExerciseName.putIfAbsent(name, () => r);
      }

      final Map<String, int> muscleCounts = {};
      int push = 0, pull = 0, legs = 0, core = 0;

      double legsVol = 0.0;
      double coreVol = 0.0;

      for (final exName in names) {
        final r = firstRowByExerciseName[exName];
        if (r == null) continue;

        final mg = _rowMuscleGroup(r);
        if (mg.trim().isNotEmpty) {
          muscleCounts[mg] = (muscleCounts[mg] ?? 0) + 1;
        }

        if (_isLegsGroup(mg)) legs++;
        if (_isCoreGroup(mg)) core++;

        final t = _rowType(r).trim().toLowerCase();
        if (t == 'push') push++;
        if (t == 'pull') pull++;
      }

      for (final r in dayRows) {
        final mg = _rowMuscleGroup(r);
        final vol = _numToDouble(r['weight']) * _numToInt(r['reps']);
        if (_isLegsGroup(mg)) legsVol += vol;
        if (_isCoreGroup(mg)) coreVol += vol;
      }

      String label;
      if (legs > 0 || core > 0) {
        if (legs > core) {
          label = 'Legs';
        } else if (core > legs) {
          label = 'Core';
        } else {
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

      summaries.add(
        _FriendDayWorkoutSummary(
          day: day,
          exerciseNames: names,
          exerciseSetCountsByName: setsByName,
          muscleGroupCounts: muscleCounts,
          dayTypeLabel: label,
          workoutDurationMinutes: durationMin,
        ),
      );
    }

    summaries.sort((a, b) => b.day.compareTo(a.day));
    return summaries;
  }

  Widget _buildToggleBar(BuildContext context) {
    final isSummary = _view == _FriendHistoryView.summary;
    final isDetailed = _view == _FriendHistoryView.detailed;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor:
                  isSummary ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : null,
              side: BorderSide(
                color: isSummary
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: isSummary ? null : () => setState(() => _view = _FriendHistoryView.summary),
            child: Text(
              'Workout Summary',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSummary ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              backgroundColor:
                  isDetailed ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : null,
              side: BorderSide(
                color: isDetailed
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed:
                isDetailed ? null : () => setState(() => _view = _FriendHistoryView.detailed),
            child: Text(
              'Detailed Sets',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDetailed ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryView(BuildContext context) {
    final summaries = _buildSummaries();

    if (summaries.isEmpty) {
      return const Center(child: Text("No workout history found."));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];

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
                        Text(_formatDate(s.day), style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text('${s.workoutDurationMinutes} min',
                            style: Theme.of(context).textTheme.bodySmall),
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
      },
    );
  }

  Widget _buildDetailedView(BuildContext context) {
    final history = widget.history;

    if (history.isEmpty) {
      return const Center(child: Text("No workout history found."));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = history[i];
        final exercise = (row['exercise_name'] ?? '').toString();
        final equipment = (row['equipment_name'] ?? '').toString();
        final weight = row['weight'];
        final reps = row['reps'];
        final when = widget.fmtDateTime(row['created_at']);

        return Card(
          child: ListTile(
            title: Text(exercise),
            subtitle: Text("$equipment\n$when"),
            isThreeLine: true,
            trailing: Text(
              "${weight ?? ''} x ${reps ?? ''}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: _buildToggleBar(context),
        ),
        Expanded(
          child: _view == _FriendHistoryView.summary ? _buildSummaryView(context) : _buildDetailedView(context),
        ),
      ],
    );
  }
}

// ---------------- EQUIPMENT/ROUTINES TAB (reusable copy tab) ----------------

enum _CopyMode { containerOnly, containerAndExercises }

class _CopyableContainerTab extends StatefulWidget {
  final String titleSingular; // "equipment" / "routine"
  final String titlePlural; // "equipment" / "routines"
  final String emptyMessage;
  final IconData leadingIcon;

  final List<Map<String, dynamic>> friendContainers;
  final List<Map<String, dynamic>> friendExercises;

  /// What kind to insert into MY equipment table ('equipment' or 'routine')
  final String insertKind;

  const _CopyableContainerTab({
    required this.titleSingular,
    required this.titlePlural,
    required this.emptyMessage,
    required this.leadingIcon,
    required this.friendContainers,
    required this.friendExercises,
    required this.insertKind,
  });

  @override
  State<_CopyableContainerTab> createState() => _CopyableContainerTabState();
}

class _CopyableContainerTabState extends State<_CopyableContainerTab> {
  final _equipmentService = EquipmentService();
  final supabase = Supabase.instance.client;

  bool _selectMode = false;
  final Set<int> _selectedIndexes = {};
  bool _isAdding = false;

  static const String _importedEquipmentName = 'Imported';

  // ---------- PRIMARY MUSCLE GROUP FILTER ----------
  static const List<String?> _muscleFiltersGrid = [
    'All',
    'Chest',
    'Shoulders',
    'Back',
    'Arms',
    'Legs',
    null,
    'Core',
    null,
  ];

  String _selectedMuscle = 'All';

  /// containerId -> set of muscle keys
  final Map<String, Set<String>> _containerMuscleGroups = {};

  @override
  void initState() {
    super.initState();
    _buildContainerMuscleMap();
  }

  @override
  void didUpdateWidget(covariant _CopyableContainerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.friendExercises != widget.friendExercises ||
        oldWidget.friendContainers != widget.friendContainers) {
      _buildContainerMuscleMap();
    }
  }

  String _normalizeMuscle(dynamic value) {
    final v = (value ?? '').toString().trim().toLowerCase();

    switch (v) {
      case 'shoulder':
      case 'shoulders':
        return 'shoulders';
      case 'arm':
      case 'arms':
        return 'arms';
      case 'leg':
      case 'legs':
        return 'legs';
      case 'chest':
        return 'chest';
      case 'back':
        return 'back';
      case 'core':
      case 'abs':
      case 'abdominals':
        return 'core';
      default:
        return v;
    }
  }

  String _selectedMuscleKey() => _normalizeMuscle(_selectedMuscle);

  String? _friendContainerId(Map<String, dynamic> c) {
    final s = (c['id'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _exerciseFriendContainerId(Map<String, dynamic> ex) {
    final s = (ex['equipment_id'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _exerciseVideoUrl(Map<String, dynamic> ex) {
    final s = (ex['video_url'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  void _buildContainerMuscleMap() {
    final map = <String, Set<String>>{};
    for (final ex in widget.friendExercises) {
      final containerId = _exerciseFriendContainerId(ex);
      if (containerId == null) continue;

      final mgRaw = ex['primary_muscle_group'];
      final mg = _normalizeMuscle(mgRaw);
      if (mg.isEmpty) continue;

      map.putIfAbsent(containerId, () => <String>{}).add(mg);
    }

    if (!mounted) return;
    setState(() {
      _containerMuscleGroups
        ..clear()
        ..addAll(map);
    });
  }

  List<int> get _visibleIndexes {
    if (_selectedMuscle == 'All') {
      return List.generate(widget.friendContainers.length, (i) => i);
    }

    final key = _selectedMuscleKey();
    final visible = <int>[];

    for (int i = 0; i < widget.friendContainers.length; i++) {
      final c = widget.friendContainers[i];
      final id = _friendContainerId(c);
      if (id == null) continue;

      final groups = _containerMuscleGroups[id];
      if (groups != null && groups.contains(key)) {
        visible.add(i);
      }
    }

    return visible;
  }

  void _enterSelectMode(int index) {
    setState(() {
      _selectMode = true;
      _selectedIndexes.add(index);
    });
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
        if (_selectedIndexes.isEmpty) _selectMode = false;
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  void _selectAllVisible() {
    final visible = _visibleIndexes;
    setState(() {
      _selectMode = true;
      _selectedIndexes
        ..clear()
        ..addAll(visible);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIndexes.clear();
      _selectMode = false;
    });
  }

  Future<_CopyMode?> _askCopyMode(BuildContext context, int count) async {
    return showDialog<_CopyMode>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add $count ${widget.titlePlural}'),
        content: Text(
          'Do you want to copy only the ${widget.titlePlural}, or also import exercises tied to the selected ${widget.titlePlural}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _CopyMode.containerOnly),
            child: Text('${_capitalize(widget.titlePlural)} only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _CopyMode.containerAndExercises),
            child: Text('${_capitalize(widget.titlePlural)} + Exercises'),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Future<Map<String, dynamic>> _ensureImportedEquipment() async {
    final listDynamic = await _equipmentService.getAllEquipment();
    final list = listDynamic
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    for (final e in list) {
      final name = (e['name'] ?? '').toString().trim().toLowerCase();
      final kind = (e['kind'] ?? 'equipment').toString().trim().toLowerCase();
      if (kind == 'equipment' && name == _importedEquipmentName.toLowerCase()) {
        return e;
      }
    }

    // Create if missing
    final created = await _equipmentService.insertEquipment(
      _importedEquipmentName,
      kind: 'equipment',
    );
    return Map<String, dynamic>.from(created);
  }

  Future<String?> _findMyExerciseIdByNameInEquipment({
    required String equipmentId,
    required String name,
  }) async {
    final nm = name.trim();
    if (nm.isEmpty) return null;

    final rows = await supabase
        .from('exercises')
        .select('id, name')
        .eq('equipment_id', equipmentId);

    if (rows is! List) return null;

    final target = nm.toLowerCase();
    for (final r in rows) {
      if (r is Map) {
        final rn = (r['name'] ?? '').toString().trim().toLowerCase();
        if (rn == target) {
          final id = (r['id'] ?? '').toString().trim();
          return id.isEmpty ? null : id;
        }
      }
    }
    return null;
  }

  Future<String?> _insertMyExerciseIntoEquipment({
    required String equipmentId,
    required Map<String, dynamic> friendExercise,
  }) async {
    final name = (friendExercise['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    // De-dupe by (equipment_id + name)
    final existingId = await _findMyExerciseIdByNameInEquipment(
      equipmentId: equipmentId,
      name: name,
    );
    if (existingId != null) return existingId;

    try {
      final friendVideoUrl = _exerciseVideoUrl(friendExercise);
      final friendExerciseId = (friendExercise['id'] ?? '').toString().trim();

      final inserted = await supabase
          .from('exercises')
          .insert({
            'name': name,
            'primary_muscle_group': (friendExercise['primary_muscle_group'] ?? '').toString(),
            'type': (friendExercise['type'] ?? '').toString(),
            'equipment_id': equipmentId,

            // do not copy url
            'video_url': null,

            // store reference if friend actually has a video
            'video_source_exercise_id':
                (friendVideoUrl != null && friendExerciseId.isNotEmpty) ? friendExerciseId : null,
          })
          .select('id')
          .single();

      final id = (inserted['id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _linkExerciseToRoutine({
    required String routineId,
    required String exerciseId,
  }) async {
    try {
      await supabase.from('routine_items').insert({
        'routine_id': routineId,
        'exercise_id': exerciseId,
        // user_id defaults to auth.uid()
      });
    } catch (_) {
      // ignore duplicates
    }
  }

  Future<void> _addSelectedToMyList() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    final mode = await _askCopyMode(context, _selectedIndexes.length);
    if (mode == null) return;

    final orderedIndexes = _selectedIndexes.toList()
      ..sort((a, b) {
        final an =
            (widget.friendContainers[a]['name'] ?? '').toString().toLowerCase();
        final bn =
            (widget.friendContainers[b]['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

    setState(() => _isAdding = true);

    int addedContainers = 0;
    int skippedContainers = 0;
    int addedExercises = 0;
    int skippedExercises = 0;
    int addedRoutineLinks = 0;

    try {
      // If we import exercises for routines, we need a home equipment to store them.
      Map<String, dynamic>? importedEquipment;
      String? importedEquipmentId;

      for (final idx in orderedIndexes) {
        final friendContainer = widget.friendContainers[idx];
        final name = (friendContainer['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          skippedContainers++;
          continue;
        }

        Map<String, dynamic>? createdContainer;
        try {
          createdContainer = await _equipmentService.insertEquipment(
            name,
            kind: widget.insertKind,
          );
          addedContainers++;
        } catch (_) {
          skippedContainers++;
          createdContainer = null;
        }

        if (mode == _CopyMode.containerAndExercises && createdContainer != null) {
          final friendContainerId = _friendContainerId(friendContainer);
          final myContainerId = (createdContainer['id'] ?? '').toString().trim();

          if (friendContainerId == null || myContainerId.isEmpty) continue;

          // Friend exercises that "belong to" this friend container in their old model.
          final matches = widget.friendExercises.where((ex) {
            final exContainerId = _exerciseFriendContainerId(ex);
            return exContainerId != null && exContainerId == friendContainerId;
          }).toList();

          if (matches.isEmpty) continue;

          // Ensure imported home equipment once (only needed when importing routine exercises)
          if (widget.insertKind == 'routine') {
            importedEquipment ??= await _ensureImportedEquipment();
            importedEquipmentId = (importedEquipment['id'] ?? '').toString().trim();
            if (importedEquipmentId.isEmpty) continue;
          }

          for (final ex in matches) {
            final exName = (ex['name'] ?? '').toString().trim();
            if (exName.isEmpty) {
              skippedExercises++;
              continue;
            }

            // EQUIPMENT import: exercises go into that equipment directly (old behavior)
            if (widget.insertKind == 'equipment') {
              try {
                final friendVideoUrl = _exerciseVideoUrl(ex);
                final friendExerciseId = (ex['id'] ?? '').toString().trim();

                await supabase.from('exercises').insert({
                  'name': exName,
                  'primary_muscle_group': (ex['primary_muscle_group'] ?? '').toString(),
                  'type': (ex['type'] ?? '').toString(),
                  'equipment_id': myContainerId,
                  'video_url': null,
                  'video_source_exercise_id':
                      (friendVideoUrl != null && friendExerciseId.isNotEmpty) ? friendExerciseId : null,
                });

                addedExercises++;
              } catch (_) {
                skippedExercises++;
              }
              continue;
            }

            // ROUTINE import: exercises MUST live in one equipment, then LINK into routine_items.
            if (widget.insertKind == 'routine') {
              final homeEquipmentId = importedEquipmentId!;
              final myExerciseId = await _insertMyExerciseIntoEquipment(
                equipmentId: homeEquipmentId,
                friendExercise: ex,
              );

              if (myExerciseId == null) {
                skippedExercises++;
                continue;
              }

              // Link into newly created routine
              await _linkExerciseToRoutine(
                routineId: myContainerId,
                exerciseId: myExerciseId,
              );

              addedExercises++;
              addedRoutineLinks++;
            }
          }
        }
      }

      if (!mounted) return;

      final totalSkipped = skippedContainers + skippedExercises;

      final msg = mode == _CopyMode.containerOnly
          ? (skippedContainers > 0
              ? "Added $addedContainers ${widget.titlePlural} • Skipped $skippedContainers (already exists)"
              : "Added $addedContainers ${widget.titlePlural}")
          : widget.insertKind == 'routine'
              ? "Added $addedContainers ${widget.titlePlural} ($addedRoutineLinks linked) • Imported $addedExercises exercise(s)"
                  "${totalSkipped > 0 ? " • Skipped $totalSkipped" : ""}"
              : "Added $addedContainers ${widget.titlePlural} ($addedExercises exercises)"
                  "${totalSkipped > 0 ? " • Skipped $totalSkipped" : ""}";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(msg),
        ),
      );

      _clearSelection();
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Widget _buildMuscleFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const cols = 3;
          const gap = 8.0;

          final totalGap = gap * (cols - 1);
          final chipWidth = (constraints.maxWidth - totalGap) / cols;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: _muscleFiltersGrid.map((label) {
              if (label == null) {
                return SizedBox(width: chipWidth, height: 32);
              }

              final selected = _selectedMuscle == label;

              return SizedBox(
                width: chipWidth,
                child: ChoiceChip(
                  label: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedMuscle = label;

                      if (_selectMode) {
                        final visible = _visibleIndexes.toSet();
                        _selectedIndexes.removeWhere((i) => !visible.contains(i));
                        if (_selectedIndexes.isEmpty) _selectMode = false;
                      }
                    });
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.friendContainers;
    if (list.isEmpty) {
      return Center(child: Text(widget.emptyMessage));
    }

    final visibleIndexes = _visibleIndexes;
    final selectedCount = _selectedIndexes.length;

    final tip = widget.insertKind == 'routine'
        ? "Tip: Long-press a routine to select it, then add it to your routines."
        : "Tip: Long-press equipment to select it, then add it to your equipment list.";

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: visibleIndexes.length + 2,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) return _buildMuscleFilterBar();

            if (i == 1) {
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tip,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final visibleIndex = visibleIndexes[i - 2];
            final c = list[visibleIndex];
            final name = (c['name'] ?? '').toString();
            final isSelected = _selectedIndexes.contains(visibleIndex);

            return ListTile(
              leading: _selectMode
                  ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                  : Icon(widget.leadingIcon),
              title: Text(name),
              trailing: _selectMode ? null : const Icon(Icons.chevron_right),
              selected: isSelected,
              onTap: _selectMode ? () => _toggleSelect(visibleIndex) : null,
              onLongPress: () {
                if (_selectMode) {
                  _toggleSelect(visibleIndex);
                } else {
                  _enterSelectMode(visibleIndex);
                }
              },
            );
          },
        ),
        if (_selectMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      Text(
                        "$selectedCount selected",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _isAdding ? null : _selectAllVisible,
                        child: const Text("Select all"),
                      ),
                      TextButton(
                        onPressed: _isAdding ? null : _clearSelection,
                        child: const Text("Clear"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: (selectedCount == 0 || _isAdding) ? null : _addSelectedToMyList,
                        icon: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_done),
                        label: Text(_isAdding ? "Adding..." : "Add"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- EXERCISES TAB ----------------

enum _AddTargetKind { equipment, routine }

class _ExercisesTab extends StatefulWidget {
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> friendEquipment;

  const _ExercisesTab({required this.exercises, required this.friendEquipment});

  @override
  State<_ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends State<_ExercisesTab> {
  final supabase = Supabase.instance.client;
  final _equipmentService = EquipmentService();

  bool _selectMode = false;
  final Set<int> _selectedIndexes = {};
  bool _isAdding = false;

  void _enterSelectMode(int index) {
    setState(() {
      _selectMode = true;
      _selectedIndexes.add(index);
    });
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndexes.contains(index)) {
        _selectedIndexes.remove(index);
        if (_selectedIndexes.isEmpty) _selectMode = false;
      } else {
        _selectedIndexes.add(index);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectMode = false;
      _selectedIndexes.clear();
    });
  }

  String? _videoUrl(Map<String, dynamic> ex) {
    final s = (ex['video_url'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  Future<String?> _findMyExerciseIdByNameInEquipment({
    required String equipmentId,
    required String name,
  }) async {
    final nm = name.trim();
    if (nm.isEmpty) return null;

    final rows = await supabase
        .from('exercises')
        .select('id, name')
        .eq('equipment_id', equipmentId);

    if (rows is! List) return null;

    final target = nm.toLowerCase();
    for (final r in rows) {
      if (r is Map) {
        final rn = (r['name'] ?? '').toString().trim().toLowerCase();
        if (rn == target) {
          final id = (r['id'] ?? '').toString().trim();
          return id.isEmpty ? null : id;
        }
      }
    }
    return null;
  }

  Future<String?> _insertMyExerciseIntoEquipment({
    required String equipmentId,
    required Map<String, dynamic> friendExercise,
  }) async {
    final name = (friendExercise['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    // De-dupe by (equipment_id + name)
    final existingId = await _findMyExerciseIdByNameInEquipment(
      equipmentId: equipmentId,
      name: name,
    );
    if (existingId != null) return existingId;

    try {
      final friendVideoUrl = _videoUrl(friendExercise);
      final friendExerciseId = (friendExercise['id'] ?? '').toString().trim();

      final inserted = await supabase
          .from('exercises')
          .insert({
            'name': name,
            'primary_muscle_group': (friendExercise['primary_muscle_group'] ?? '').toString(),
            'type': (friendExercise['type'] ?? '').toString(),
            'equipment_id': equipmentId,

            // do not copy URL
            'video_url': null,

            // store reference if friend has a video
            'video_source_exercise_id':
                (friendVideoUrl != null && friendExerciseId.isNotEmpty) ? friendExerciseId : null,
          })
          .select('id')
          .single();

      final id = (inserted['id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _linkExerciseToRoutine({
    required String routineId,
    required String exerciseId,
  }) async {
    try {
      await supabase.from('routine_items').insert({
        'routine_id': routineId,
        'exercise_id': exerciseId,
      });
    } catch (_) {
      // ignore duplicates
    }
  }

  Future<Map<String, dynamic>?> _pickOrCreateContainer({
    required String title,
    required String existingHint,
    required String createHint,
    required String kind, // 'equipment' or 'routine'
  }) async {
    // Load MY containers
    final myDynamic = await _equipmentService.getAllEquipment();
    final myList = myDynamic
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => (e['kind'] ?? 'equipment').toString().toLowerCase().trim() == kind)
        .toList()
      ..sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

    String? selectedId;
    final newController = TextEditingController();

    final picked = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final typed = newController.text.trim();
            final canUse = (selectedId != null && selectedId!.isNotEmpty) || typed.isNotEmpty;

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(existingHint),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedId,
                    isExpanded: true,
                    items: [
                      for (final e in myList)
                        DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text(e['name'].toString()),
                        ),
                    ],
                    onChanged: newController.text.isNotEmpty
                        ? null
                        : (val) {
                            setLocal(() {
                              selectedId = val;
                              if (val != null) newController.text = '';
                            });
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Select",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(createHint),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newController,
                    enabled: selectedId == null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "New name",
                    ),
                    onChanged: (_) {
                      setLocal(() {
                        if (newController.text.isNotEmpty) {
                          selectedId = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: canUse ? () => Navigator.pop(context, true) : null,
                  child: const Text("Continue"),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != true) return null;

    final typed = newController.text.trim();

    if (typed.isNotEmpty) {
      final created = await _equipmentService.insertEquipment(typed, kind: kind);
      return Map<String, dynamic>.from(created);
    }

    if (selectedId != null && selectedId!.isNotEmpty) {
      final found = myList.firstWhere((e) => e['id'].toString() == selectedId);
      return found;
    }

    return null;
  }

  /// ✅ NEW: Add selected friend exercises to MY EQUIPMENT (existing behavior)
  /// (imports canonical exercises into one equipment)
  Future<void> _addSelectedExercisesToEquipment() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    final target = await _pickOrCreateContainer(
      title: "Add ${_selectedIndexes.length} exercise(s) to equipment",
      existingHint: "Add to existing equipment:",
      createHint: "Or create new equipment:",
      kind: 'equipment',
    );
    if (target == null) return;

    final targetEquipmentId = (target['id'] ?? '').toString().trim();
    final targetEquipmentName = (target['name'] ?? '').toString().trim();
    if (targetEquipmentId.isEmpty) return;

    setState(() => _isAdding = true);

    int added = 0;
    int skipped = 0;

    try {
      final ordered = _selectedIndexes.toList()
        ..sort((a, b) {
          final an = (widget.exercises[a]['name'] ?? '').toString().toLowerCase();
          final bn = (widget.exercises[b]['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

      for (final idx in ordered) {
        final ex = widget.exercises[idx];
        final id = await _insertMyExerciseIntoEquipment(
          equipmentId: targetEquipmentId,
          friendExercise: ex,
        );
        if (id == null) {
          skipped++;
        } else {
          added++;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            skipped > 0
                ? "Added $added exercise(s) to $targetEquipmentName • Skipped $skipped"
                : "Added $added exercise(s) to $targetEquipmentName",
          ),
        ),
      );

      _cancelSelection();
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  /// ✅ NEW: Add selected friend exercises to MY ROUTINE
  /// Because exercises must "live" in one equipment, we ask for:
  /// 1) Home equipment for the imported exercises
  /// 2) Target routine to link them into (routine_items)
  Future<void> _addSelectedExercisesToRoutine() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    // Pick/create the HOME equipment first
    final homeEquipment = await _pickOrCreateContainer(
      title: "Where should these exercises live?",
      existingHint: "Choose home equipment:",
      createHint: "Or create new equipment:",
      kind: 'equipment',
    );
    if (homeEquipment == null) return;

    final homeEquipmentId = (homeEquipment['id'] ?? '').toString().trim();
    final homeEquipmentName = (homeEquipment['name'] ?? '').toString().trim();
    if (homeEquipmentId.isEmpty) return;

    // Pick/create routine
    final routine = await _pickOrCreateContainer(
      title: "Add ${_selectedIndexes.length} exercise(s) to routine",
      existingHint: "Add to existing routine:",
      createHint: "Or create new routine:",
      kind: 'routine',
    );
    if (routine == null) return;

    final routineId = (routine['id'] ?? '').toString().trim();
    final routineName = (routine['name'] ?? '').toString().trim();
    if (routineId.isEmpty) return;

    setState(() => _isAdding = true);

    int imported = 0;
    int linked = 0;
    int skipped = 0;

    try {
      final ordered = _selectedIndexes.toList()
        ..sort((a, b) {
          final an = (widget.exercises[a]['name'] ?? '').toString().toLowerCase();
          final bn = (widget.exercises[b]['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

      for (final idx in ordered) {
        final ex = widget.exercises[idx];

        final myExerciseId = await _insertMyExerciseIntoEquipment(
          equipmentId: homeEquipmentId,
          friendExercise: ex,
        );

        if (myExerciseId == null) {
          skipped++;
          continue;
        }

        imported++;

        await _linkExerciseToRoutine(
          routineId: routineId,
          exerciseId: myExerciseId,
        );

        linked++;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            skipped > 0
                ? "Imported $imported into $homeEquipmentName • Linked $linked into $routineName • Skipped $skipped"
                : "Imported $imported into $homeEquipmentName • Linked $linked into $routineName",
          ),
        ),
      );

      _cancelSelection();
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exercises.isEmpty) {
      return const Center(child: Text("No exercises found."));
    }

    final selectedCount = _selectedIndexes.length;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount: widget.exercises.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Tip: Long-press exercises to select them, then add them to your equipment or routines.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final index = i - 1;
            final ex = widget.exercises[index];

            final name = (ex['name'] ?? '').toString();
            final equipName = (ex['equipment_name'] ?? '').toString();
            final mg = (ex['primary_muscle_group'] ?? '').toString();
            final type = (ex['type'] ?? '').toString();

            final url = _videoUrl(ex);
            final hasVideo = url != null && url.isNotEmpty;

            final isSelected = _selectedIndexes.contains(index);

            return Card(
              child: ListTile(
                leading: _selectMode
                    ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                    : null,
                title: Text(name),
                subtitle: Text("$equipName • $mg • $type"),
                trailing: Tooltip(
                  message: hasVideo ? 'Form video available' : 'No form video',
                  child: Icon(
                    hasVideo ? Icons.play_circle_fill : Icons.videocam_off,
                    color: hasVideo
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                  ),
                ),
                selected: isSelected,
                onTap: _selectMode
                    ? () => _toggleSelect(index)
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FriendExerciseFormVideoPage(
                              exerciseName: name,
                              videoUrl: url,
                            ),
                          ),
                        );
                      },
                onLongPress: () {
                  if (_selectMode) {
                    _toggleSelect(index);
                  } else {
                    _enterSelectMode(index);
                  }
                },
              ),
            );
          },
        ),
        if (_selectMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        "$selectedCount selected",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextButton(
                        onPressed: _isAdding ? null : _cancelSelection,
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton.icon(
                        onPressed: (selectedCount == 0 || _isAdding) ? null : _addSelectedExercisesToEquipment,
                        icon: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.fitness_center),
                        label: Text(_isAdding ? "Adding..." : "Add to equipment"),
                      ),
                      ElevatedButton.icon(
                        onPressed: (selectedCount == 0 || _isAdding) ? null : _addSelectedExercisesToRoutine,
                        icon: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.view_list),
                        label: Text(_isAdding ? "Adding..." : "Add to routine"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- FORM VIDEO PAGE ----------------

class FriendExerciseFormVideoPage extends StatefulWidget {
  final String exerciseName;
  final String? videoUrl;

  const FriendExerciseFormVideoPage({
    super.key,
    required this.exerciseName,
    required this.videoUrl,
  });

  @override
  State<FriendExerciseFormVideoPage> createState() => _FriendExerciseFormVideoPageState();
}

class _FriendExerciseFormVideoPageState extends State<FriendExerciseFormVideoPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = (widget.videoUrl ?? '').trim();

    if (url.isEmpty) {
      setState(() {
        _loading = false;
        _controller = null;
      });
      return;
    }

    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize();
      c.setLooping(true);

      if (!mounted) return;
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _controller = null;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urlMissing = (widget.videoUrl ?? '').trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(widget.exerciseName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : urlMissing
                ? const Center(child: Text("No form video uploaded."))
                : _error != null
                    ? Center(
                        child: Text(
                          "Couldn't load video.\n\n$_error",
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoPlayer(_controller!),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                iconSize: 42,
                                icon: Icon(
                                  _controller!.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_controller!.value.isPlaying) {
                                      _controller!.pause();
                                    } else {
                                      _controller!.play();
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Form video",
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
      ),
    );
  }
}