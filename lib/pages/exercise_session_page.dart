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

  List<DateTime> last3Dates = [];
  Map<DateTime, List<Map<String, dynamic>>> sessionsByDate = {};

  // -------- Form video state --------
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedVideo;
  VideoPlayerController? _videoController;

  bool _isUploadingVideo = false;
  String? _formVideoUrl; // persisted URL from exercises.form_video_url

  @override
  void initState() {
    super.initState();
    _loadLast3DatesAndSessions();
    _loadExistingFormVideo();
  }

  Future<void> _loadLast3DatesAndSessions() async {
    final dates = await sessionService.getLast3SessionDates(widget.exercise['id']);
    final Map<DateTime, List<Map<String, dynamic>>> map = {};

    for (final date in dates) {
      map[date] = await sessionService.getSessionsForDate(widget.exercise['id'], date);
    }

    if (!mounted) return;
    setState(() {
      last3Dates = dates;
      sessionsByDate = map;
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    await _loadLast3DatesAndSessions();
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

    // Otherwise fetch from DB (recommended so it always stays fresh)
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
    }
  }

  Future<void> _initVideoPlayerFromUrl(String url) async {
    await _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoController!.initialize();
    
    await _videoController!.setVolume(1.0);
    await _videoController!.setPlaybackSpeed(1.0); // optional, but harmless
    _videoController!.setLooping(true);

    _videoController!.setLooping(true);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickVideo() async {
  try {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    // Set state immediately so UI updates
    if (!mounted) return;
    setState(() {
      _pickedVideo = video;
    });

    await _videoController?.dispose();

    // Always use network controller — works for blob URLs (web) and public URLs
    _videoController = VideoPlayerController.networkUrl(Uri.parse(video.path));
    await _videoController!.initialize();
    await _videoController!.setVolume(1.0);
    await _videoController!.setPlaybackSpeed(1.0); // optional, but harmless
    _videoController!.setLooping(true);

    _videoController!.setLooping(true);

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
    final bucket = client.storage.from('exercise_form_video');

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
            Text("Log Your Session", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),

            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Weight",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Reps",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("Save Session"),
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
                  await _loadLast3DatesAndSessions();
                },
              ),
            ),

            const SizedBox(height: 24),

            // ----------------- Exercise Form Video -----------------
            Text("Exercise Form Video", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.video_library),
                    label: Text(_pickedVideo == null ? "Choose Video" : "Change Video"),
                    onPressed: _isUploadingVideo ? null : _pickVideo,
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
                    onPressed: (_pickedVideo == null || _isUploadingVideo)
                        ? null
                        : _uploadPickedVideo,
                  ),
                ),
              ],
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
              _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: () async {
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

            const SizedBox(height: 24),

            // ----------------- Last 3 Recorded Days -----------------
            if (last3Dates.isNotEmpty)
              Text("Last 3 Recorded Days", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            ...last3Dates.map((date) {
              final sessions = sessionsByDate[date] ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  title: Text("${date.month}/${date.day}/${date.year}"),
                  children: sessions.map((s) {
                    return Dismissible(
                      key: Key(s['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: Colors.red,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteSession(s['id']),
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center),
                        title: Text("Weight: ${s['weight']}"),
                        subtitle: Text("Reps: ${s['reps']}"),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
