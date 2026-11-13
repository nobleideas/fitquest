import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'exercise_service.dart';

/// Lives independently of an exercise page, so navigation does not cancel jobs.
/// Jobs remain in memory: closing/reloading the web app stops them.
class VideoUploadManager {
  VideoUploadManager._();
  static final VideoUploadManager instance = VideoUploadManager._();

  final ValueNotifier<Map<String, bool>> activeExercises =
      ValueNotifier<Map<String, bool>>(<String, bool>{});

  OverlayEntry? _notice;
  final ValueNotifier<_UploadNotice> _noticeState = ValueNotifier(
    const _UploadNotice('Preparing video...', true),
  );

  bool isUploading(String exerciseId) =>
      activeExercises.value[exerciseId] == true;

  Future<String> start({
    required BuildContext context,
    required String exerciseId,
    required XFile video,
    required String exerciseName,
  }) {
    if (activeExercises.value.isNotEmpty) {
      throw StateError('Please wait for the current video upload to finish.');
    }

    activeExercises.value = {...activeExercises.value, exerciseId: true};
    _showNotice(context);
    _noticeState.value = _UploadNotice(
      'Processing "$exerciseName" video. You can use other pages in FitQuest while it finishes. Keep the app open and visible.',
      true,
    );

    // This future is owned by the singleton, not by the exercise page.
    return _performUpload(exerciseId: exerciseId, video: video,
        exerciseName: exerciseName);
  }

  Future<String> _performUpload({
    required String exerciseId,
    required XFile video,
    required String exerciseName,
  }) async {
    try {
      final url = await ExerciseService().uploadUserFormVideo(
        exerciseId: exerciseId,
        video: video,
      );
      _noticeState.value = _UploadNotice(
        'Video uploaded successfully: $exerciseName', false,
      );
      return url;
    } catch (e) {
      _noticeState.value = _UploadNotice(
        'Video upload failed: $e', false,
      );
      rethrow;
    } finally {
      final updated = {...activeExercises.value}..remove(exerciseId);
      activeExercises.value = updated;
    }
  }

  void _showNotice(BuildContext context) {
    if (_notice != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _notice = OverlayEntry(
      builder: (_) => Positioned(
        left: 12,
        right: 12,
        bottom: 16,
        child: SafeArea(
          top: false,
          child: Material(
            color: const Color(0xFF211832),
            elevation: 10,
            borderRadius: BorderRadius.circular(14),
            child: ValueListenableBuilder<_UploadNotice>(
              valueListenable: _noticeState,
              builder: (context, state, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    if (state.busy)
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.video_file_outlined, color: Colors.white70),
                    const SizedBox(width: 12),
                    Expanded(child: Text(state.message,
                        style: const TextStyle(color: Colors.white, fontSize: 13))),
                    if (!state.busy)
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: dismiss,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_notice!);
  }

  void dismiss() {
    _notice?.remove();
    _notice?.dispose();
    _notice = null;
  }
}

class _UploadNotice {
  final String message;
  final bool busy;
  const _UploadNotice(this.message, this.busy);
}
