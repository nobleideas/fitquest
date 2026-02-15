import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as p;

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
  final SessionService sessionService = SessionService();

  // --- Last 3 recorded days (stable day-key approach avoids timezone/dup bugs)
  List<String> last3DayKeys = []; // "YYYY-MM-DD"
  Map<String, List<Map<String, dynamic>>> sessionsByDayKey = {};
  Map<String, double> volumeByDayKey = {};

  // -------- Profile Goal / Suggestions --------
  String? _userGoal; // gain_strength, gain_mass, lose_weight
  double? _suggestedWeight;
  int? _suggestedReps;
  int? _suggestedSets;
  String? _suggestionNote;

  // -------- Form video state --------
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedVideo;
  VideoPlayerController? _videoController;

  bool _isUploadingVideo = false;
  bool _isRemovingVideo = false;

  String? _formVideoUrl; // resolved URL we’re currently showing (local or imported)
  String? _myVideoUrl; // my exercise.video_url (if any)
  String? _sourceExerciseId; // my exercise.video_source_exercise_id (if any)

  @override
  void initState() {
    super.initState();
    _loadUserGoal();
    _loadLast3DaysAndSessions();
    _loadExistingFormVideo();
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

  double _roundTo(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  // ---------- Load user goal ----------
  Future<void> _loadUserGoal() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final data = await client
          .from('profiles')
          .select('goal')
          .eq('id', user.id)
          .maybeSingle();

      final goal = data?['goal']?.toString().trim();
      if (!mounted) return;

      setState(() {
        _userGoal = (goal != null && goal.isNotEmpty) ? goal : null;
      });

      _computeSuggestion();
    } catch (_) {
      // suggestions still work without a goal
    }
  }

  // ---------- Sessions ----------
  Future<void> _loadLast3DaysAndSessions() async {
    final rawDates = await sessionService.getLast3SessionDates(
      widget.exercise['id'],
    );

    // Deduplicate by day; keep newest-first order as returned by service.
    final seen = <String>{};
    final keys = <String>[];
    for (final d in rawDates) {
      final key = _dayKey(d);
      if (seen.add(key)) keys.add(key);
      if (keys.length == 3) break;
    }

    final Map<String, List<Map<String, dynamic>>> map = {};
    final Map<String, double> volMap = {};

    for (final key in keys) {
      final date = _dateFromDayKey(key);
      final sessions = await sessionService.getSessionsForDate(
        widget.exercise['id'],
        date,
      );
      map[key] = sessions;

      double totalVol = 0.0;
      for (final s in sessions) {
        totalVol += _numToDouble(s['weight']) * _numToInt(s['reps']);
      }
      volMap[key] = totalVol;
    }

    if (!mounted) return;
    setState(() {
      last3DayKeys = keys;
      sessionsByDayKey = map;
      volumeByDayKey = volMap;
    });

    _computeSuggestion();
  }

  Future<void> _deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    await _loadLast3DaysAndSessions();
  }

  // ---------- NEW Suggestion logic (working-set anchored + goal-driven) ----------
  void _computeSuggestion() {
    final goal = (_userGoal ?? '').toLowerCase().trim();

    int targetReps;
    int targetSets;

    switch (goal) {
      case 'gain_strength':
        targetReps = 5;
        targetSets = 5;
        break;
      case 'gain_mass':
        targetReps = 10;
        targetSets = 4;
        break;
      case 'lose_weight':
        targetReps = 12;
        targetSets = 4;
        break;
      default:
        targetReps = 8;
        targetSets = 4;
        break;
    }

    // Use the most recent day that is NOT today
    final todayKey = _todayKey();
    final referenceKey = last3DayKeys.firstWhere(
      (k) => k != todayKey,
      orElse: () => '',
    );

    if (referenceKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = targetReps;
        _suggestedSets = targetSets;
        _suggestionNote =
            "No prior training day found yet for this exercise (excluding today). Showing reps/sets from your goal.";
      });
      return;
    }

    final sessions = sessionsByDayKey[referenceKey] ?? const [];
    if (sessions.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = targetReps;
        _suggestedSets = targetSets;
        _suggestionNote =
            "No usable session history on ${_formatDate(_dateFromDayKey(referenceKey))}. Showing reps/sets from your goal.";
      });
      return;
    }

    // Parse sets
    final sets = sessions
        .map((s) => (
              weight: _numToDouble(s['weight']),
              reps: _numToInt(s['reps']),
            ))
        .where((x) => x.weight > 0 && x.reps > 0)
        .toList();

    if (sets.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = targetReps;
        _suggestedSets = targetSets;
        _suggestionNote =
            "Not enough valid sets to estimate a working weight. Showing reps/sets from your goal.";
      });
      return;
    }

    final maxW = sets.map((x) => x.weight).reduce((a, b) => a > b ? a : b);

    // Filter “working sets” and ignore likely warmups:
    // keep anything at or above 85% of max weight for that day.
    final working = sets.where((x) => x.weight >= (0.85 * maxW)).toList();

    // Fallback: if filter too strict, use the top 3 heaviest sets.
    if (working.isEmpty) {
      final sorted = [...sets]..sort((a, b) => b.weight.compareTo(a.weight));
      working.addAll(sorted.take(sorted.length >= 3 ? 3 : sorted.length));
    }

    final workingWeights = working.map((x) => x.weight).toList();
    final workingMedianWeight = _median(workingWeights);

    // Determine if you “hit” the target last time:
    // Count sets near your working weight where reps >= targetReps.
    final nearWorking = working.where((x) => x.weight >= (0.95 * workingMedianWeight)).toList();
    final goodSets = nearWorking.where((x) => x.reps >= targetReps).length;

    // Progression step
    // Default 2.5; bump to 5 if you clearly exceeded reps.
    double step = 2.5;
    final crushedSets = nearWorking.where((x) => x.reps >= (targetReps + 2)).length;
    if (crushedSets >= (targetSets >= 3 ? 3 : targetSets)) {
      step = 5.0;
    }

    // Suggest weight:
    // If you hit at least targetSets good sets last time, add step; else keep.
    double suggested = workingMedianWeight;
    final progressed = goodSets >= targetSets;
    if (progressed) {
      suggested = workingMedianWeight + step;
    }

    // Round to nearest 2.5 (your plates reality)
    suggested = _roundTo(suggested, 2.5);

    final refDate = _formatDate(_dateFromDayKey(referenceKey));
    final goalText = goal.isEmpty ? "default" : goal.replaceAll('_', ' ');
    final note =
        "Based on your working sets on $refDate (ignoring warmups). "
        "Estimated working weight: ${workingMedianWeight.toStringAsFixed(workingMedianWeight % 1 == 0 ? 0 : 1)}. "
        "You hit $goodSets set(s) at ${targetReps} reps or more near that weight, so next session is ${progressed ? "a small increase" : "the same weight"} "
        "for $targetSets×$targetReps ($goalText).";

    if (!mounted) return;
    setState(() {
      _suggestedWeight = suggested > 0 ? suggested : null;
      _suggestedReps = targetReps;
      _suggestedSets = targetSets;
      _suggestionNote = note;
    });
  }

  // ---------- VIDEO: helpers ----------
  Future<String?> _rpcResolveExerciseVideoUrl(String sourceExerciseId) async {
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc(
        'get_exercise_video_url',
        params: {'p_exercise_id': sourceExerciseId},
      );

      if (res == null) return null;

      if (res is String) {
        final s = res.trim();
        return s.isEmpty ? null : s;
      }

      if (res is List && res.isNotEmpty) {
        final first = res.first;
        if (first is Map && first.isNotEmpty) {
          final v = (first.values.first ?? '').toString().trim();
          return v.isEmpty ? null : v;
        }
        final v = first.toString().trim();
        return v.isEmpty ? null : v;
      }

      if (res is Map) {
        final v = (res.values.isNotEmpty ? res.values.first : '').toString().trim();
        return v.isEmpty ? null : v;
      }

      final v = res.toString().trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearVideoControllerState() async {
    await _videoController?.dispose();
    _videoController = null;
  }

  Future<void> _loadExistingFormVideo() async {
    final client = Supabase.instance.client;

    final passedMyUrl = (widget.exercise['video_url'] as String?)?.trim();
    final passedSource =
        (widget.exercise['video_source_exercise_id'] ?? '').toString().trim();

    String? myUrl = (passedMyUrl != null && passedMyUrl.isNotEmpty) ? passedMyUrl : null;
    String? sourceId = passedSource.isNotEmpty ? passedSource : null;

    if (myUrl == null && sourceId == null) {
      final data = await client
          .from('exercises')
          .select('video_url, video_source_exercise_id')
          .eq('id', widget.exercise['id'])
          .maybeSingle();

      myUrl = (data?['video_url'] as String?)?.trim();
      if (myUrl != null && myUrl.isEmpty) myUrl = null;

      final sid = (data?['video_source_exercise_id'] ?? '').toString().trim();
      sourceId = sid.isNotEmpty ? sid : null;
    }

    _myVideoUrl = myUrl;
    _sourceExerciseId = sourceId;

    if (myUrl != null && myUrl.isNotEmpty) {
      _formVideoUrl = myUrl;
      await _initVideoPlayerFromUrl(myUrl);
      return;
    }

    if (sourceId != null && sourceId.isNotEmpty) {
      final srcUrl = await _rpcResolveExerciseVideoUrl(sourceId);

      if (srcUrl != null && srcUrl.isNotEmpty) {
        _formVideoUrl = srcUrl;
        await _initVideoPlayerFromUrl(srcUrl);
        return;
      }

      await _clearVideoControllerState();
      if (!mounted) return;
      setState(() {
        _formVideoUrl = null;
      });
      return;
    }

    await _clearVideoControllerState();
    if (!mounted) return;
    setState(() => _formVideoUrl = null);
  }

  Future<void> _initVideoPlayerFromUrl(String url) async {
    await _clearVideoControllerState();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoController!.initialize();
    await _videoController!.setVolume(1.0);
    await _videoController!.setPlaybackSpeed(1.0);
    await _videoController!.setLooping(true);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;

      if (!mounted) return;
      setState(() => _pickedVideo = video);

      await _clearVideoControllerState();

      if (kIsWeb) {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(video.path));
      } else {
        _videoController = VideoPlayerController.file(File(video.path));
      }

      await _videoController!.initialize();
      await _videoController!.setVolume(1.0);
      await _videoController!.setPlaybackSpeed(1.0);
      await _videoController!.setLooping(true);

      if (!mounted) return;
      setState(() {});
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

    setState(() => _isUploadingVideo = true);

    try {
      final client = Supabase.instance.client;

      const bucketId = 'exercise_form_video';
      final bucket = client.storage.from(bucketId);

      final ext = p.extension(video.name).isNotEmpty ? p.extension(video.name) : '.mp4';
      final storagePath = 'exercise_${widget.exercise['id']}/form$ext';

      final bytes = await video.readAsBytes();

      await bucket.uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: video.mimeType ?? 'video/mp4',
        ),
      );

      final publicUrl = bucket.getPublicUrl(storagePath);

      await client
          .from('exercises')
          .update({
            'video_url': publicUrl,
            'video_source_exercise_id': null,
          })
          .eq('id', widget.exercise['id']);

      _myVideoUrl = publicUrl;
      _sourceExerciseId = null;
      _formVideoUrl = publicUrl;

      await _initVideoPlayerFromUrl(publicUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video uploaded and saved to exercise.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingVideo = false);
    }
  }

  String? _tryExtractStoragePathFromPublicUrl(String url, String bucketId) {
    try {
      final marker = '/storage/v1/object/public/$bucketId/';
      final i = url.indexOf(marker);
      if (i == -1) return null;
      final path = url.substring(i + marker.length);
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeFormVideo() async {
    final url = (_formVideoUrl ?? '').trim();
    final hasSomethingToRemove = url.isNotEmpty || (_sourceExerciseId ?? '').isNotEmpty;

    if (!hasSomethingToRemove) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove form video?'),
        content: const Text('This will remove the saved form video from this exercise.'),
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

    setState(() => _isRemovingVideo = true);

    try {
      final client = Supabase.instance.client;
      final myUrl = (_myVideoUrl ?? '').trim();

      await client
          .from('exercises')
          .update({'video_url': null, 'video_source_exercise_id': null})
          .eq('id', widget.exercise['id']);

      const bucketId = 'exercise_form_video';
      if (myUrl.isNotEmpty) {
        final bucket = client.storage.from(bucketId);
        final storagePath = _tryExtractStoragePathFromPublicUrl(myUrl, bucketId);
        if (storagePath != null) {
          try {
            await bucket.remove([storagePath]);
          } catch (_) {}
        }
      }

      await _clearVideoControllerState();

      if (!mounted) return;
      setState(() {
        _formVideoUrl = null;
        _myVideoUrl = null;
        _sourceExerciseId = null;
        _pickedVideo = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Form video removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove video: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRemovingVideo = false);
    }
  }

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    _videoController?.dispose();
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
              decoration: const InputDecoration(
                labelText: "Weight / Bodyweight",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Reps / Seconds / Minutes / Miles",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("Save Set"),
                onPressed: () async {
                  final weight = double.tryParse(weightController.text);
                  final reps = int.tryParse(repsController.text);
                  if (weight == null || reps == null) return;

                  final res = await sessionService.insertSession(
                    exerciseId: exercise['id'],
                    weight: weight,
                    reps: reps,
                  );

                  final sessionID = res['id'];

                  await Supabase.instance.client.rpc(
                    'add_session_xp',
                    params: {'session_id': sessionID},
                  );

                  weightController.clear();
                  repsController.clear();
                  await _loadLast3DaysAndSessions();
                },
              ),
            ),

            const SizedBox(height: 16),

            // ----------------- Suggested Next Session -----------------
            if (_suggestedReps != null && _suggestedSets != null)
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
                          const Icon(Icons.auto_awesome),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Suggested Next Session",
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_suggestionNote != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _suggestionNote!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_suggestedWeight != null)
                            Chip(
                              label: Text(
                                "Weight: ${_suggestedWeight!.toStringAsFixed(_suggestedWeight! % 1 == 0 ? 0 : 1)}",
                              ),
                            )
                          else
                            const Chip(label: Text("Weight: —")),
                          Chip(label: Text("Reps: $_suggestedReps")),
                          Chip(label: Text("Sets: $_suggestedSets")),
                          if (_userGoal != null && _userGoal!.isNotEmpty)
                            Chip(label: Text("Goal: $_userGoal")),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Tip: Aim for $_suggestedSets × $_suggestedReps${_suggestedWeight == null ? '' : ' at the suggested weight.'}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // ----------------- Last 3 Recorded Days -----------------
            if (last3DayKeys.isNotEmpty)
              Text(
                "Last 3 Recorded Days",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 12),

            ...last3DayKeys.map((key) {
              final date = _dateFromDayKey(key);
              final sessions = sessionsByDayKey[key] ?? const [];
              final vol = volumeByDayKey[key] ?? 0.0;
              final volLabel = vol.toStringAsFixed(0);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  title: Text("${_formatDate(date)}  •  Volume: $volLabel"),
                  children: sessions.isEmpty
                      ? const [
                          ListTile(
                            leading: Icon(Icons.info_outline),
                            title: Text("No sessions found for this day."),
                          ),
                        ]
                      : sessions.map((s) {
                          final setVol =
                              _numToDouble(s['weight']) * _numToInt(s['reps']);
                          return Dismissible(
                            key: Key(s['id'].toString()),
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
                                _deleteSession(s['id'].toString()),
                            child: ListTile(
                              leading: const Icon(Icons.fitness_center),
                              title: Text("Weight: ${s['weight']}"),
                              subtitle: Text("Reps: ${s['reps']}"),
                              trailing: Text(
                                "Vol: ${setVol.toStringAsFixed(0)}",
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          );
                        }).toList(),
                ),
              );
            }).toList(),

            const SizedBox(height: 24),

            // ----------------- Exercise Form Video -----------------
            Text(
              "Exercise Form Video",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.video_library),
                    label: Text(_pickedVideo == null ? "Choose Video" : "Change Video"),
                    onPressed: (_isUploadingVideo || _isRemovingVideo) ? null : _pickVideo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isUploadingVideo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isUploadingVideo ? "Uploading..." : "Upload"),
                    onPressed: (_pickedVideo == null || _isUploadingVideo || _isRemovingVideo)
                        ? null
                        : _uploadPickedVideo,
                  ),
                ),
              ],
            ),

            if (((_formVideoUrl ?? '').trim().isNotEmpty) ||
                ((_sourceExerciseId ?? '').trim().isNotEmpty)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _isRemovingVideo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(_isRemovingVideo ? "Removing..." : "Remove video"),
                  onPressed: (_isUploadingVideo || _isRemovingVideo) ? null : _removeFormVideo,
                ),
              ),
            ],

            if (_pickedVideo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Selected: ${_pickedVideo!.name}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

            const SizedBox(height: 12),

            if (_videoController != null && _videoController!.value.isInitialized)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _videoController!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: () async {
                          if (_videoController == null) return;

                          if (_videoController!.value.isPlaying) {
                            await _videoController!.pause();
                          } else {
                            await _videoController!.setVolume(1.0);
                            await _videoController!.play();
                          }

                          if (mounted) setState(() {});
                        },
                      ),
                      const Spacer(),
                      if ((_formVideoUrl ?? '').trim().isNotEmpty)
                        const Text("Saved ✓"),
                    ],
                  ),
                ],
              )
            else
              Text(
                (_formVideoUrl ?? '').trim().isEmpty
                    ? "No form video uploaded."
                    : "Loading form video...",
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
