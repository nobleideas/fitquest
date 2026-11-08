import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/exercise_service.dart';
import '../services/session_service.dart';
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
  static const int _historyPageSize = 4;
  int? _currentRound;
  String? _bestMatchingDayKey;
  bool _isLoadingHistory = true;
  int _historyRequest = 0;
  Map<String, List<Map<String, dynamic>>> sessionsByDayKey = {};
  Map<String, double> volumeByDayKey = {};
  Map<String, bool> hasVolumeByDayKey = {};
  Map<String, int> roundByDayKey = {};
  bool _metricPreferenceLoaded = false;

  // -------- Form video state --------
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedVideo;

  VideoPlayerController? _importedVideoController;
  VideoPlayerController? _userVideoController;

  bool _isLoadingVideos = true;
  bool _isUploadingVideo = false;
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
  int? _storedRound(List<Map<String, dynamic>> sessions) {
    for (final session in sessions) {
      final raw = session['exercise_order'];
      final order = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (order != null && order > 0) return ((order - 1) ~/ 2) + 1;
    }
    return null;
  }

  // ---------- Sessions and round-aware history ----------
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

  Future<int> _resolveCurrentRound(String userId, String exerciseId,
      DateTime activeDate) async {
    // Match the order allocation used by insert_exercise_session_with_order.
    // An exercise already logged today retains its existing order.
    final startUtc = DateTime(activeDate.year, activeDate.month,
            activeDate.day)
        .toUtc().toIso8601String();
    final endUtc = DateTime(activeDate.year, activeDate.month,
            activeDate.day + 1)
        .toUtc().toIso8601String();
    await sessionService.backfillExerciseOrdersForDate(activeDate);
    final rows = <Map<String, dynamic>>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      final page = await Supabase.instance.client
          .from('exercise_sessions')
          .select('exercise_id, exercise_order')
          .eq('user_id', userId)
          .gte('created_at', startUtc)
          .lt('created_at', endUtc)
          .range(offset, offset + pageSize - 1);
      rows.addAll(page.map((r) => Map<String, dynamic>.from(r)));
      if (page.length < pageSize) break;
    }
    int? existingOrder;
    var maxOrder = 0;
    final distinctIds = <String>{};
    for (final row in rows) {
      final id = (row['exercise_id'] ?? '').toString();
      if (id.isNotEmpty) distinctIds.add(id);
      final raw = row['exercise_order'];
      final order = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (order != null && order > 0) {
        if (order > maxOrder) maxOrder = order;
        if (id == exerciseId) {
          existingOrder = existingOrder == null
              ? order
              : (order < existingOrder ? order : existingOrder);
        }
      }
    }
    final nextOrder = existingOrder ??
        (maxOrder > distinctIds.length ? maxOrder : distinctIds.length) + 1;
    return ((nextOrder - 1) ~/ 2) + 1;
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

      final currentRound = await _resolveCurrentRound(
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

      // Historical sessions may predate persistent exercise_order. Backfill
      // only days that need it, and re-read the affected exercise's sets.
      for (final key in map.keys.toList()) {
        final sessions = map[key]!;
        if (sessions.isEmpty || _storedRound(sessions) != null) continue;
        final day = _dateFromDayKey(key);
        await sessionService.backfillExerciseOrdersForDate(day);
        map[key] = await sessionService.getSessionsForDate(exerciseId, day);
      }

      final priorKeys = map.keys.where((key) => key.compareTo(activeKey) < 0)
          .toList()..sort((a, b) => b.compareTo(a));
      final volMap = <String, double>{};
      final hasVolMap = <String, bool>{};
      final roundMap = <String, int>{};
      for (final entry in map.entries) {
        var volume = 0.0;
        var hasVolume = false;
        for (final session in entry.value) {
          if ((session['metric_type'] ?? 'reps').toString() == 'reps' &&
              (session['load_type'] ?? 'weight').toString() == 'weight') {
            hasVolume = true;
            volume += _numToDouble(session['weight']) *
                _sessionMetricValue(session);
          }
        }
        volMap[entry.key] = volume;
        hasVolMap[entry.key] = hasVolume;
        final round = _storedRound(entry.value);
        if (round != null) roundMap[entry.key] = round;
      }

      String? bestKey;
      double? bestVolume;
      for (final key in priorKeys) {
        if (roundMap[key] != currentRound || hasVolMap[key] != true) continue;
        final volume = volMap[key]!;
        if (bestVolume == null || volume > bestVolume) {
          bestVolume = volume;
          bestKey = key;
        }
      }

      if (!mounted || request != _historyRequest || _todayKey() != activeKey) {
        return;
      }
      setState(() {
        todayDayKey = map[activeKey]!.isNotEmpty ? activeKey : null;
        previousDayKeys = priorKeys;
        sessionsByDayKey = map;
        volumeByDayKey = volMap;
        hasVolumeByDayKey = hasVolMap;
        roundByDayKey = roundMap;
        _currentRound = currentRound;
        _bestMatchingDayKey = bestKey;
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
    final round = roundByDayKey[dayKey];
    final isBestMatch = dayKey == _bestMatchingDayKey;
    final isMatchingRound = dayKey != _todayKey() &&
        _currentRound != null && round == _currentRound;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isBestMatch ? 5 : 3,
      color: isBestMatch ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBestMatch
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : isMatchingRound
                ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5))
                : BorderSide.none,
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title  •  ${sessions.length} ${sessions.length == 1 ? 'set' : 'sets'}'),
            if (isBestMatch)
              Text('BEST VOLUME · ROUND $_currentRound',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
            if (isMatchingRound && !isBestMatch)
              Text('MATCHING ROUND',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  )),
            if (showVolume)
              Text('Volume: ${volume.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (round != null)
              Text('Round $round',
                  style: Theme.of(context).textTheme.bodySmall),
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
                            style: Theme.of(context).textTheme.bodySmall,
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
      await controller.setLooping(true);
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
      await previewController.setLooping(true);

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

  Future<void> _uploadPickedVideo() async {
    final video = _pickedVideo;
    if (video == null) return;

    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
    if (exerciseId.isEmpty) return;

    setState(() => _isUploadingVideo = true);

    try {
      final publicUrl = await exerciseService.uploadUserFormVideo(
        exerciseId: exerciseId,
        video: video,
      );

      final controller = await _createNetworkController(publicUrl);
      await _disposeController(_userVideoController);

      if (!mounted) {
        await controller?.dispose();
        return;
      }

      setState(() {
        _userVideoUrl = publicUrl;
        _userVideoController = controller;
        _pickedVideo = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your form video was uploaded.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingVideo = false);
      }
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
      builder: (_) => AlertDialog(
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
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
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
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if ((formNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formNotes!.trim(),
                  style: Theme.of(context).textTheme.bodySmall,
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

    return Scaffold(
      appBar: AppBar(title: Text(exercise['name'] ?? 'Exercise')),
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
            Text(
              "Log Your Session",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.layers_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_currentRound == null
                          ? 'Determining current round...'
                          : 'Current round: $_currentRound  •  '
                            '${sessionsByDayKey[_todayKey()]?.length ?? 0} sets logged',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

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
            Text(
              isBacklogging ? "Selected Workout Day" : "Today's Workout",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              isBacklogging
                  ? "Sets for ${_formatDate(activeWorkoutDate)} appear here. Existing sets are preserved when you add more."
                  : "Today's recorded sets appear here.",
              style: Theme.of(context).textTheme.bodySmall,
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
                          style: Theme.of(context).textTheme.bodyMedium,
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

            // ----------------- Paged Previous Days -----------------
            Text('Previous Days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              isBacklogging
                  ? 'Earlier workout days before the selected backlog date. '
                    'Your highest-volume day in the same round is highlighted.'
                  : 'Browse all previous workout days, four at a time. '
                    'Your highest-volume day in the same round is highlighted.',
              style: Theme.of(context).textTheme.bodySmall,
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
                    style: Theme.of(context).textTheme.bodySmall,
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
              if (_bestMatchingDayKey != null &&
                  !previousDayKeys
                      .skip(_historyPage * _historyPageSize)
                      .take(_historyPageSize)
                      .contains(_bestMatchingDayKey))
                TextButton.icon(
                  onPressed: () => setState(() {
                    _historyPage = previousDayKeys.indexOf(_bestMatchingDayKey!) ~/
                        _historyPageSize;
                  }),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: Text('Jump to best Round $_currentRound day'),
                ),
            ],

            const SizedBox(height: 24),

            // ----------------- Exercise Form Videos -----------------
            Text(
              "Exercise Form Videos",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              "Compare the imported trainer demonstration with your own form.",
              style: Theme.of(context).textTheme.bodySmall,
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
              const SizedBox(height: 8),
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
                style: Theme.of(context).textTheme.bodySmall,
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
          ],
        ),
      ),
    );
  }
}
