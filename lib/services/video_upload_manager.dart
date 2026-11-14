import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'exercise_service.dart';

/// Singleton: uploads continue when users navigate between FitQuest pages.
/// The queue is in memory and does not survive closing/reloading the web app.
class VideoUploadManager {
  VideoUploadManager._();
  static final VideoUploadManager instance = VideoUploadManager._();

  /// Includes queued and currently uploading exercises.
  final ValueNotifier<Map<String, bool>> activeExercises =
      ValueNotifier<Map<String, bool>>(<String, bool>{});

  final List<_VideoJob> _queue = <_VideoJob>[];
  bool _processing = false;
  OverlayEntry? _notice;
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

    final completer = Completer<String>();
    _queue.add(_VideoJob(exerciseId, video, exerciseName, completer));
    activeExercises.value = {...activeExercises.value, exerciseId: true};
    _showNotice(context);
    _updateQueuedNotice();
    if (!_processing) unawaited(_processQueue());
    return completer.future;
  }

  void _updateQueuedNotice() {
    if (_processing) return;
    _noticeState.value = _UploadNotice(
      'Video uploads queued: ${_queue.length}. Keep FitQuest open and visible.',
      true,
    );
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      final remaining = _queue.length;
      _noticeState.value = _UploadNotice(
        'Uploading "${job.exerciseName}"${remaining > 0 ? ' ($remaining waiting)' : ''}. '
        'You can navigate FitQuest. Keep the app open and visible. Drag this notice to move it.',
        true,
      );
      try {
        final url = await ExerciseService().uploadUserFormVideo(
          exerciseId: job.exerciseId,
          video: job.video,
        );
        job.completer.complete(url);
        _noticeState.value = _UploadNotice(
          'Uploaded "${job.exerciseName}" successfully.', false,
        );
      } catch (e) {
        job.completer.completeError(e);
        _noticeState.value = _UploadNotice(
          'Upload failed for "${job.exerciseName}": $e', false,
        );
      } finally {
        activeExercises.value = {...activeExercises.value}
          ..remove(job.exerciseId);
      }
    }
    _processing = false;
  }

  void _showNotice(BuildContext context) {
    if (_notice != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
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
                        const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        const Icon(Icons.video_file_outlined, color: Colors.white70),
                      const SizedBox(width: 12),
                      Expanded(child: Text(state.message,
                          style: const TextStyle(color: Colors.white, fontSize: 13))),
                      const Icon(Icons.drag_indicator, color: Colors.white54, size: 18),
                      if (!state.busy)
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
