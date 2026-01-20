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
  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

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

      // (Your RPC already orders by eq.name then ex.name, but we keep it as-is.)

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
    final hh = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(
      2,
      '0',
    );
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
    final title = widget.friendUsername.isNotEmpty
        ? "@${widget.friendUsername}"
        : "Friend";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "History"),
            Tab(text: "Equipment"),
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
                _EquipmentTab(
                  equipment: _equipment,
                  friendExercises: _exercises,
                  friendUsername: widget.friendUsername,
                ),
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

// ---------------- HISTORY TAB (summary + detailed toggle) ----------------

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
    final v =
        row['primary_muscle_group'] ??
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
              backgroundColor: isSummary
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : null,
              side: BorderSide(
                color: isSummary
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: isSummary
                ? null
                : () => setState(() => _view = _FriendHistoryView.summary),
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
              backgroundColor: isDetailed
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : null,
              side: BorderSide(
                color: isDetailed
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: isDetailed
                ? null
                : () => setState(() => _view = _FriendHistoryView.detailed),
            child: Text(
              'Detailed Sets',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDetailed
                    ? Theme.of(context).colorScheme.primary
                    : null,
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
                        Text(
                          _formatDate(s.day),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${s.workoutDurationMinutes} min',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
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
          child: _view == _FriendHistoryView.summary
              ? _buildSummaryView(context)
              : _buildDetailedView(context),
        ),
      ],
    );
  }
}

// ---------------- EQUIPMENT TAB (select all + copy mode + optionally copy exercises) ----------------

enum _CopyMode { equipmentOnly, equipmentAndExercises }

class _EquipmentTab extends StatefulWidget {
  final List<Map<String, dynamic>> equipment;
  final List<Map<String, dynamic>> friendExercises;
  final String friendUsername;

  const _EquipmentTab({
    required this.equipment,
    required this.friendExercises,
    required this.friendUsername,
  });

  @override
  State<_EquipmentTab> createState() => _EquipmentTabState();
}

class _EquipmentTabState extends State<_EquipmentTab> {
  final _equipmentService = EquipmentService();
  final supabase = Supabase.instance.client;

  bool _selectMode = false;
  final Set<int> _selectedIndexes = {};
  bool _isAdding = false;

  // ---------- PRIMARY MUSCLE GROUP FILTER ----------
  static const List<String> _muscleFilters = [
    'All',
    'Chest',
    'Shoulders',
    'Back',
    'Arms',
    'Legs',
    'Core',
  ];

  String _selectedMuscle = 'All';

  /// equipmentId -> set of muscle keys (lowercase normalized)
  final Map<String, Set<String>> _equipmentMuscleGroups = {};

  @override
  void initState() {
    super.initState();
    _buildEquipmentMuscleMap();
  }

