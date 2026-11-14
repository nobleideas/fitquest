import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'exercise_service.dart';

/// Singleton: uploads continue while navigating between FitQuest pages.
/// Jobs are in memory and do not survive closing or reloading the web app.
class VideoUploadManager {
  VideoUploadManager._();
  static final VideoUploadManager instance = VideoUploadManager._();

  final ValueNotifier<Map<String, bool>> activeExercises =
      ValueNotifier<Map<String, bool>>(<String, bool>{});
  final List<_VideoJob> _queue = <_VideoJob>[];
  bool _processing = false;
  OverlayEntry? _notice;
  OverlayState? _rootOverlay;
  Timer? _hideTimer;
  double _top = 90;
  double _left = 12;
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
    if (isUploading(exerciseId)) {
      throw StateError('A video for this exercise is already uploading or queued.');
    }

    // Keep the root overlay so a completion message can be shown even after
    // the exercise page that started this upload has been popped.
    _rootOverlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<String>();
    _queue.add(_VideoJob(exerciseId, video, exerciseName, completer));
    activeExercises.value = {...activeExercises.value, exerciseId: true};

    _showMessage(
      'Uploading video for "$exerciseName". You can continue using FitQuest.',
      busy: true,
      duration: const Duration(seconds: 4),
    );
    if (!_processing) unawaited(_processQueue());
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        try {
          final url = await ExerciseService().uploadUserFormVideo(
            exerciseId: job.exerciseId,
            video: job.video,
          );
          job.completer.complete(url);
          _showMessage(
            'Video uploaded successfully for "${job.exerciseName}".',
            busy: false,
            duration: const Duration(seconds: 6),
          );
        } catch (e) {
          job.completer.completeError(e);
          _showMessage(
            'Video upload failed for "${job.exerciseName}": $e',
            busy: false,
            // Errors remain until dismissed so they cannot be missed.
          );
        } finally {
          activeExercises.value = {...activeExercises.value}
            ..remove(job.exerciseId);
        }
      }
    } finally {
      _processing = false;
    }
  }

  void _showMessage(
    String message, {
    required bool busy,
    Duration? duration,
  }) {
    _hideTimer?.cancel();
    _hideTimer = null;
    _noticeState.value = _UploadNotice(message, busy);
    _showNotice();
    if (duration != null) {
      _hideTimer = Timer(duration, dismiss);
    }
  }

  void _showNotice() {
    if (_notice != null) return;
    final overlay = _rootOverlay;
    if (overlay == null || !overlay.mounted) return;

    _notice = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.sizeOf(overlayContext);
        return Positioned(
          top: _top.clamp(0.0, (screen.height - 100).clamp(0.0, double.infinity)).toDouble(),
          left: _left.clamp(0.0, (screen.width - 100).clamp(0.0, double.infinity)).toDouble(),
          width: (screen.width - _left - 12).clamp(100.0, screen.width).toDouble(),
          child: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) {
                _top = (_top + details.delta.dy)
                    .clamp(0.0, (screen.height - 100).clamp(0.0, double.infinity))
                    .toDouble();
                _left = (_left + details.delta.dx)
                    .clamp(0.0, (screen.width - 100).clamp(0.0, double.infinity))
                    .toDouble();
                _notice?.markNeedsBuild();
              },
              child: Material(
                color: const Color(0xFF211832),
                elevation: 10,
                borderRadius: BorderRadius.circular(14),
                child: ValueListenableBuilder<_UploadNotice>(
                  valueListenable: _noticeState,
                  builder: (context, state, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      if (state.busy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.video_file_outlined, color: Colors.white70),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.message,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      const Icon(Icons.drag_indicator, color: Colors.white54, size: 18),
                      IconButton(
                          tooltip: 'Dismiss',
                          onPressed: dismiss,
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_notice!);
  }

  void dismiss() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _notice?.remove();
    _notice?.dispose();
    _notice = null;
  }
}

class _VideoJob {
  final String exerciseId;
  final XFile video;
  final String exerciseName;
  final Completer<String> completer;
  _VideoJob(this.exerciseId, this.video, this.exerciseName, this.completer);
}

class _UploadNotice {
  final String message;
  final bool busy;
  const _UploadNotice(this.message, this.busy);
}
