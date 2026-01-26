import 'dart:io';

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

  // ✅ NEW: total volume per day key
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

  String? _formVideoUrl; // persisted URL from exercises.video_url

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
      // If profile load fails, suggestions still work without a goal.
    }
  }

  // ---------- Sessions ----------
  Future<void> _loadLast3DaysAndSessions() async {
    final rawDates =
        await sessionService.getLast3SessionDates(widget.exercise['id']);

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

      // ✅ compute volume (sum weight * reps)
      double totalVol = 0.0;
      for (final s in sessions) {
        final w = _numToDouble(s['weight']);
        final r = _numToInt(s['reps']);
        totalVol += (w * r);
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

  // ---------- Suggestion logic (UPDATED) ----------
  //
  // Goals:
  // - If NO sessions exist: suggest reps & sets by goal, no weight.
  // - If sessions exist: use MOST RECENT day's total volume.
  //   - Pick target reps/sets by goal
  //   - Compute weight = volume / (reps * sets)
  //   - Apply small goal adjustment for progression
  //
  void _computeSuggestion() {
    final goal = (_userGoal ?? '').toLowerCase().trim();

    // Goal-based defaults
    int goalReps;
    int goalSets;
    double progressionMultiplier; // small change to push progression

    switch (goal) {
      case 'gain_strength':
        goalReps = 5;
        goalSets = 5;
        progressionMultiplier = 1.02; // +2%
        break;
      case 'gain_mass':
        goalReps = 10;
        goalSets = 4;
        progressionMultiplier = 1.01; // +1%
        break;
      case 'lose_weight':
        goalReps = 12;
        goalSets = 4;
        progressionMultiplier = 0.97; // slightly easier (volume-based calc already handles)
        break;
      default:
        // fallback (hypertrophy-ish)
        goalReps = 8;
        goalSets = 4;
        progressionMultiplier = 1.01;
        break;
    }

    // If no history at all
    if (last3DayKeys.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = goalReps;
        _suggestedSets = goalSets;
        _suggestionNote =
            "No previous sessions for this exercise yet — reps/sets suggested from your goal.";
      });
      return;
    }

    // Most recent day key + sessions
    final mostRecentKey = last3DayKeys.first;
    final recentSessions = sessionsByDayKey[mostRecentKey] ?? const [];
    final recentVolume = volumeByDayKey[mostRecentKey] ?? 0.0;

    // If no sessions found for the most recent day (rare edge case)
    if (recentSessions.isEmpty) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = goalReps;
        _suggestedSets = goalSets;
        _suggestionNote =
            "No sessions found in your recent history — reps/sets suggested from your goal.";
      });
      return;
    }

    // If volume is 0 (maybe reps-based cardio / bodyweight entered as 0 weight)
    // Still suggest reps/sets; weight would be useless.
    if (recentVolume <= 0.0) {
      if (!mounted) return;
      setState(() {
        _suggestedWeight = null;
        _suggestedReps = goalReps;
        _suggestedSets = goalSets;
        _suggestionNote =
            "Your most recent session volume was 0 — suggesting reps/sets based on your goal.";
      });
      return;
    }

    // Compute weight from volume distribution
    final reps = goalReps.clamp(1, 30);
    final sets = goalSets.clamp(1, 12);

    final denom = (reps * sets).toDouble();
    double baseWeight = recentVolume / denom;

    // Apply small progression based on goal
    baseWeight *= progressionMultiplier;

    // Round weight to nearest 2.5 like your original logic
    const roundTo = 2.5;
    double roundedWeight = (baseWeight / roundTo).round() * roundTo;
    if (roundedWeight <= 0) roundedWeight = baseWeight;

    final volText = recentVolume.toStringAsFixed(0);

    String note;
    if (goal == 'gain_strength') {
      note =
          "Based on your most recent day volume ($volText), distributed as $sets sets × $reps reps (strength).";
    } else if (goal == 'gain_mass') {
      note =
          "Based on your most recent day volume ($volText), distributed as $sets sets × $reps reps (mass).";
    } else if (goal == 'lose_weight') {
      note =
          "Based on your most recent day volume ($volText), distributed as $sets sets × $reps reps (fat loss).";
    } else {
      note =
          "Based on your most recent day volume ($volText), distributed as $sets sets × $reps reps.";
    }

    if (!mounted) return;
    setState(() {
      _suggestedWeight = roundedWeight;
      _suggestedReps = reps;
      _suggestedSets = sets;
      _suggestionNote = note;
    });
  }

  void _applySuggestionToInputs() {
    if (_suggestedWeight != null) {
      final w = _suggestedWeight!;
      final decimals = (w % 1 == 0) ? 0 : 1;
      weightController.text = w.toStringAsFixed(decimals);
    }
    if (_suggestedReps != null) {
      repsController.text = _suggestedReps.toString();
    }
  }

  // ---------- Video helpers ----------
  Future<void> _loadExistingFormVideo() async {
    // If the caller already included it, use it immediately
    final existing = widget.exercise['video_url'] as String?;
    if (existing != null && existing.isNotEmpty) {
      _formVideoUrl = existing;
      await _initVideoPlayerFromUrl(existing);
      return;
    }

    // Otherwise fetch from DB (keeps fresh if caller didn't include it)
    final client = Supabase.instance.client;
    final data = await client
        .from('exercises')
        .select('video_url')
        .eq('id', widget.exercise['id'])
        .maybeSingle();

    final url = data?['video_url'] as String?;
    if (url != null && url.isNotEmpty) {
      _formVideoUrl = url;
      await _initVideoPlayerFromUrl(url);
    } else {
      if (!mounted) return;
      setState(() => _formVideoUrl = null);
    }
  }

  Future<void> _initVideoPlayerFromUrl(String url) async {
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoController!.initialize();
    await _videoController!.setVolume(1.0);
    await _videoController!.setPlaybackSpeed(1.0);
    _videoController!.setLooping(true);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;

      if (!mounted) return;
      setState(() => _pickedVideo = video);

      await _videoController?.dispose();

      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(video.path));
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

      // bucket id must match exactly
      final bucket = client.storage.from('exercise_form_video');

      final ext =
          p.extension(video.name).isNotEmpty ? p.extension(video.name) : '.mp4';
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
          .update({'video_url': publicUrl})
          .eq('id', widget.exercise['id']);

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

  // ✅ NEW: remove existing form video (DB + best-effort storage delete)
  String? _tryExtractStoragePathFromPublicUrl(String url, String bucketId) {
    // Typical public URL:
    // .../storage/v1/object/public/<bucketId>/<path>
    // We want <path>
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
    if (url.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove form video?'),
        content: const Text(
          'This will remove the saved form video from this exercise.',
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

    setState(() => _isRemovingVideo = true);

    try {
      final client = Supabase.instance.client;

      // 1) Clear DB
      await client
          .from('exercises')
          .update({'video_url': null})
          .eq('id', widget.exercise['id']);

      // 2) Best-effort delete storage object if we can parse the path
      const bucketId = 'exercise_form_video';
      final bucket = client.storage.from(bucketId);
      final storagePath = _tryExtractStoragePathFromPublicUrl(url, bucketId);

      if (storagePath != null) {
        try {
          await bucket.remove([storagePath]);
        } catch (_) {
          // ignore; DB cleared is the main goal
        }
      }

      await _videoController?.dispose();
      _videoController = null;

      if (!mounted) return;
      setState(() {
        _formVideoUrl = null;
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
      appBar: AppBar(title: Text(exercise['name'])),
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
                          Text(
                            "Suggested Next Session",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _applySuggestionToInputs,
                            child: const Text("Use suggestion"),
                          ),
                        ],
                      ),
                      if (_suggestionNote != null) ...[
                        const SizedBox(height: 4),
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
                        "Tip: Log $_suggestedSets sets using the reps above${_suggestedWeight == null ? '' : ' (and weight).'}",
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
                  // ✅ show volume next to date
                  title: Text("${_formatDate(date)}  •  Volume: $volLabel"),
                  children: sessions.isEmpty
                      ? const [
                          ListTile(
                            leading: Icon(Icons.info_outline),
                            title: Text("No sessions found for this day."),
                          ),
                        ]
                      : sessions.map((s) {
                          return Dismissible(
                            key: Key(s['id'].toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              color: Colors.red,
                              padding: const EdgeInsets.only(right: 20),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) =>
                                _deleteSession(s['id'].toString()),
                            child: ListTile(
                              leading: const Icon(Icons.fitness_center),
                              title: Text("Weight: ${s['weight']}"),
                              subtitle: Text("Reps: ${s['reps']}"),
                              trailing: Text(
                                "Vol: ${(_numToDouble(s['weight']) * _numToInt(s['reps'])).toStringAsFixed(0)}",
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
                    label: Text(
                      _pickedVideo == null ? "Choose Video" : "Change Video",
                    ),
                    onPressed: (_isUploadingVideo || _isRemovingVideo)
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
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isUploadingVideo ? "Uploading..." : "Upload"),
                    onPressed: (_pickedVideo == null ||
                            _isUploadingVideo ||
                            _isRemovingVideo)
                        ? null
                        : _uploadPickedVideo,
                  ),
                ),
              ],
            ),

            // ✅ NEW: remove video button
            if ((_formVideoUrl ?? '').trim().isNotEmpty) ...[
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
                  onPressed: (_isUploadingVideo || _isRemovingVideo)
                      ? null
                      : _removeFormVideo,
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

            if (_videoController != null &&
                _videoController!.value.isInitialized)
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
                      if (_formVideoUrl != null && _formVideoUrl!.isNotEmpty)
                        const Text("Saved ✓"),
                    ],
                  ),
                ],
              )
            else
              Text(
                _formVideoUrl == null
                    ? "No form video uploaded yet."
                    : "Loading form video...",
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
