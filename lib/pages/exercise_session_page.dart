import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../theme/fitquest_theme.dart';
import '../services/exercise_service.dart';
import '../services/video_upload_manager.dart';
import '../services/session_service.dart';
import '../services/muscle_exercise_position_service.dart';
import '../services/workout_date_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseSessionPage extends StatefulWidget {
  final Map<String, dynamic> exercise;
  const ExerciseSessionPage({super.key, required this.exercise});

  @override
  State<ExerciseSessionPage> createState() => _ExerciseSessionPageState();
}

class _ExerciseSessionPageState extends State<ExerciseSessionPage> {
  final weightController = TextEditingController();
  final repsController = TextEditingController();
  final userFormNotesController = TextEditingController();
  final SessionService sessionService = SessionService();
  final WorkoutDateService _workoutDateService = WorkoutDateService.instance;
  bool _isSavingSet = false;
  final ExerciseService exerciseService = ExerciseService();
  bool _isRemovingTrainerVideo = false;
  bool _isSavingFormNotes = false;
  String _selectedMetricType = 'reps';
  String _selectedLoadType = 'weight';

  // --- Current workout and paged historical workout days
  String? todayDayKey;
  List<String> previousDayKeys = []; // All earlier days, newest first.
  int _historyPage = 0;
  String? _selectedChartDayKey;
  bool _chartDetailsExpanded = false;
  static const int _historyPageSize = 4;
  int? _currentPosition;
  final _positionService = MuscleExercisePositionService();
  Set<String> _bestReferenceDayKeys = <String>{};
  Set<int> _referencePositions = <int>{};
  String? _overallBestDayKey;
  double? _overallLongestHoldSeconds;
  bool _isLoadingHistory = true;
  int _historyRequest = 0;
  Map<String, List<Map<String, dynamic>>> sessionsByDayKey = {};
  Map<String, double> volumeByDayKey = {};
  Map<String, bool> hasVolumeByDayKey = {};
  Map<String, int> positionByDayKey = {};
  bool _metricPreferenceLoaded = false;

  // -------- Form video state --------
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedVideo;

  VideoPlayerController? _importedVideoController;
  VideoPlayerController? _userVideoController;

  bool _isLoadingVideos = true;
  bool _isUploadingVideo = false;
  final VideoUploadManager _videoUploads = VideoUploadManager.instance;
  bool _isRemovingVideo = false;

  String? _importedVideoUrl;
  String? _userVideoUrl;
  String? _sourceExerciseId;
  String? _trainerFormNotes;

  @override
  void initState() {
    super.initState();
    _workoutDateService.selectedDate.addListener(_onWorkoutDateChanged);
    _loadWorkoutHistory();
    _loadExerciseVideos();
    _videoUploads.activeExercises.addListener(_onVideoUploadStateChanged);
    _onVideoUploadStateChanged();
  }

  void _onVideoUploadStateChanged() {
    if (!mounted) return;
    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    final busy = _videoUploads.isUploading(exerciseId);
    if (_isUploadingVideo != busy) {
      setState(() => _isUploadingVideo = busy);
    }
  }

  void _onWorkoutDateChanged() {
    if (!mounted) return;
    _loadWorkoutHistory();
  }

