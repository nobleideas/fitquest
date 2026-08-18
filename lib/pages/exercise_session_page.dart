import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/exercise_service.dart';
import '../services/session_service.dart';
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
  final ExerciseService exerciseService = ExerciseService();
  bool _isRemovingTrainerVideo = false;
  bool _isSavingFormNotes = false;
  String _selectedMetricType = 'reps';
  String _selectedLoadType = 'weight';

  // --- Today's workout + four most recent prior workout days
  String? todayDayKey;
  List<String> last4DayKeys = []; // "YYYY-MM-DD", excludes today
  Map<String, List<Map<String, dynamic>>> sessionsByDayKey = {};
  Map<String, double> volumeByDayKey = {};

  // -------- Progress --------
  double? _strengthTrendPercent;
  double? _volumeTrendPercent;
  String _strengthTrendLabel = 'Not enough data';
  String _volumeTrendLabel = 'Not enough data';
  String? _progressSummary;

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
    _loadTodayAndLast4Days();
    _loadExerciseVideos();
  }

  // ---------- Day key helpers ----------
  String _dayKey(DateTime dt) {
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _todayKey() => _dayKey(DateTime.now());

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

  // ---------- Sessions ----------
  Future<void> _loadTodayAndLast4Days() async {
    final user = Supabase.instance.client.auth.currentUser;
    final exerciseId = (widget.exercise['id'] ?? '').toString().trim();

    if (user == null || exerciseId.isEmpty) return;

    final recentRows = await Supabase.instance.client
        .from('exercise_sessions')
        .select('created_at')
        .eq('user_id', user.id)
        .eq('exercise_id', exerciseId)
        .order('created_at', ascending: false)
        .limit(500);

    final todayKey = _todayKey();
    final seen = <String>{};
    final priorKeys = <String>[];
    var hasToday = false;

    for (final row in recentRows) {
      if (row is! Map) continue;

      final parsed = DateTime.tryParse(
        (row['created_at'] ?? '').toString(),
      );
      if (parsed == null) continue;

      final key = _dayKey(parsed);

      if (key == todayKey) {
        hasToday = true;
        continue;
      }

      if (seen.add(key)) {
        priorKeys.add(key);
      }

      if (priorKeys.length == 4) break;
    }

    final keysToLoad = <String>[
      if (hasToday) todayKey,
      ...priorKeys,
    ];

    final map = <String, List<Map<String, dynamic>>>{};
    final volMap = <String, double>{};

    for (final key in keysToLoad) {
      final date = _dateFromDayKey(key);
      final sessions = await sessionService.getSessionsForDate(
        exerciseId,
        date,
      );

      map[key] = sessions;

      double totalVolume = 0;
      for (final session in sessions) {
        final metricType = (session['metric_type'] ?? 'reps').toString();
        final loadType = (session['load_type'] ?? 'weight').toString();
        if (metricType == 'reps' && loadType == 'weight') {
          totalVolume +=
              _numToDouble(session['weight']) *
              _sessionMetricValue(session);
        }
      }

      volMap[key] = totalVolume;
    }

    if (!mounted) return;

    setState(() {
      todayDayKey = hasToday ? todayKey : null;
      last4DayKeys = priorKeys;
      sessionsByDayKey = map;
      volumeByDayKey = volMap;
    });

    await _loadProgress();
  }

  Future<void> _deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    await _loadTodayAndLast4Days();
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

    await _loadTodayAndLast4Days();
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

  // ---------- Rolling progress ----------
  Future<void> _loadProgress() async {
    try {
      final exerciseId = (widget.exercise['id'] ?? '').toString().trim();
      if (exerciseId.isEmpty) return;

      final performance = await exerciseService.getExercisePerformanceData(
        exerciseId: exerciseId,
      );

      if (!mounted) return;
      setState(() {
        _strengthTrendPercent = performance.strengthTrendPercent;
        _volumeTrendPercent = performance.volumeTrendPercent;
        _strengthTrendLabel = performance.strengthTrendLabel;
        _volumeTrendLabel = performance.volumeTrendLabel;
        _progressSummary = performance.progressSummary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progressSummary = 'Could not calculate progress: $e';
      });
    }
  }

  String _formatTrendPercent(double? value) {
    if (value == null) return '—';
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(1)}%';
  }

  IconData _trendIcon(double? value) {
    if (value == null) return Icons.horizontal_rule;
    if (value > 1) return Icons.trending_up;
    if (value < -1) return Icons.trending_down;
    return Icons.trending_flat;
  }

  Widget _buildProgressTile({
    required String title,
    required double? value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_trendIcon(value)),
            const SizedBox(height: 6),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              _formatTrendPercent(value),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutDayCard({
    required String dayKey,
    required String title,
    bool initiallyExpanded = false,
  }) {
    final sessions = sessionsByDayKey[dayKey] ?? const [];
    final volume = volumeByDayKey[dayKey] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          '$title  •  Volume: ${volume.toStringAsFixed(0)}',
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

    return Scaffold(
      appBar: AppBar(title: Text(exercise['name'] ?? 'Exercise')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------- Log Form -----------------
            Text(
              "Log Your Session",
              style: Theme.of(context).textTheme.headlineSmall,
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
                        setState(() => _selectedLoadType = type);
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
                        setState(() => _selectedMetricType = type);
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
                label: const Text("Save Set"),
                onPressed: () async {
                  final weight = double.tryParse(weightController.text.trim());
                  final metricValue = double.tryParse(repsController.text.trim());
                  if (weight == null || metricValue == null) return;

                  if (_selectedMetricType == 'reps' &&
                      metricValue != metricValue.roundToDouble()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reps must be a whole number.')),
                    );
                    return;
                  }

                  final res = await sessionService.insertSession(
                    exerciseId: exercise['id'].toString(),
                    weight: weight,
                    metricType: _selectedMetricType,
                    metricValue: metricValue,
                    loadType: _selectedLoadType,
                  );

                  final sessionID = res['id'];

                  await Supabase.instance.client.rpc(
                    'add_session_xp',
                    params: {'session_id': sessionID},
                  );

                  weightController.clear();
                  repsController.clear();
                  await _loadTodayAndLast4Days();
                },
              ),
            ),

            const SizedBox(height: 16),

            if (_progressSummary != null)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insights),
                          const SizedBox(width: 8),
                          Text(
                            'Progress',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildProgressTile(
                            title: 'Strength trend',
                            value: _strengthTrendPercent,
                            label: _strengthTrendLabel,
                          ),
                          const SizedBox(width: 10),
                          _buildProgressTile(
                            title: 'Volume trend',
                            value: _volumeTrendPercent,
                            label: _volumeTrendLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _progressSummary!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // ----------------- Today's Workout -----------------
            Text(
              "Today's Workout",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "Today's sets are shown here but are excluded from the current "
              "progress calculations until the calendar day changes.",
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
                          "No sets have been recorded for this exercise today.",
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
                title: "Today",
                initiallyExpanded: true,
              ),

            const SizedBox(height: 20),

            // ----------------- Last 4 Recorded Days -----------------
            Text(
              "Last 4 Recorded Days",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "These are completed prior workout days. Tomorrow, today's "
              "workout will automatically move into this section and the "
              "progress calculation will refresh using it.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (last4DayKeys.isEmpty)
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "No prior workout days have been recorded for this exercise.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...last4DayKeys.map((key) {
                final date = _dateFromDayKey(key);

                return _buildWorkoutDayCard(
                  dayKey: key,
                  title: _formatDate(date),
                );
              }),

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