  @override
  void didUpdateWidget(covariant _EquipmentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.friendExercises != widget.friendExercises ||
        oldWidget.equipment != widget.equipment) {
      _buildEquipmentMuscleMap();
      // If currently selected filter yields nothing because data changed,
      // we keep the selection (user intent), but mapping will update.
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

  String? _friendEqId(Map<String, dynamic> eq) {
    final s = (eq['id'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _exerciseFriendEquipmentId(Map<String, dynamic> ex) {
    final s = (ex['equipment_id'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _exerciseVideoUrl(Map<String, dynamic> ex) {
    final s = (ex['video_url'] ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  void _buildEquipmentMuscleMap() {
    final map = <String, Set<String>>{};

    for (final ex in widget.friendExercises) {
      final eqId = _exerciseFriendEquipmentId(ex);
      if (eqId == null) continue;

      final mgRaw = ex['primary_muscle_group'];
      final mg = _normalizeMuscle(mgRaw);
      if (mg.isEmpty) continue;

      map.putIfAbsent(eqId, () => <String>{}).add(mg);
    }

    setState(() {
      _equipmentMuscleGroups
        ..clear()
        ..addAll(map);
    });
  }

  List<int> get _visibleIndexes {
    // If "All", show everything.
    if (_selectedMuscle == 'All') {
      return List.generate(widget.equipment.length, (i) => i);
    }

    final key = _selectedMuscleKey();
    final visible = <int>[];

    for (int i = 0; i < widget.equipment.length; i++) {
      final eq = widget.equipment[i];
      final id = _friendEqId(eq);
      if (id == null) continue;

      final groups = _equipmentMuscleGroups[id];
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
        title: Text('Add $count equipment'),
        content: const Text(
          'Do you want to copy only the equipment, or also copy all exercises tied to the selected equipment?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _CopyMode.equipmentOnly),
            child: const Text('Equipment only'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, _CopyMode.equipmentAndExercises),
            child: const Text('Equipment + Exercises'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSelectedToMyEquipment() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    final mode = await _askCopyMode(context, _selectedIndexes.length);
    if (mode == null) return;

    final orderedIndexes = _selectedIndexes.toList()
      ..sort((a, b) {
        final an = (widget.equipment[a]['name'] ?? '').toString().toLowerCase();
        final bn = (widget.equipment[b]['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

    setState(() => _isAdding = true);

    int addedEquipment = 0;
    int skippedEquipment = 0;
    int addedExercises = 0;
    int skippedExercises = 0;

    try {
      for (final idx in orderedIndexes) {
        final friendEq = widget.equipment[idx];
        final eqName = (friendEq['name'] ?? '').toString().trim();
        if (eqName.isEmpty) {
          skippedEquipment++;
          continue;
        }

        Map<String, dynamic>? createdEq;
        try {
          createdEq = await _equipmentService.insertEquipment(eqName);
          addedEquipment++;
        } catch (_) {
          skippedEquipment++;
          // If equipment already exists, we skip copying exercises too (safe default)
          createdEq = null;
        }

        if (mode == _CopyMode.equipmentAndExercises && createdEq != null) {
          final friendEqId = _friendEqId(friendEq);
          final myEqId = createdEq['id']?.toString();

          if (friendEqId == null || myEqId == null || myEqId.isEmpty) continue;

          final matches = widget.friendExercises.where((ex) {
            final exEqId = _exerciseFriendEquipmentId(ex);
            return exEqId != null && exEqId == friendEqId;
          }).toList();

          for (final ex in matches) {
            final exName = (ex['name'] ?? '').toString().trim();
            if (exName.isEmpty) {
              skippedExercises++;
              continue;
            }

            try {
              await supabase.from('exercises').insert({
                'name': exName,
                'primary_muscle_group': (ex['primary_muscle_group'] ?? '')
                    .toString(),
                'type': (ex['type'] ?? '').toString(),
                'equipment_id': myEqId,
                'video_url': _exerciseVideoUrl(ex),
              });
              addedExercises++;
            } catch (_) {
              skippedExercises++;
            }
          }
        }
      }

      if (!mounted) return;

      final msg = mode == _CopyMode.equipmentOnly
          ? (skippedEquipment > 0
                ? "Added $addedEquipment equipment • Skipped $skippedEquipment (already exists)"
                : "Added $addedEquipment equipment")
          : "Added $addedEquipment equipment ($addedExercises exercises)"
                "${(skippedEquipment + skippedExercises) > 0 ? " • Skipped ${skippedEquipment + skippedExercises}" : ""}";

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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final label in _muscleFilters) ...[
              ChoiceChip(
                label: Text(label),
                selected: _selectedMuscle == label,
                onSelected: (_) {
                  setState(() {
                    _selectedMuscle = label;

                    // Optional: if selection mode is active, keep only selections
                    // that are still visible under the filter (prevents "ghost" selections).
                    if (_selectMode) {
                      final visible = _visibleIndexes.toSet();
                      _selectedIndexes.removeWhere((i) => !visible.contains(i));
                      if (_selectedIndexes.isEmpty) _selectMode = false;
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final equipment = widget.equipment;
    if (equipment.isEmpty) {
      return const Center(child: Text("No equipment found."));
    }

    final visibleIndexes = _visibleIndexes;
    final selectedCount = _selectedIndexes.length;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount:
              visibleIndexes.length + 2, // +1 for filter bar, +1 for tip card
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              // ✅ Filter bar at very top
              return _buildMuscleFilterBar();
            }

            if (i == 1) {
              // Tip card
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
                          "Tip: Long-press equipment to select it, then add it to your equipment list.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final visibleIndex = visibleIndexes[i - 2];
            final e = equipment[visibleIndex];
            final name = (e['name'] ?? '').toString();
            final isSelected = _selectedIndexes.contains(visibleIndex);

            return ListTile(
              leading: _selectMode
                  ? Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    )
                  : const Icon(Icons.fitness_center),
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
                        onPressed: (selectedCount == 0 || _isAdding)
                            ? null
                            : _addSelectedToMyEquipment,
                        icon: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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

// ---------------- EXERCISES TAB (long-press multi-select -> add to new/existing equipment) ----------------

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

  Future<void> _addSelectedExercisesToEquipment() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    // Load MY equipment options
    final myEquipmentDynamic = await _equipmentService.getAllEquipment();
    final myEquipment =
        myEquipmentDynamic
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
          ..sort((a, b) {
            final an = (a['name'] ?? '').toString().toLowerCase();
            final bn = (b['name'] ?? '').toString().toLowerCase();
            return an.compareTo(bn);
          });

    String? selectedEquipmentId;
    String? selectedEquipmentName;
    final newEquipmentController = TextEditingController();

    final picked = await showDialog<bool>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final typed = newEquipmentController.text.trim();
            final canAdd =
                (selectedEquipmentId != null &&
                    selectedEquipmentId!.isNotEmpty) ||
                typed.isNotEmpty;

            return AlertDialog(
              title: Text("Add ${_selectedIndexes.length} exercise(s)"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Add to existing equipment:"),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedEquipmentId,
                    isExpanded: true,
                    items: [
                      for (final e in myEquipment)
                        DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text(e['name'].toString()),
                        ),
                    ],
                    onChanged: newEquipmentController.text.isNotEmpty
                        ? null
                        : (val) {
                            setLocal(() {
                              selectedEquipmentId = val;
                              if (val != null) newEquipmentController.text = '';
                            });
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Select equipment",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text("Or create new equipment:"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newEquipmentController,
                    enabled: selectedEquipmentId == null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "New equipment name",
                    ),
                    onChanged: (_) {
                      setLocal(() {
                        if (newEquipmentController.text.isNotEmpty) {
                          selectedEquipmentId = null;
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
                  onPressed: canAdd ? () => Navigator.pop(context, true) : null,
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != true) return;

    setState(() => _isAdding = true);

    int added = 0;
    int skipped = 0;

    try {
      String targetEquipmentId;
      final typed = newEquipmentController.text.trim();

      if (typed.isNotEmpty) {
        final created = await _equipmentService.insertEquipment(typed);
        targetEquipmentId = created['id'].toString();
        selectedEquipmentName = created['name'].toString();
      } else {
        targetEquipmentId = selectedEquipmentId!;
        selectedEquipmentName = myEquipment
            .firstWhere(
              (e) => e['id'].toString() == selectedEquipmentId,
            )['name']
            .toString();
      }

      final ordered = _selectedIndexes.toList()
        ..sort((a, b) {
          final an = (widget.exercises[a]['name'] ?? '')
              .toString()
              .toLowerCase();
          final bn = (widget.exercises[b]['name'] ?? '')
              .toString()
              .toLowerCase();
          return an.compareTo(bn);
        });

      for (final idx in ordered) {
        final ex = widget.exercises[idx];
        final name = (ex['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          skipped++;
          continue;
        }

        try {
          await supabase.from('exercises').insert({
            'name': name,
            'primary_muscle_group': (ex['primary_muscle_group'] ?? '')
                .toString(),
            'type': (ex['type'] ?? '').toString(),
            'equipment_id': targetEquipmentId,
            'video_url': _videoUrl(ex),
          });
          added++;
        } catch (_) {
          skipped++;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            skipped > 0
                ? "Added $added exercises to $selectedEquipmentName • Skipped $skipped"
                : "Added $added exercises to $selectedEquipmentName",
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
                          "Tip: Long-press exercises to select them, then add them to your equipment.",
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
                    ? Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                      )
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
                  child: Row(
                    children: [
                      Text(
                        "$selectedCount selected",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _isAdding ? null : _cancelSelection,
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: (selectedCount == 0 || _isAdding)
                            ? null
                            : _addSelectedExercisesToEquipment,
                        icon: _isAdding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.playlist_add),
                        label: Text(
                          _isAdding ? "Adding..." : "Add to equipment",
                        ),
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
  State<FriendExerciseFormVideoPage> createState() =>
      _FriendExerciseFormVideoPageState();
}

class _FriendExerciseFormVideoPageState
    extends State<FriendExerciseFormVideoPage> {
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