  // ---------- Day key helpers ----------
  String _dayKey(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _todayKey() => _dayKey(_workoutDateService.activeDate);

  DateTime _dateFromDayKey(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  String _formatDate(DateTime d) => "${d.month}/${d.day}/${d.year}";

  // ---------- numeric helpers ----------
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

  String _loadLabel(String loadType) {
    return loadType == 'level' ? 'Level' : 'Weight';
  }

  String _metricLabel(String metricType) {
    switch (metricType) {
      case 'seconds':
        return 'Seconds';
      case 'minutes':
        return 'Minutes';
      case 'miles':
        return 'Miles';
      default:
        return 'Reps';
    }
  }

  double _sessionMetricValue(Map<String, dynamic> session) {
    final stored = session['metric_value'];
    if (stored != null) return _numToDouble(stored);
    return _numToDouble(session['reps']);
  }

  String _formatMetricValue(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  // Compare only sets recorded with the currently selected measurement.
  // Old weight/reps records remain in history, but cannot become timed PRs.
  bool _matchesPerformanceMetric(Map<String, dynamic> session) =>
      (session['metric_type'] ?? 'reps').toString() == _selectedMetricType &&
      (session['load_type'] ?? 'weight').toString() == _selectedLoadType;

  double _comparableMetricValue(Map<String, dynamic> session) {
    final value = _sessionMetricValue(session);
    return _selectedMetricType == 'minutes' ? value * 60 : value;
  }

  // Keep weight/reps volume unchanged. Timed workouts use total duration
  // across matching sets; a longest uninterrupted hold is tracked separately.
  double? _dayPerformance(List<Map<String, dynamic>> sessions) {
    final comparable = sessions.where(_matchesPerformanceMetric).toList();
    if (comparable.isEmpty) return null;
    if (_selectedLoadType == 'weight' && _selectedMetricType == 'reps') {
      return comparable.fold<double>(0, (sum, row) =>
          sum + _numToDouble(row['weight']) * _sessionMetricValue(row));
    }
    if (_selectedMetricType == 'seconds' || _selectedMetricType == 'minutes') {
      return comparable.fold<double>(0, (sum, row) =>
          sum + _comparableMetricValue(row));
    }
    // Preserve the existing single-set benchmark for non-timed metrics.
    var best = 0.0;
    for (final row in comparable) {
      final value = _comparableMetricValue(row);
      if (value > best) best = value;
    }
    return best;
  }

  double? _longestHoldForDay(List<Map<String, dynamic>> sessions) {
    if (_selectedMetricType != 'seconds' && _selectedMetricType != 'minutes') {
      return null;
    }
    double? longest;
    for (final row in sessions.where(_matchesPerformanceMetric)) {
      final seconds = _comparableMetricValue(row);
      if (longest == null || seconds > longest) longest = seconds;
    }
    return longest;
  }

  String get _performanceLabel {
    if (_selectedLoadType == 'weight' && _selectedMetricType == 'reps') {
      return 'VOLUME';
    }
    switch (_selectedMetricType) {
      case 'seconds':
      case 'minutes': return 'DURATION';
      case 'miles': return 'DISTANCE';
      default: return 'REPS';
    }
  }

  String _performanceValue(double value) {
    if (_selectedLoadType == 'weight' && _selectedMetricType == 'reps') {
      return value.toStringAsFixed(0);
    }
    if (_selectedMetricType == 'minutes') {
      // Duration benchmarks are stored internally in seconds for comparison.
      // Display them in the unit selected by the user.
      return '${_formatMetricValue(value / 60)} min';
    }
    if (_selectedMetricType == 'seconds') {
      return '${_formatMetricValue(value)} sec';
    }
    if (_selectedMetricType == 'miles') return '${_formatMetricValue(value)} mi';
    return '${_formatMetricValue(value)} reps';
  }

  // Difficulty is an independent record: level 7 for two minutes must not
  // be compared by multiplying 7 x 2 against level 3 for five minutes.
  double? _highestLevelForDay(List<Map<String, dynamic>> sessions) {
    if (_selectedLoadType != 'level') return null;
    final matching = sessions.where(_matchesPerformanceMetric);
    double? highest;
    for (final row in matching) {
      final level = _numToDouble(row['weight']);
      if (highest == null || level > highest) highest = level;
    }
    return highest;
  }

  // The most recent saved set is the preference for this exercise.
  // A new exercise keeps the default Weight + Reps.
  void _restoreMetricPreference(List<Map<String, dynamic>> sessions) {
    if (_metricPreferenceLoaded || sessions.isEmpty) return;
    final latest = List<Map<String, dynamic>>.from(sessions)
      ..sort((a, b) => (b['created_at'] ?? '').toString()
          .compareTo((a['created_at'] ?? '').toString()));
    final row = latest.first;
    final load = (row['load_type'] ?? 'weight').toString();
    final metric = (row['metric_type'] ?? 'reps').toString();
    _selectedLoadType = ['weight', 'level'].contains(load) ? load : 'weight';
    _selectedMetricType = ['reps', 'seconds', 'minutes', 'miles'].contains(metric)
        ? metric : 'reps';
    _metricPreferenceLoaded = true;
  }

  // Persistent exercise order is assigned atomically when a set is saved.
  // Older records without an order remain unclassified rather than guessing.
  bool _hasStoredOrder(List<Map<String, dynamic>> sessions) {
    return sessions.any((session) {
      final raw = session['exercise_order'];
      final order = raw is num ? raw.toInt() : int.tryParse('$raw');
      return order != null && order > 0;
    });
  }

  String _positionLabel(int n) => MuscleExercisePositionService.label(
      n, (widget.exercise['primary_muscle_group'] ?? '').toString());

  // ---------- Sessions and muscle-position-aware history ----------
  Future<List<Map<String, dynamic>>> _fetchAllExerciseSessions(
    String userId,
    String exerciseId,
    DateTime activeDate,
  ) async {
    final endUtc = DateTime(activeDate.year, activeDate.month,
            activeDate.day + 1)
        .toUtc()
        .toIso8601String();
    final all = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final page = await Supabase.instance.client
          .from('exercise_sessions')
          .select()
          .eq('user_id', userId)
          .eq('exercise_id', exerciseId)
          .lt('created_at', endUtc)
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      all.addAll(page.map((r) => Map<String, dynamic>.from(r)));
      if (page.length < pageSize) break;
    }
    return all;
  }

  Future<int?> _resolveCurrentPosition(String userId, String exerciseId,
      DateTime activeDate) async {
    await sessionService.backfillExerciseOrdersForDate(activeDate);
    final positions = await _positionService.positionsForDay(activeDate);
    if (positions.containsKey(exerciseId)) return positions[exerciseId];
    // The next distinct exercise in this muscle group, if not yet logged.
    final muscle = (widget.exercise['primary_muscle_group'] ?? '').toString().trim();
    if (muscle.isEmpty) return null;
    final start = DateTime(activeDate.year, activeDate.month, activeDate.day);
    final end = DateTime(activeDate.year, activeDate.month, activeDate.day + 1);
    final rows = await Supabase.instance.client.from('exercise_sessions')
        .select('exercise_id, exercises!inner(primary_muscle_group)')
        .eq('user_id', userId)
        .gte('created_at', start.toUtc().toIso8601String())
        .lt('created_at', end.toUtc().toIso8601String());
    final ids = <String>{};
    for (final row in rows) {
      final ex = row['exercises'];
      if (ex is Map && (ex['primary_muscle_group'] ?? '').toString().trim().toLowerCase() == muscle.toLowerCase()) {
        ids.add(row['exercise_id'].toString());
      }
    }
    return ids.length + 1;
  }

  Future<void> _loadWorkoutHistory() async {
    final user = Supabase.instance.client.auth.currentUser;
    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    if (user == null || exerciseId.isEmpty) return;
    final request = ++_historyRequest;
    final activeKey = _todayKey();
    final activeDate = _dateFromDayKey(activeKey);
    if (mounted) setState(() => _isLoadingHistory = true);

    try {
      // Restore the exercise's most recently used metric selection, including
      // when viewing an older backlog date.
      if (!_metricPreferenceLoaded) {
        final latestRows = await Supabase.instance.client
            .from('exercise_sessions')
            .select('created_at, metric_type, load_type')
            .eq('user_id', user.id)
            .eq('exercise_id', exerciseId)
            .order('created_at', ascending: false)
            .limit(1);
        if (latestRows.isNotEmpty && mounted && request == _historyRequest) {
          setState(() => _restoreMetricPreference(
              latestRows.map((row) => Map<String, dynamic>.from(row)).toList()));
        }
      }

      // Begin current-position work concurrently with the history fetch.
      final currentPositionFuture = _resolveCurrentPosition(
          user.id, exerciseId, activeDate);
      final rows = await _fetchAllExerciseSessions(
          user.id, exerciseId, activeDate);
      final map = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final dt = DateTime.tryParse((row['created_at'] ?? '').toString());
        if (dt == null) continue;
        final key = _dayKey(dt);
        if (key.compareTo(activeKey) > 0) continue;
        map.putIfAbsent(key, () => []).add(row);
      }
      map.putIfAbsent(activeKey, () => []);

      // First paint: show saved workout days immediately after the history
      // query, without waiting for legacy-order repairs or position lookups.
      // Performance is calculated from matching metric types, so the initial
      // cards contain real sets without mixing incompatible measurements.
      final immediateKeys = map.keys
          .where((key) => key.compareTo(activeKey) < 0)
          .toList()..sort((a, b) => b.compareTo(a));
      final immediateVolume = <String, double>{};
      final immediateHasVolume = <String, bool>{};
      for (final entry in map.entries) {
        final performance = _dayPerformance(entry.value);
        final volume = performance ?? 0.0;
        final hasVolume = performance != null;
        immediateVolume[entry.key] = volume;
        immediateHasVolume[entry.key] = hasVolume;
      }
      final immediateLongestHold = map.values
          .map(_longestHoldForDay)
          .whereType<double>()
          .fold<double?>(null, (best, value) =>
              best == null || value > best ? value : best);
      String? immediateBestKey;
      double? immediateBestVolume;
      for (final key in immediateKeys) {
        if (immediateHasVolume[key] != true) continue;
        final volume = immediateVolume[key]!;
        if (immediateBestVolume == null || volume > immediateBestVolume) {
          immediateBestVolume = volume;
          immediateBestKey = key;
        }
      }
      if (immediateHasVolume[activeKey] == true &&
          (immediateBestVolume == null ||
              immediateVolume[activeKey]! > immediateBestVolume)) {
        immediateBestKey = activeKey;
      }
      if (mounted && request == _historyRequest && _todayKey() == activeKey) {
        setState(() {
          todayDayKey = map[activeKey]!.isNotEmpty ? activeKey : null;
          previousDayKeys = immediateKeys;
          sessionsByDayKey = Map.of(map);
          volumeByDayKey = immediateVolume;
          hasVolumeByDayKey = immediateHasVolume;
          positionByDayKey = {};
          _bestReferenceDayKeys = immediateBestKey == null
              ? <String>{} : <String>{immediateBestKey};
          _referencePositions = {};
          _overallBestDayKey = immediateBestKey;
          _overallLongestHoldSeconds = immediateLongestHold;
          if (_historyPage * _historyPageSize >= immediateKeys.length) {
            _historyPage = 0;
          }
          _isLoadingHistory = false;
        });
      }

      // Historical sessions may predate persistent exercise_order. Backfill
      // only days that need it, and re-read the affected exercise's sets.
      for (final key in map.keys.toList()) {
        final sessions = map[key]!;
        if (sessions.isEmpty || _hasStoredOrder(sessions)) continue;
        final day = _dateFromDayKey(key);
        await sessionService.backfillExerciseOrdersForDate(day);
        map[key] = await sessionService.getSessionsForDate(exerciseId, day);
      }

      final currentPosition = await currentPositionFuture;
      final priorKeys = map.keys.where((key) => key.compareTo(activeKey) < 0)
          .toList()..sort((a, b) => b.compareTo(a));
      final volMap = <String, double>{};
      final hasVolMap = <String, bool>{};
      final positionMap = <String, int>{};
      // Fetch historical positions concurrently in small batches instead of
      // waiting for a network round-trip for every single workout day.
      // Keep the batch bounded to avoid flooding Supabase on long histories.
      final positionCache = <String, Map<String, int>>{};
      final positionKeys = map.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => entry.key)
          .toList();
      const positionBatchSize = 6;
      for (var i = 0; i < positionKeys.length; i += positionBatchSize) {
        final batch = positionKeys.skip(i).take(positionBatchSize).toList();
        final positions = await Future.wait(batch.map((key) =>
            _positionService.positionsForDay(_dateFromDayKey(key))));
        for (var j = 0; j < batch.length; j++) {
          positionCache[batch[j]] = positions[j];
        }
      }
      for (final entry in map.entries) {
        final performance = _dayPerformance(entry.value);
        final volume = performance ?? 0.0;
        final hasVolume = performance != null;
        volMap[entry.key] = volume;
        hasVolMap[entry.key] = hasVolume;
        if (entry.value.isNotEmpty) {
          final position = positionCache[entry.key]?[exerciseId];
          if (position != null) positionMap[entry.key] = position;
        }
      }

      final overallLongestHold = map.values
          .map(_longestHoldForDay)
          .whereType<double>()
          .fold<double?>(null, (best, value) =>
              best == null || value > best ? value : best);

      // Compare the active measurement independently of exercise order.
      // Also retain the best matching performance at each position.
      final bestVolumeByPosition = <int, double>{};
      double? overallBestVolume;
      String? overallBestKey;
      for (final key in priorKeys) {
        if (hasVolMap[key] != true) continue;
        final volume = volMap[key]!;
        final position = positionMap[key];
        if (position != null &&
            (bestVolumeByPosition[position] == null ||
                volume > bestVolumeByPosition[position]!)) {
          bestVolumeByPosition[position] = volume;
        }
        // Prior keys are newest first: equal volumes prefer the newer day.
        if (overallBestVolume == null || volume > overallBestVolume) {
          overallBestVolume = volume;
          overallBestKey = key;
        }
      }
      final bestKeys = <String>{};
      for (final key in priorKeys) {
        final position = positionMap[key];
        if (position != null && hasVolMap[key] == true &&
            volMap[key] == bestVolumeByPosition[position]) {
          bestKeys.add(key);
        }
      }
      // The active workout day can supersede the historical overall best.
      // A tie retains the existing historical record; only a strictly higher
      // matching performance earns the new overall-best highlight.
      if (hasVolMap[activeKey] == true &&
          (overallBestVolume == null ||
              volMap[activeKey]! > overallBestVolume)) {
        overallBestVolume = volMap[activeKey]!;
        overallBestKey = activeKey;
      }

      // Include the overall best even when its exercise position is unknown.
      if (overallBestKey != null) bestKeys.add(overallBestKey);
      final referencePositions = bestVolumeByPosition.keys.toSet();

      if (!mounted || request != _historyRequest || _todayKey() != activeKey) {
        return;
      }
      setState(() {
        todayDayKey = map[activeKey]!.isNotEmpty ? activeKey : null;
        previousDayKeys = priorKeys;
        sessionsByDayKey = map;
        volumeByDayKey = volMap;
        hasVolumeByDayKey = hasVolMap;
        positionByDayKey = positionMap;
        _currentPosition = currentPosition;
        _bestReferenceDayKeys = bestKeys;
        _referencePositions = referencePositions;
        _overallBestDayKey = overallBestKey;
        _overallLongestHoldSeconds = overallLongestHold;
        if (_historyPage * _historyPageSize >= priorKeys.length) {
          _historyPage = 0;
        }
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted || request != _historyRequest) return;
      setState(() => _isLoadingHistory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load workout history: $e')),
      );
    }
  }

  Future<void> _saveSet() async {
    if (_isSavingSet) return;
    final weight = double.tryParse(weightController.text.trim());
    final metricValue = double.tryParse(repsController.text.trim());
    if (weight == null || metricValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid load and metric value.')),
      );
      return;
    }
    if (_selectedMetricType == 'reps' && metricValue != metricValue.roundToDouble()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reps must be a whole number.')),
      );
      return;
    }
    setState(() => _isSavingSet = true);
    bool sessionSaved = false;
    try {
      final res = await sessionService.insertSession(
        exerciseId: widget.exercise['id'].toString(),
        weight: weight,
        metricType: _selectedMetricType,
        metricValue: metricValue,
        loadType: _selectedLoadType,
      );
      sessionSaved = true;
      // Only call XP once for a newly inserted session. Never automatically
      // retry the RPC, since the database function is not idempotent.
      await Supabase.instance.client.rpc(
        'add_session_xp',
        params: {'session_id': res['id']},
      );
      if (!mounted) return;
      weightController.clear();
      repsController.clear();
      await _loadWorkoutHistory();
    } catch (e) {
      if (!mounted) return;
      // The session may already be committed even if XP failed. Do not retry
      // saving automatically; that could create duplicate sets.
      if (sessionSaved) await _loadWorkoutHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sessionSaved
          ? 'Set saved, but XP confirmation failed. Check history before trying again. $e'
          : 'Could not save set: $e'),
      ));
    } finally {
      if (mounted) setState(() => _isSavingSet = false);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    await _loadWorkoutHistory();
  }

  Future<void> _editSession(Map<String, dynamic> session) async {
    final weightEditController = TextEditingController(
      text: _numToDouble(session['weight']).toString().replaceFirst(RegExp(r'\.0$'), ''),
    );
    final metricEditController = TextEditingController(
      text: _formatMetricValue(_sessionMetricValue(session)),
    );
    var metricType = (session['metric_type'] ?? 'reps').toString();
    var loadType = (session['load_type'] ?? 'weight').toString();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit set'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: weightEditController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _loadLabel(loadType),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: ['weight', 'level'].map((type) {
                    return SizedBox(
                      width: 112,
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(_loadLabel(type), style: const TextStyle(fontSize: 13)),
                        value: loadType == type,
                        onChanged: (checked) {
                          if (checked == true) {
                            setDialogState(() => loadType = type);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: metricEditController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _metricLabel(metricType),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: ['reps', 'seconds', 'minutes', 'miles'].map((type) {
                    return SizedBox(
                      width: 112,
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(_metricLabel(type), style: const TextStyle(fontSize: 13)),
                        value: metricType == type,
                        onChanged: (checked) {
                          if (checked == true) {
                            setDialogState(() => metricType = type);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (save != true) return;

    final weight = double.tryParse(weightEditController.text.trim());
    final metricValue = double.tryParse(metricEditController.text.trim());
    if (weight == null || metricValue == null) return;
    if (metricType == 'reps' && metricValue != metricValue.roundToDouble()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reps must be a whole number.')),
      );
      return;
    }

    await sessionService.updateSession(
      sessionId: session['id'].toString(),
      weight: weight,
      metricType: metricType,
      metricValue: metricValue,
      loadType: loadType,
    );

    await _loadWorkoutHistory();
  }

  Future<void> _saveUserFormNotes() async {
    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    if (exerciseId.isEmpty) return;

    setState(() => _isSavingFormNotes = true);
    try {
      final notes = userFormNotesController.text.trim();
      await Supabase.instance.client
          .from('exercises')
          .update({'form_notes': notes.isEmpty ? null : notes})
          .eq('id', exerciseId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form tips saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save form tips: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingFormNotes = false);
    }
  }

  Future<void> _removeTrainerVideo() async {
  final hasTrainerVideo =
      (_importedVideoUrl ?? '').trim().isNotEmpty &&
      (_sourceExerciseId ?? '').trim().isNotEmpty;

  if (!hasTrainerVideo) return;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Remove trainer video?'),
      content: const Text(
        'This will remove the imported trainer video from this exercise. '
        'Your own uploaded form video will not be affected.',
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

  final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
  if (exerciseId.isEmpty) return;

  setState(() => _isRemovingTrainerVideo = true);

  try {
    await exerciseService.removeImportedTrainerVideo(
      exerciseId: exerciseId,
    );

    await _disposeController(_importedVideoController);

    if (!mounted) return;

    setState(() {
      _importedVideoUrl = null;
      _sourceExerciseId = null;
      _importedVideoController = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trainer video removed from this exercise.'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to remove trainer video: $e'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() => _isRemovingTrainerVideo = false);
    }
  }
}

  Widget _buildWorkoutDayCard({
    required String dayKey,
    required String title,
    bool initiallyExpanded = false,
  }) {
    final sessions = sessionsByDayKey[dayKey] ?? const [];
    final volume = volumeByDayKey[dayKey] ?? 0;
    final showVolume = hasVolumeByDayKey[dayKey] ?? false;
    final position = positionByDayKey[dayKey];
    final isBestMatch = _bestReferenceDayKeys.contains(dayKey);
    final isOverallBest = dayKey == _overallBestDayKey;
    final isReferencePosition = dayKey != _todayKey() &&
        position != null && _referencePositions.contains(position);
    final isExactPosition = position == _currentPosition;
    final theme = FitQuestTheme.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isOverallBest ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isOverallBest
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : isReferencePosition
                ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5))
                : const BorderSide(color: FitQuestTheme.outline),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title  •  ${sessions.length} ${sessions.length == 1 ? 'set' : 'sets'}',
                style: theme.textTheme.titleSmall),
            if (isBestMatch)
              Text(isOverallBest
                  ? 'OVERALL BEST $_performanceLabel'
                  : 'BEST AT THIS POSITION',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
            if (isReferencePosition && !isBestMatch)
              Text(isExactPosition ? 'SAME EXERCISE POSITION' : 'POSITION HISTORY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
            if (showVolume)
              Text('${_performanceLabel == 'VOLUME' ? 'Volume' : _performanceLabel == 'DURATION' ? 'Total duration' : 'Best $_performanceLabel'}: ${_performanceValue(volume)}',
                  style: FitQuestTheme.dark.textTheme.bodySmall),
            if (_longestHoldForDay(sessions) != null)
              Text(
                'Longest hold: ${_performanceValue(_longestHoldForDay(sessions)!)}'
                '${_longestHoldForDay(sessions) == _overallLongestHoldSeconds ? '  •  PERSONAL BEST' : ''}',
                style: FitQuestTheme.dark.textTheme.bodySmall,
              ),
            if (_highestLevelForDay(sessions) != null)
              Text('Highest level: ${_formatMetricValue(_highestLevelForDay(sessions)!)}',
                  style: FitQuestTheme.dark.textTheme.bodySmall),
            if (position != null)
              Text(_positionLabel(position),
                  style: FitQuestTheme.dark.textTheme.bodySmall),
          ],
        ),
        children: sessions.isEmpty
            ? const [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No sets found for this day.'),
                ),
              ]
            : sessions.map((session) {
                final metricType = (session['metric_type'] ?? 'reps').toString();
                final loadType = (session['load_type'] ?? 'weight').toString();
                final metricValue = _sessionMetricValue(session);
                final setVolume = metricType == 'reps' && loadType == 'weight'
                    ? _numToDouble(session['weight']) * metricValue
                    : null;

                return Dismissible(
                  key: Key(session['id'].toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    color: Colors.red,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) =>
                      _deleteSession(session['id'].toString()),
                  child: ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: Text('${_loadLabel(loadType)}: ${session['weight']}'),
                    subtitle: Text(
                      '${_metricLabel(metricType)}: ${_formatMetricValue(metricValue)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (setVolume != null)
                          Text(
                            'Vol: ${setVolume.toStringAsFixed(0)}',
                            style: FitQuestTheme.dark.textTheme.bodySmall,
                          ),
                        IconButton(
                          tooltip: 'Edit set',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editSession(session),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
      ),
    );
  }

  // Chronological performance chart. Uses the same metric-filtered daily
  // values as the history cards; no inferred positions for legacy records.
  Widget _buildProgressChart() {
    final keys = volumeByDayKey.keys
        .where((key) => hasVolumeByDayKey[key] == true)
        .toList()..sort();
    if (keys.isEmpty) return const SizedBox.shrink();

    final values = keys.map((key) => volumeByDayKey[key]!).toList();
    final best = values.reduce(math.max);
    final selectedKey = keys.contains(_selectedChartDayKey)
        ? _selectedChartDayKey! : keys.last;
    final selectedIndex = keys.indexOf(selectedKey);
    final selectedPosition = positionByDayKey[selectedKey];
    final selectedSessions = sessionsByDayKey[selectedKey] ?? const <Map<String, dynamic>>[];
    final pointWidth = 74.0;
    final plotWidth = math.max(300.0, keys.length * pointWidth + 36);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exercise progress', style: FitQuestTheme.dark.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('$_performanceLabel over time • Order = position in muscle-group workout',
                style: FitQuestTheme.dark.textTheme.bodySmall),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final index = ((details.localPosition.dx - 18) / pointWidth)
                        .round().clamp(0, keys.length - 1);
                    setState(() {
                      _selectedChartDayKey = keys[index];
                      // Keep details open to compare sets between points.
                    });
                  },
                  child: CustomPaint(
                    size: Size(math.max(plotWidth, constraints.maxWidth), 224),
                    painter: _ExerciseProgressPainter(
                      values: values,
                      positions: keys.map((key) => positionByDayKey[key]).toList(),
                      dates: keys.map((key) => _dateFromDayKey(key)).toList(),
                      selectedIndex: selectedIndex,
                      bestValue: best,
                      accent: FitQuestTheme.dark.colorScheme.primary,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: FitQuestTheme.dark.colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() =>
                        _chartDetailsExpanded = !_chartDetailsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_formatDate(_dateFromDayKey(selectedKey))}  •  ${_performanceValue(values[selectedIndex])}',
                                  style: FitQuestTheme.dark.textTheme.titleSmall,
                                ),
                                Text(
                                  'Muscle-group order: ${selectedPosition == null ? 'Not recorded' : _positionLabel(selectedPosition)}  •  ${selectedSessions.length} sets${values[selectedIndex] == best ? '  •  Best performance' : ''}',
                                  style: FitQuestTheme.dark.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Icon(_chartDetailsExpanded
                              ? Icons.expand_less : Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                  if (_chartDetailsExpanded) ...[
                    Divider(height: 1, color: FitQuestTheme.dark.dividerColor),
                    if (selectedSessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No sets recorded for this workout.'),
                      )
                    else
                      ...selectedSessions.asMap().entries.map((entry) {
                        final session = entry.value;
                        final metricType =
                            (session['metric_type'] ?? 'reps').toString();
                        final loadType =
                            (session['load_type'] ?? 'weight').toString();
                        final metricValue = _sessionMetricValue(session);
                        final setVolume = metricType == 'reps' && loadType == 'weight'
                            ? _numToDouble(session['weight']) * metricValue
                            : null;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.fitness_center),
                          title: Text('Set ${entry.key + 1}  •  ${_loadLabel(loadType)}: ${_formatMetricValue(_numToDouble(session['weight']))}'),
                          subtitle: Text('${_metricLabel(metricType)}: ${_formatMetricValue(metricValue)}'),
                          trailing: setVolume == null
                              ? null
                              : Text('Vol: ${setVolume.toStringAsFixed(0)}',
                                  style: FitQuestTheme.dark.textTheme.bodySmall),
                        );
                      }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('Tap a point to inspect it, then tap the summary to view its sets. Swipe horizontally for older workouts. An em dash means order was not recorded.',
                style: FitQuestTheme.dark.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // ---------- Exercise videos ----------
  Future<void> _disposeController(
    VideoPlayerController? controller,
  ) async {
    await controller?.dispose();
  }

  Future<VideoPlayerController?> _createNetworkController(
    String? url,
  ) async {
    final cleanedUrl = (url ?? '').trim();
    if (cleanedUrl.isEmpty) return null;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(cleanedUrl),
    );

    try {
      await controller.initialize();
      await controller.setVolume(1.0);
      await controller.setPlaybackSpeed(1.0);
      await controller.setLooping(false);
      // Ask the browser to decode the opening frame before playback.
      await controller.seekTo(Duration.zero);
      await controller.pause();
      return controller;
    } catch (_) {
      await controller.dispose();
      return null;
    }
  }

  Future<void> _loadExerciseVideos() async {
    if (mounted) {
      setState(() => _isLoadingVideos = true);
    }

    try {
      final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
      if (exerciseId.isEmpty) return;

      final videos = await exerciseService.getExerciseVideos(
        exerciseId: exerciseId,
        passedExercise: widget.exercise,
      );

      final importedController = await _createNetworkController(
        videos.importedVideoUrl,
      );
      final userController = await _createNetworkController(
        videos.userVideoUrl,
      );

      await _disposeController(_importedVideoController);
      await _disposeController(_userVideoController);

      if (!mounted) {
        await importedController?.dispose();
        await userController?.dispose();
        return;
      }

      setState(() {
        _importedVideoUrl = videos.importedVideoUrl;
        _userVideoUrl = videos.userVideoUrl;
        _sourceExerciseId = videos.sourceExerciseId;
        _trainerFormNotes = videos.importedFormNotes;
        userFormNotesController.text = videos.userFormNotes ?? '';
        _importedVideoController = importedController;
        _userVideoController = userController;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load form videos: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingVideos = false);
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video == null) return;

      VideoPlayerController previewController;

      if (kIsWeb) {
        previewController = VideoPlayerController.networkUrl(
          Uri.parse(video.path),
        );
      } else {
        previewController = VideoPlayerController.file(
          File(video.path),
        );
      }

      await previewController.initialize();
      await previewController.setVolume(1.0);
      await previewController.setPlaybackSpeed(1.0);
      await previewController.setLooping(false);
      // Show the selected video's opening frame while awaiting upload.
      await previewController.seekTo(Duration.zero);
      await previewController.pause();

      await _disposeController(_userVideoController);

      if (!mounted) {
        await previewController.dispose();
        return;
      }

      setState(() {
        _pickedVideo = video;
        _userVideoController = previewController;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Picking video failed: $e')),
      );
    }
  }

  void _uploadPickedVideo() {
    final video = _pickedVideo;
    if (video == null) return;

    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    if (exerciseId.isEmpty || _videoUploads.isUploading(exerciseId)) return;

    // Start the manager first: this immediately shows the global notice and
    // starts the queued upload, even if this page is navigated away from.
    final upload = _videoUploads.start(
      context: context,
      exerciseId: exerciseId,
      video: video,
      exerciseName: (widget.exercise['name'] ?? 'Exercise').toString(),
    );

    // The preview is no longer needed. Detach it from page state immediately,
    // then release it without blocking the upload or its floating notice.
    final previewController = _userVideoController;
    setState(() {
      _pickedVideo = null;
      _userVideoController = null;
    });
    if (previewController != null) {
      previewController.dispose();
    }

    _finishUploadOnPage(upload);
  }

  Future<void> _finishUploadOnPage(Future<String> upload) async {
    try {
      final publicUrl = await upload;
      if (!mounted) return;
      final controller = await _createNetworkController(publicUrl);
      if (!mounted) {
        await controller?.dispose();
        return;
      }
      await _disposeController(_userVideoController);
      if (!mounted) {
        await controller?.dispose();
        return;
      }
      setState(() {
        _userVideoUrl = publicUrl;
        _userVideoController = controller;
      });
    } catch (_) {
      // The global notice reports failures even if this page was closed.
    }
  }

  Future<void> _removeUserFormVideo() async {
    final hasSavedUserVideo = (_userVideoUrl ?? '').trim().isNotEmpty;
    final hasPickedVideo = _pickedVideo != null;

    if (!hasSavedUserVideo && !hasPickedVideo) return;

    if (hasPickedVideo && !hasSavedUserVideo) {
      await _disposeController(_userVideoController);

      if (!mounted) return;
      setState(() {
        _pickedVideo = null;
        _userVideoController = null;
      });
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(
        data: FitQuestTheme.dark,
        child: AlertDialog(
        title: const Text('Remove your form video?'),
        content: const Text(
          'This removes only your uploaded video. '
          'The imported trainer video will remain available.',
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
      ),
    );

    if (confirm != true) return;

    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    if (exerciseId.isEmpty) return;

    setState(() => _isRemovingVideo = true);

    try {
      await exerciseService.removeUserFormVideo(
        exerciseId: exerciseId,
        userVideoUrl: _userVideoUrl,
      );

      await _disposeController(_userVideoController);

      if (!mounted) return;

      setState(() {
        _userVideoUrl = null;
        _userVideoController = null;
        _pickedVideo = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your form video was removed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove video: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRemovingVideo = false);
      }
    }
  }

  Widget _buildVideoPlayerCard({
    required String title,
    required String emptyMessage,
    required VideoPlayerController? controller,
    required String? videoUrl,
    String? subtitle,
    String? formNotes,
  }) {
    final hasUrl = (videoUrl ?? '').trim().isNotEmpty;
    final isReady = controller != null && controller.value.isInitialized;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: FitQuestTheme.dark.textTheme.titleSmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: FitQuestTheme.dark.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            if (isReady) ...[
              AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: VideoPlayer(controller),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: () async {
                      if (controller.value.isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.setVolume(1.0);
                        await controller.play();
                      }

                      if (mounted) setState(() {});
                    },
                  ),
                  const Spacer(),
                  if (hasUrl) const Text('Saved ✓'),
                ],
              ),
            ] else
              Text(
                hasUrl ? 'Loading video...' : emptyMessage,
                style: FitQuestTheme.dark.textTheme.bodySmall,
              ),
            if ((formNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: FitQuestTheme.dark.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formNotes!.trim(),
                  style: FitQuestTheme.dark.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _workoutDateService.selectedDate.removeListener(_onWorkoutDateChanged);
    _videoUploads.activeExercises.removeListener(_onVideoUploadStateChanged);
    weightController.dispose();
    repsController.dispose();
    userFormNotesController.dispose();
    _importedVideoController?.dispose();
    _userVideoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final isBacklogging = _workoutDateService.isBacklogging;
    final activeWorkoutDate = _workoutDateService.activeDate;

    return Theme(
      data: FitQuestTheme.dark,
      child: Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: Text(
          (exercise['name'] ?? 'Exercise').toString(),
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBacklogging) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Backlog Workout'),
                  subtitle: Text('Logging for ${_formatDate(activeWorkoutDate)}'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // ----------------- Log Form -----------------
            const FitQuestSectionHeader(
              title: 'Log your session',
              subtitle: 'One set at a time. Every rep counts.',
              icon: Icons.fitness_center,
            ),
            Row(children: [
              Expanded(child: FitQuestMetricTile(
                label: 'EXERCISE POSITION',
                value: _currentPosition == null ? '—' : _positionLabel(_currentPosition!),
                icon: Icons.layers_outlined,
              )),
              const SizedBox(width: 12),
              Expanded(child: FitQuestMetricTile(
                label: 'SETS LOGGED',
                value: '${sessionsByDayKey[_todayKey()]?.length ?? 0}',
                icon: Icons.check_circle_outline,
                accentColor: FitQuestTheme.mint,
              )),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _loadLabel(_selectedLoadType),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: ['weight', 'level'].map((type) {
                return SizedBox(
                  width: 112,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_loadLabel(type), style: const TextStyle(fontSize: 13)),
                    value: _selectedLoadType == type,
                    onChanged: (checked) {
                      if (checked == true) {
                        setState(() { _selectedLoadType = type; _metricPreferenceLoaded = true; });
                        _loadWorkoutHistory();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: repsController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _metricLabel(_selectedMetricType),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: ['reps', 'seconds', 'minutes', 'miles'].map((type) {
                return SizedBox(
                  width: 112,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_metricLabel(type), style: const TextStyle(fontSize: 13)),
                    value: _selectedMetricType == type,
                    onChanged: (checked) {
                      if (checked == true) {
                        setState(() { _selectedMetricType = type; _metricPreferenceLoaded = true; });
                        _loadWorkoutHistory();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(_isSavingSet ? "Saving..." : "Save Set"),
                onPressed: _isSavingSet ? null : _saveSet,
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 24),

            // ----------------- Today's Workout -----------------
            FitQuestSectionHeader(
              title: isBacklogging ? 'Selected workout day' : "Today's workout",
              icon: Icons.today_outlined,
            ),
            const SizedBox(height: 8),
            Text(
              isBacklogging
                  ? "Sets for ${_formatDate(activeWorkoutDate)} appear here. Existing sets are preserved when you add more."
                  : "Today's recorded sets appear here.",
              style: FitQuestTheme.dark.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (todayDayKey == null)
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isBacklogging
                              ? "No sets recorded for this exercise on ${_formatDate(activeWorkoutDate)}."
                              : "No sets have been recorded for this exercise today.",
                          style: FitQuestTheme.dark.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildWorkoutDayCard(
                dayKey: todayDayKey!,
                title: isBacklogging ? _formatDate(activeWorkoutDate) : "Today",
                initiallyExpanded: true,
              ),

            const SizedBox(height: 20),

            // ----------------- Historical progress chart -----------------
            _buildProgressChart(),
            const SizedBox(height: 20),

            // ----------------- Paged Previous Days -----------------
            const FitQuestSectionHeader(
              title: 'Previous days',
              icon: Icons.history,
            ),
            const SizedBox(height: 8),
            Text(
              isBacklogging
                  ? 'Earlier workout days before the selected backlog date. '
                    'Best performance for the selected metric is highlighted; position-specific bests are also marked.'
                  : 'Browse all previous workout days, four at a time. '
                    'Best performance for the selected metric is highlighted; position-specific bests are also marked.',
              style: FitQuestTheme.dark.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_isLoadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (previousDayKeys.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('No previous workout days for this exercise.'),
                ),
              )
            else ...[
              ...previousDayKeys
                  .skip(_historyPage * _historyPageSize)
                  .take(_historyPageSize)
                  .map((key) => _buildWorkoutDayCard(
                        dayKey: key,
                        title: _formatDate(_dateFromDayKey(key)),
                      )),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _historyPage == 0
                        ? null
                        : () => setState(() => _historyPage--),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Newer'),
                  ),
                  Text(
                    '${_historyPage + 1} / '
                    '${(previousDayKeys.length + _historyPageSize - 1) ~/ _historyPageSize}',
                    style: FitQuestTheme.dark.textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    onPressed: (_historyPage + 1) * _historyPageSize >=
                            previousDayKeys.length
                        ? null
                        : () => setState(() => _historyPage++),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Older'),
                  ),
                ],
              ),
              ...(_bestReferenceDayKeys.toList()
                    ..sort((a, b) => (positionByDayKey[a] ?? 0)
                        .compareTo(positionByDayKey[b] ?? 0)))
                  .where((key) => key != _todayKey() && !previousDayKeys
                      .skip(_historyPage * _historyPageSize)
                      .take(_historyPageSize)
                      .contains(key))
                  .map((key) => TextButton.icon(
                        onPressed: () => setState(() {
                          _historyPage = previousDayKeys.indexOf(key) ~/
                              _historyPageSize;
                        }),
                        icon: const Icon(Icons.emoji_events_outlined),
                        label: Text(key == _overallBestDayKey
                             ? 'Jump to overall best ${_performanceLabel.toLowerCase()}'
                             : 'Jump to best ${positionByDayKey[key] == null ? 'exercise' : _positionLabel(positionByDayKey[key]!)} day'),
                      )),
            ],

            const SizedBox(height: 24),

            // ----------------- Exercise Form Videos -----------------
            const FitQuestSectionHeader(
              title: 'Exercise form videos',
              icon: Icons.play_circle_outline,
            ),
            const SizedBox(height: 6),
            Text(
              "Compare the imported trainer demonstration with your own form.",
              style: FitQuestTheme.dark.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (_isLoadingVideos)
              const Center(child: CircularProgressIndicator())
            else ...[
              _buildVideoPlayerCard(
                title: "Trainer Form Video",
                subtitle: _sourceExerciseId == null
                    ? null
                    : "Imported with this exercise",
                emptyMessage: "No imported trainer video is available.",
                controller: _importedVideoController,
                videoUrl: _importedVideoUrl,
                formNotes: _trainerFormNotes,
              ),

if ((_importedVideoUrl ?? '').trim().isNotEmpty &&
    (_sourceExerciseId ?? '').trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      icon: _isRemovingTrainerVideo
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.link_off),
      label: Text(
        _isRemovingTrainerVideo
            ? 'Removing Trainer Video...'
            : 'Remove Trainer Video',
      ),
      onPressed:
          (_isRemovingTrainerVideo ||
                  _isUploadingVideo ||
                  _isRemovingVideo)
              ? null
              : _removeTrainerVideo,
    ),
  ),
],
              const SizedBox(height: 12),
              _buildVideoPlayerCard(
                title: "My Form Video",
                subtitle: "Upload your own video without replacing the trainer video.",
                emptyMessage: "You have not uploaded a form video yet.",
                controller: _userVideoController,
                videoUrl: _pickedVideo != null
                    ? _pickedVideo!.path
                    : _userVideoUrl,
              ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.video_library),
                    label: Text(
                      _pickedVideo == null
                          ? "Choose My Video"
                          : "Change Selection",
                    ),
                    onPressed:
                        (_isUploadingVideo || _isRemovingVideo)
                            ? null
                            : _pickVideo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isUploadingVideo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      _isUploadingVideo ? "Uploading..." : "Upload Mine",
                    ),
                    onPressed:
                        (_pickedVideo == null ||
                            _isUploadingVideo ||
                            _isRemovingVideo)
                        ? null
                        : _uploadPickedVideo,
                  ),
                ),
              ],
            ),

            if (_pickedVideo != null) ...[
              const SizedBox(height: 8),
              Text(
                "Selected: ${_pickedVideo!.name}",
                style: FitQuestTheme.dark.textTheme.bodySmall,
              ),
            ],

            if ((_userVideoUrl ?? '').trim().isNotEmpty ||
                _pickedVideo != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _isRemovingVideo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(
                    _isRemovingVideo
                        ? "Removing..."
                        : _pickedVideo != null &&
                              (_userVideoUrl ?? '').trim().isEmpty
                        ? "Discard Selection"
                        : "Remove My Video",
                  ),
                  onPressed:
                      (_isUploadingVideo || _isRemovingVideo)
                      ? null
                      : _removeUserFormVideo,
                ),
              ),
            ],
            const SizedBox(height: 16),
              TextField(
                controller: userFormNotesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'My form tips / isolation notes',
                  hintText: 'Example: Keep elbows tucked and pause at peak contraction...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: _isSavingFormNotes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notes),
                  label: Text(
                    _isSavingFormNotes ? 'Saving...' : 'Save Form Tips',
                  ),
                  onPressed: _isSavingFormNotes ? null : _saveUserFormNotes,
                ),
              ),
          ],
          ],
        ),
      ),
    ),
    );
  }
}


class _ExerciseProgressPainter extends CustomPainter {
  final List<double> values;
  final List<int?> positions;
  final List<DateTime> dates;
  final int selectedIndex;
  final double bestValue;
  final Color accent;

  const _ExerciseProgressPainter({
    required this.values,
    required this.positions,
    required this.dates,
    required this.selectedIndex,
    required this.bestValue,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 18.0;
    const step = 74.0;
    const top = 20.0;
    const bottom = 151.0;
    final maximum = bestValue <= 0 ? 1.0 : bestValue * 1.12;
    double y(double v) => bottom - (v / maximum) * (bottom - top);
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.12)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final yy = top + (bottom - top) * i / 3;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }
    final line = Paint()..color = accent..strokeWidth = 2.5..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = left + i * step;
      if (i == 0) { path.moveTo(x, y(values[i])); }
      else { path.lineTo(x, y(values[i])); }
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < values.length; i++) {
      final x = left + i * step;
      final yy = y(values[i]);
      final isSelected = i == selectedIndex;
      final isBest = values[i] == bestValue;
      canvas.drawCircle(Offset(x, yy), isSelected ? 6.5 : 4.5,
          Paint()..color = isBest ? const Color(0xFFFFD166) : accent);
      if (isSelected) {
        canvas.drawCircle(Offset(x, yy), 9,
            Paint()..color = accent.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = 2);
      }
      final d = dates[i];
      _label(canvas, '${d.month}/${d.day}', Offset(x, 166), Colors.white70, 11);
      _label(canvas, positions[i] == null ? '—' : '#${positions[i]}',
          Offset(x, 190), Colors.white, 12);
    }
    _label(canvas, 'DATE', const Offset(18, 216), Colors.white54, 9, center: false);
    _label(canvas, 'ORDER', const Offset(70, 216), Colors.white54, 9, center: false);
  }

  void _label(Canvas canvas, String value, Offset at, Color color, double size,
      {bool center = true}) {
    final tp = TextPainter(
      text: TextSpan(text: value, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center ? at.dx - tp.width / 2 : at.dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _ExerciseProgressPainter old) =>
      old.selectedIndex != selectedIndex || old.values != values ||
      old.positions != positions || old.dates != dates;
}
