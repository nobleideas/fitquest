import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/friend_profile_service.dart';
import '../services/gym_service.dart';
import '../services/meal_service.dart';

// Friend Profile premium-dark design tokens. Scoped to this page so other
// FitQuest screens keep their existing themes.
class _FriendUx {
  static const background = Color(0xFF090D15);
  static const surface = Color(0xFF151B27);
  static const raised = Color(0xFF202838);
  static const accent = Color(0xFF78E4C4);
  static const text = Color(0xFFF4F7FC);
  static const muted = Color(0xFFA6B2C4);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      onPrimary: background,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: raised,
      outline: const Color(0xFF394357),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      // The app-wide theme may be light. Override inherited typography too,
      // otherwise text on these dark surfaces keeps the light theme's dark ink.
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: text, fontSize: 15),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: text),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: text),
      ),
      dividerColor: const Color(0xFF30394B),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text, fontSize: 20, fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF2C3547)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        iconColor: accent,
        textColor: text,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Color(0xFF293244),
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.17),
        side: const BorderSide(color: Color(0xFF354054)),
        labelStyle: const TextStyle(color: text, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted),
        floatingLabelStyle: const TextStyle(color: accent),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF364154)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent, foregroundColor: background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
    );
  }
}

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
  final _friendProfileService = FriendProfileService();

  late final TabController _tabController;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _equipment = []; // friend containers (equipment+routines)
  List<Map<String, dynamic>> _exercises = [];
  List<Map<String, dynamic>> _foodLog = [];
  String? _foodLogError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
      final data = await _friendProfileService.loadFriendProfile(
        widget.friendUserId,
      );
      List<Map<String, dynamic>> foodLog = [];
      String? foodLogError;
      try {
        foodLog = await _friendProfileService.loadFriendFoodLog(widget.friendUserId);
      } catch (e) {
        foodLogError = e.toString();
      }

      if (!mounted) return;
      setState(() {
        _history = data.history;
        _equipment = data.containers;
        _exercises = data.exercises;
        _foodLog = foodLog;
        _foodLogError = foodLogError;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

    return Theme(
      data: _FriendUx.theme(context),
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 15),
          tabs: const [
            Tab(text: "History"),
            Tab(text: "Equipment"),
            Tab(text: "Routines"),
            Tab(text: "Exercises"),
            Tab(text: "Food Log"),
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
                    _FriendFoodLogTab(rows: _foodLog, error: _foodLogError),
                  ],
                ),
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

      // Sum separate workout intervals; never count the idle time between
      // morning and evening sessions as training time.
      final times = dayRows
          .map(_rowCreatedAtLocal)
          .whereType<DateTime>()
          .toList()..sort();
      int durationMin = 0;
      if (times.length > 1) {
        var sessionStart = times.first;
        var sessionEnd = times.first;
        for (final time in times.skip(1)) {
          if (time.difference(sessionEnd) > const Duration(minutes: 60)) {
            durationMin += sessionEnd.difference(sessionStart).inMinutes;
            sessionStart = time;
          }
          sessionEnd = time;
        }
        durationMin += sessionEnd.difference(sessionStart).inMinutes;
      }

      final Map<String, int> setsByName = {};
      final Map<String, DateTime> firstTimeByExerciseName = {};
      final Map<String, Map<String, dynamic>> firstRowByExerciseName = {};

      for (final r in dayRows) {
        final name = (r['exercise_name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        setsByName[name] = (setsByName[name] ?? 0) + 1;

        final dt = _rowCreatedAtLocal(r);
        if (dt != null) {
          final existing = firstTimeByExerciseName[name];
          if (existing == null || dt.isBefore(existing)) {
            firstTimeByExerciseName[name] = dt;
            firstRowByExerciseName[name] = r;
          }
        } else {
          firstRowByExerciseName.putIfAbsent(name, () => r);
        }
      }

      final names = setsByName.keys.toList()
        ..sort((a, b) {
          final aTime = firstTimeByExerciseName[a];
          final bTime = firstTimeByExerciseName[b];

          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return aTime.compareTo(bTime);
        });

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
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];

        final muscleEntries = s.muscleGroupCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
            ],
          ),
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

    // Group recorded sets by their LOCAL calendar day, matching Workout Summary.
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final row in history) {
      final local = _rowCreatedAtLocal(row);
      if (local == null) continue;
      final day = DateTime(local.year, local.month, local.day);
      byDay.putIfAbsent(day, () => <Map<String, dynamic>>[]).add(row);
    }

    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final rows in byDay.values) {
      rows.sort((a, b) {
        final aTime = _rowCreatedAtLocal(a);
        final bTime = _rowCreatedAtLocal(b);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final sets = byDay[day]!;
        return Card(
          child: ExpansionTile(
            key: PageStorageKey<String>('friend-detailed-${day.toIso8601String()}'),
            title: Text(
              _formatDate(day),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${sets.length} ${sets.length == 1 ? "set" : "sets"}'),
            children: [
              for (final row in sets) ...[
                const Divider(height: 1),
                ListTile(
                  title: Text((row['exercise_name'] ?? '').toString()),
                  subtitle: Text(
                    '${(row['equipment_name'] ?? '').toString()}\n'
                    '${widget.fmtDateTime(row['created_at'])}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    "${row['weight'] ?? ''} x ${row['reps'] ?? ''}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
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
  final _friendProfileService = FriendProfileService();
  final _gymService = GymService();

  bool _selectMode = false;
  final Set<int> _selectedIndexes = {};
  bool _isAdding = false;

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
  String? _selectedGymId;

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
    final s = (c['id'] ?? c['equipment_id'] ?? '').toString().trim();
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

  List<String> _friendContainerGymIds(Map<String, dynamic> c) {
    final raw = c['gym_ids'];

    if (raw is List) {
      return raw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }

    // Backward compatibility with older single-gym RPC responses.
    final direct = (c['gym_id'] ?? '').toString().trim();
    if (direct.isNotEmpty) return [direct];

    final gym = c['gym'];
    if (gym is Map) {
      final nested = (gym['id'] ?? '').toString().trim();
      if (nested.isNotEmpty) return [nested];
    }

    return const [];
  }

  List<String> _friendContainerGymNames(Map<String, dynamic> c) {
    final raw = c['gym_names'];

    if (raw is List) {
      return raw
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }

    // Backward compatibility with older single-gym RPC responses.
    final direct = (c['gym_name'] ?? '').toString().trim();
    if (direct.isNotEmpty) return [direct];

    final gym = c['gym'];
    if (gym is Map) {
      final nested = (gym['name'] ?? '').toString().trim();
      if (nested.isNotEmpty) return [nested];
    }

    return const [];
  }

  List<Map<String, String>> get _friendGyms {
    final byId = <String, String>{};

    for (final c in widget.friendContainers) {
      final ids = _friendContainerGymIds(c);
      final names = _friendContainerGymNames(c);

      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        final name =
            i < names.length && names[i].isNotEmpty ? names[i] : 'Gym';
        byId.putIfAbsent(id, () => name);
      }
    }

    final gyms = byId.entries
        .map((entry) => <String, String>{
              'id': entry.key,
              'name': entry.value,
            })
        .toList()
      ..sort(
        (a, b) => (a['name'] ?? '')
            .toLowerCase()
            .compareTo((b['name'] ?? '').toLowerCase()),
      );

    return gyms;
  }

  List<int> get _visibleIndexes {
    final key = _selectedMuscleKey();
    final visible = <int>[];

    for (int i = 0; i < widget.friendContainers.length; i++) {
      final c = widget.friendContainers[i];

      if (_selectedGymId != null &&
          !_friendContainerGymIds(c).contains(_selectedGymId)) {
        continue;
      }

      if (_selectedMuscle != 'All') {
        final id = _friendContainerId(c);
        if (id == null) continue;

        final groups = _containerMuscleGroups[id];
        if (groups == null || !groups.contains(key)) {
          continue;
        }
      }

      visible.add(i);
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

  Future<String?> _createGymForImport() async {
    final controller = TextEditingController();

    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final canCreate = controller.text.trim().isNotEmpty;

            return AlertDialog(
              title: const Text('Create Gym'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Gym name',
                  hintText: 'Example: Planet Fitness',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) {
                    Navigator.pop(dialogContext, trimmed);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canCreate
                      ? () => Navigator.pop(
                            dialogContext,
                            controller.text.trim(),
                          )
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        ),
      );

      if (name == null || name.trim().isEmpty) return null;

      final gym = await _gymService.createGym(name.trim());
      final gymId = (gym['id'] ?? '').toString().trim();

      if (gymId.isEmpty) {
        throw StateError('The new gym was created without a valid ID.');
      }

      return gymId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not create gym: $e'),
          ),
        );
      }
      return null;
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _chooseDestinationGym() async {
    try {
      final gyms = await _gymService.getGyms();

      if (!mounted) return null;

      if (gyms.isEmpty) {
        final shouldCreate = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Create a gym first'),
            content: const Text(
              'Equipment must be added to one of your gyms. '
              'Create your first gym to continue importing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Create Gym'),
              ),
            ],
          ),
        );

        if (shouldCreate != true || !mounted) return null;
        return _createGymForImport();
      }

      final activeGymId = await _gymService.getActiveGymId();

      if (!mounted) return null;

      final validIds = gyms
          .map((gym) => (gym['id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      String selectedGymId =
          activeGymId != null && validIds.contains(activeGymId)
              ? activeGymId
              : validIds.first;

      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choose Destination Gym'),
              content: DropdownButtonFormField<String>(
                initialValue: selectedGymId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Add equipment to',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
                items: [
                  ...gyms.map(
                    (gym) => DropdownMenuItem<String>(
                      value: (gym['id'] ?? '').toString(),
                      child: Text((gym['name'] ?? 'Gym').toString()),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: '__create_new__',
                    child: Row(
                      children: [
                        Icon(Icons.add),
                        SizedBox(width: 8),
                        Text('Create New Gym'),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  if (value == '__create_new__') {
                    Navigator.pop(dialogContext, '__create_new__');
                    return;
                  }

                  setDialogState(() => selectedGymId = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selectedGymId),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        ),
      );

      if (result == '__create_new__') {
        if (!mounted) return null;
        return _createGymForImport();
      }

      return result;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not load your gyms: $e'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _addSelectedToMyList() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    final mode = await _askCopyMode(context, _selectedIndexes.length);
    if (mode == null) return;

    String? destinationGymId;

    if (widget.insertKind == 'equipment') {
      destinationGymId = await _chooseDestinationGym();
      if (destinationGymId == null || destinationGymId.trim().isEmpty) {
        return;
      }
    }

    final selectedContainers = _selectedIndexes
        .map((index) => Map<String, dynamic>.from(widget.friendContainers[index]))
        .toList()
      ..sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

    setState(() => _isAdding = true);

    try {
      final result = await _friendProfileService.importContainers(
        friendContainers: selectedContainers,
        friendExercises: widget.friendExercises,
        insertKind: widget.insertKind,
        includeExercises: mode == _CopyMode.containerAndExercises,
        destinationGymId: destinationGymId,
      );

      if (!mounted) return;

      final message = mode == _CopyMode.containerOnly
          ? result.skippedContainers > 0
              ? "Added ${result.addedContainers} ${widget.titlePlural} • "
                  "Skipped ${result.skippedContainers} (already in destination)"
              : "Added ${result.addedContainers} ${widget.titlePlural}"
          : widget.insertKind == 'routine'
              ? "Added ${result.addedContainers} ${widget.titlePlural} "
                  "(${result.addedRoutineLinks} linked) • "
                  "Imported ${result.addedExercises} exercise(s)"
                  "${result.totalSkipped > 0 ? " • Skipped ${result.totalSkipped}" : ""}"
              : "Added ${result.addedContainers} ${widget.titlePlural} "
                  "(${result.addedExercises} exercises)"
                  "${result.totalSkipped > 0 ? " • Skipped ${result.totalSkipped}" : ""}";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(message),
        ),
      );

      _clearSelection();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Import failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Widget _buildGymFilter() {
    final gyms = _friendGyms;

    if (widget.insertKind != 'equipment' || gyms.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedValue = _selectedGymId ?? '__all__';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: DropdownButtonFormField<String>(
        initialValue: selectedValue,
        style: const TextStyle(color: Color(0xFFB5C2D0), fontWeight: FontWeight.w500),
        dropdownColor: _FriendUx.surface,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Gym',
          labelStyle: TextStyle(color: Color(0xFF9EACBD)),
          floatingLabelStyle: TextStyle(color: Color(0xFFB5C2D0)),
          prefixIcon: Icon(Icons.location_on_outlined),
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: '__all__',
            child: Text('All Gyms', style: TextStyle(color: Color(0xFFB5C2D0))),
          ),
          ...gyms.map(
            (gym) => DropdownMenuItem<String>(
              value: gym['id'],
              child: Text(gym['name'] ?? 'Gym', style: const TextStyle(color: Color(0xFFB5C2D0))),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() {
            _selectedGymId =
                value == null || value == '__all__' ? null : value;

            if (_selectMode) {
              final visible = _visibleIndexes.toSet();
              _selectedIndexes.removeWhere((i) => !visible.contains(i));
              if (_selectedIndexes.isEmpty) _selectMode = false;
            }
          });
        },
      ),
    );
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
                  selectedColor: const Color(0xFF283A48),
                  backgroundColor: const Color(0xFF1B2530),
                  labelStyle: TextStyle(
                    color: selected
                        ? const Color(0xFFD4E0EA)
                        : const Color(0xFFADB9C6),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
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
        ? "Tap a routine to select it for import."
        : "Tap equipment to select it for import.";

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          itemCount:
              visibleIndexes.length + (widget.insertKind == 'equipment' ? 3 : 2),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final hasGymFilter = widget.insertKind == 'equipment';

            if (hasGymFilter && i == 0) return _buildGymFilter();

            final contentIndex = hasGymFilter ? i - 1 : i;

            if (contentIndex == 0) return _buildMuscleFilterBar();

            if (contentIndex == 1) {
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

            final visibleIndex = visibleIndexes[contentIndex - 2];
            final c = list[visibleIndex];
            final name =
                (c['name'] ?? c['equipment_name'] ?? '').toString();
            final isSelected = _selectedIndexes.contains(visibleIndex);

            return Card(
              child: ListTile(
              leading: _selectMode
                  ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked)
                  : Icon(widget.leadingIcon),
              title: Text(name),
              trailing: _selectMode
                  ? null
                  : const Icon(Icons.add_circle_outline, color: _FriendUx.accent),
              selected: isSelected,
              onTap: () {
                if (_selectMode) {
                  _toggleSelect(visibleIndex);
                } else {
                  _enterSelectMode(visibleIndex);
                }
              },
              onLongPress: () {
                if (_selectMode) {
                  _toggleSelect(visibleIndex);
                } else {
                  _enterSelectMode(visibleIndex);
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
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                    children: [
                      Text(
                        "$selectedCount selected",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 16),
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
          ),
      ],
    );
  }
}

// ---------------- EXERCISES TAB ----------------

class _ExercisesTab extends StatefulWidget {
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> friendEquipment;

  const _ExercisesTab({required this.exercises, required this.friendEquipment});

  @override
  State<_ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends State<_ExercisesTab> {
  final _friendProfileService = FriendProfileService();

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

  String? _videoUrl(Map<String, dynamic> exercise) =>
      _friendProfileService.exerciseVideoUrl(exercise);

  Future<Map<String, dynamic>?> _pickOrCreateContainer({
    required String title,
    required String existingHint,
    required String createHint,
    required String kind, // 'equipment' or 'routine'
  }) async {
    final myList = await _friendProfileService.getMyContainers(kind: kind);

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
      return _friendProfileService.createContainer(name: typed, kind: kind);
    }

    if (selectedId != null && selectedId!.isNotEmpty) {
      final found = myList.firstWhere((e) => e['id'].toString() == selectedId);
      return found;
    }

    return null;
  }

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

    final selectedExercises = _selectedIndexes
        .map((index) => Map<String, dynamic>.from(widget.exercises[index]))
        .toList()
      ..sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

    setState(() => _isAdding = true);

    try {
      final result = await _friendProfileService.importExercisesToEquipment(
        friendExercises: selectedExercises,
        equipmentId: targetEquipmentId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            result.skippedExercises > 0
                ? "Added ${result.addedExercises} exercise(s) to "
                    "$targetEquipmentName • Skipped ${result.skippedExercises}"
                : "Added ${result.addedExercises} exercise(s) to $targetEquipmentName",
          ),
        ),
      );

      _cancelSelection();
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  /// Add selected friend exercises to one of my routines.
  Future<void> _addSelectedExercisesToRoutine() async {
    if (_selectedIndexes.isEmpty || _isAdding) return;

    final homeEquipment = await _pickOrCreateContainer(
      title: "Where should these exercises live?",
      existingHint: "Choose home equipment:",
      createHint: "Or create new equipment:",
      kind: 'equipment',
    );
    if (homeEquipment == null) return;

    final homeEquipmentId =
        (homeEquipment['id'] ?? '').toString().trim();
    final homeEquipmentName =
        (homeEquipment['name'] ?? '').toString().trim();
    if (homeEquipmentId.isEmpty) return;

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

    final selectedExercises = _selectedIndexes
        .map((index) => Map<String, dynamic>.from(widget.exercises[index]))
        .toList()
      ..sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

    setState(() => _isAdding = true);

    try {
      final result = await _friendProfileService.importExercisesToRoutine(
        friendExercises: selectedExercises,
        homeEquipmentId: homeEquipmentId,
        routineId: routineId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            result.skippedExercises > 0
                ? "Imported ${result.addedExercises} into $homeEquipmentName • "
                    "Linked ${result.addedRoutineLinks} into $routineName • "
                    "Skipped ${result.skippedExercises}"
                : "Imported ${result.addedExercises} into $homeEquipmentName • "
                    "Linked ${result.addedRoutineLinks} into $routineName",
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
    );  // test comment
  }
}
// ---------------- FRIEND FOOD LOG (read-only Meal Tracker presentation) ----------------
class _FriendFoodLogTab extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final String? error;
  const _FriendFoodLogTab({required this.rows, required this.error});
  @override
  State<_FriendFoodLogTab> createState() => _FriendFoodLogTabState();
}

class _FriendFoodLogTabState extends State<_FriendFoodLogTab> {
  final Set<DateTime> _expandedDays = <DateTime>{};

  String _formatNumber(double value) =>
      (value - value.round()).abs() < 0.01
          ? value.round().toString() : value.toStringAsFixed(1);

  String _foodDisplayName(FoodItem food) =>
      food.brand.trim().isEmpty ? food.name : '${food.name} (${food.brand})';

  Widget _macroCell(String label) => SizedBox(
        width: 44,
        child: Text(label, textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _macroValue(double value) => SizedBox(
        width: 44,
        child: Text(_formatNumber(value), textAlign: TextAlign.right),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Could not load friend food log.\n\n${widget.error}',
            textAlign: TextAlign.center),
      ));
    }

    final grouped = <DateTime, List<ConsumedFood>>{};
    for (final row in widget.rows) {
      final rawFood = row['food_items'];
      final foodMap = rawFood is Map ? rawFood
          : rawFood is List && rawFood.isNotEmpty && rawFood.first is Map
              ? rawFood.first as Map : null;
      if (foodMap == null) continue;
      final when = DateTime.tryParse((row['consumed_at'] ?? '').toString());
      if (when == null) continue;
      final local = when.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final rawServings = row['servings'];
      final servings = rawServings is num ? rawServings.toDouble()
          : double.tryParse((rawServings ?? '').toString()) ?? 0.0;
      grouped.putIfAbsent(day, () => []).add(ConsumedFood(
        id: (row['id'] ?? '').toString(),
        consumedAt: local,
        servings: servings,
        food: FoodItem.fromMap(Map<String, dynamic>.from(foodMap)),
      ));
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) {
      return const Center(child: Text('No food has been logged yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: days.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Food Log', style: Theme.of(context).textTheme.titleLarge),
        );
        final day = days[index - 1];
        final items = grouped[day]!..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
        final calories = items.fold<double>(0, (s, i) => s + i.calories);
        final protein = items.fold<double>(0, (s, i) => s + i.protein);
        final carbs = items.fold<double>(0, (s, i) => s + i.carbs);
        final fat = items.fold<double>(0, (s, i) => s + i.fat);
        final expanded = _expandedDays.contains(day);
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => setState(() {
                if (expanded) { _expandedDays.remove(day); }
                else { _expandedDays.add(day); }
              }),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${day.month}/${day.day}/${day.year}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 6, children: [
                    Text('${_formatNumber(calories)} cal',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('P ${_formatNumber(protein)}g'),
                    Text('C ${_formatNumber(carbs)}g'),
                    Text('F ${_formatNumber(fat)}g'),
                  ]),
                ]),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Row(children: [
                  Expanded(child: Text('Foods', style: Theme.of(context)
                    .textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                  _macroCell('P'), _macroCell('C'), _macroCell('F'),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Column(children: items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_foodDisplayName(item.food), maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('${_formatNumber(item.servings)} serving${item.servings == 1 ? '' : 's'} '
                        '(${_formatNumber(item.food.servingAmount)} ${item.food.servingUnit} each) '
                        '• ${_formatNumber(item.calories)} cal',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    ])),
                    _macroValue(item.protein), _macroValue(item.carbs), _macroValue(item.fat),
                  ]),
                )).toList()),
              ),
            ],
          ]),
        );
      },
    );
  }
}
