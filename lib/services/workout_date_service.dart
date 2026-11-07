
import 'package:flutter/foundation.dart';

/// Shared workout date across FitQuest navigation.
/// null means normal logging using the current date/time.
class WorkoutDateService {
  WorkoutDateService._();

  static final WorkoutDateService instance = WorkoutDateService._();

  final ValueNotifier<DateTime?> selectedDate =
      ValueNotifier<DateTime?>(null);

  bool get isBacklogging => selectedDate.value != null;

  DateTime get activeDate => selectedDate.value ?? DateTime.now();

  void startBacklog(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (!normalized.isBefore(today)) {
      throw ArgumentError('Backlog date must be before today.');
    }

    selectedDate.value = normalized;
  }

  void finishBacklog() {
    selectedDate.value = null;
  }
}
