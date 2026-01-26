import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/exercise_service.dart';
import '../services/equipment_service.dart';
import 'exercise_session_page.dart';

class ExerciseListPage extends StatefulWidget {
  final String equipmentId;
  final String equipmentName;

  const ExerciseListPage({
    super.key,
    required this.equipmentId,
    required this.equipmentName,
  });

  @override
  State<ExerciseListPage> createState() => _ExerciseListPageState();
}

class _ExerciseListPageState extends State<ExerciseListPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> exercises = [];
  bool isLoading = true;

  final _exerciseService = ExerciseService();
  final _equipmentService = EquipmentService();

  /// Exercise IDs that have at least one session today (for this equipment)
  Set<String> exercisesWithSessionsToday = {};

  /// ✅ For imported exercises: which *source* exercises still have a video_url
  final Set<String> _sourceExercisesWithVideo = {};

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  String _cleanStr(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    if (s.toLowerCase() == 'null') return '';
    return s;
  }

  bool _hasDirectVideo(Map<String, dynamic> ex) {
    final url = _cleanStr(ex['video_url']);
    return url.isNotEmpty;
  }

  String _sourceId(Map<String, dynamic> ex) {
    return _cleanStr(ex['video_source_exercise_id']);
  }

  bool _hasFormVideo(Map<String, dynamic> ex) {
    // ✅ Local video saved on THIS exercise row
    if (_hasDirectVideo(ex)) return true;

    // ✅ Imported: only show as "has video" if source still has video_url
    final srcId = _sourceId(ex);
    if (srcId.isEmpty) return false;

    return _sourceExercisesWithVideo.contains(srcId);
  }

  Future<void> _loadExercises() async {
    setState(() => isLoading = true);

    try {
      final list = await _exerciseService.getExercisesForEquipment(
        widget.equipmentId,
      );

      // Base alphabetical sort (case-insensitive)
      final sorted = List<Map<String, dynamic>>.from(list)
        ..sort(
          (a, b) => (a['name'] as String).toLowerCase().compareTo(
                (b['name'] as String).toLowerCase(),
              ),
        );

      // ✅ Determine which exercises were used today
      final todaySet = await _loadExerciseIdsWithSessionsToday();

      // ✅ Verify imported video sources still exist
      await _refreshSourceVideoCache(sorted);

      // Reorder: used today (alpha) first, then the rest (alpha)
      final usedToday = <Map<String, dynamic>>[];
      final notUsedToday = <Map<String, dynamic>>[];

      for (final ex in sorted) {
        final id = ex['id']?.toString() ?? '';
        if (todaySet.contains(id)) {
          usedToday.add(ex);
        } else {
          notUsedToday.add(ex);
        }
      }

      if (!mounted) return;
      setState(() {
        exercises = [...usedToday, ...notUsedToday];
        exercisesWithSessionsToday = todaySet;
        isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading exercises: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        exercises = [];
        exercisesWithSessionsToday = {};
        _sourceExercisesWithVideo.clear();
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load exercises: $e')),
      );
    }
  }

  /// ✅ Build a cache of source exercise IDs that *currently* have a video_url.
  /// This prevents the icon from showing when the original friend deleted the video.
  Future<void> _refreshSourceVideoCache(List<Map<String, dynamic>> exList) async {
    _sourceExercisesWithVideo.clear();

    final sourceIds = <String>{};

    for (final ex in exList) {
      // Only care about imported exercises that do NOT have a direct local video
      if (_hasDirectVideo(ex)) continue;

      final srcId = _sourceId(ex);
      if (srcId.isNotEmpty) sourceIds.add(srcId);
    }

    if (sourceIds.isEmpty) return;

    // Supabase "in" can be picky about size; but your lists are usually small.
    // If you ever hit large lists, we can chunk this.
    final rows = await supabase
        .from('exercises')
        .select('id, video_url')
        .inFilter('id', sourceIds.toList());

    for (final r in rows) {
      final id = _cleanStr(r['id']);
      final url = _cleanStr(r['video_url']);
      if (id.isNotEmpty && url.isNotEmpty) {
        _sourceExercisesWithVideo.add(id);
      }
    }
  }

  /// Load exercise IDs (for this equipment) that have at least one session today.
  Future<Set<String>> _loadExerciseIdsWithSessionsToday() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final nowLocal = DateTime.now();
    final startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final endLocal = startLocal.add(const Duration(days: 1));

    // Convert to UTC for consistent filtering with timestamptz
    final startUtc = startLocal.toUtc().toIso8601String();
    final endUtc = endLocal.toUtc().toIso8601String();

    final rows = await supabase
        .from('exercise_sessions')
        .select('exercise_id, created_at, exercises!inner(id, equipment_id)')
        .eq('user_id', user.id)
        .eq('exercises.equipment_id', widget.equipmentId)
        .gte('created_at', startUtc)
        .lt('created_at', endUtc);

    final ids = <String>{};
    for (final row in rows) {
      final exId = row['exercise_id'];
      if (exId != null) ids.add(exId.toString());
    }

    return ids;
  }

  // ---------- ADD EXERCISE ----------
  Future<void> _addExercise() async {
    final nameController = TextEditingController();

    String primaryMuscleGroup = 'back';
    String type = 'push';

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Add New Exercise"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Exercise Name",
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("Muscle: "),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: primaryMuscleGroup,
                        items: const [
                          DropdownMenuItem(value: 'back', child: Text('Back')),
                          DropdownMenuItem(value: 'chest', child: Text('Chest')),
                          DropdownMenuItem(value: 'shoulders', child: Text('Shoulders')),
                          DropdownMenuItem(value: 'arms', child: Text('Arms')),
                          DropdownMenuItem(value: 'legs', child: Text('Legs')),
                          DropdownMenuItem(value: 'core', child: Text('Core')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => primaryMuscleGroup = val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text("Type: "),
                      const SizedBox(width: 16),
                      DropdownButton<String>(
                        value: type,
                        items: const [
                          DropdownMenuItem(value: 'push', child: Text('Push')),
                          DropdownMenuItem(value: 'pull', child: Text('Pull')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => type = val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;

                    await _exerciseService.insertExercise(
                      name: name,
                      primaryMuscleGroup: primaryMuscleGroup,
                      type: type,
                      equipmentId: widget.equipmentId,
                    );

                    if (!mounted) return;
                    Navigator.pop(context);
                    await _loadExercises();
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------- EDIT EXERCISE NAME ----------
  Future<void> _editExerciseName(Map<String, dynamic> exercise) async {
    final currentName = (exercise['name'] ?? '').toString();
    final controller = TextEditingController(text: currentName);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Exercise Name"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Exercise Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;

              final exerciseId = exercise['id'].toString();

              await _exerciseService.updateExerciseName(
                exerciseId: exerciseId,
                name: newName,
              );

              if (!mounted) return;
              Navigator.pop(context);
              await _loadExercises();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // ---------- MOVE EXERCISE ----------
  Future<void> _moveExercise(Map<String, dynamic> exercise) async {
    final exerciseId = exercise['id'].toString();
    final exerciseName = (exercise['name'] ?? 'Exercise').toString();
    String? targetEquipmentName;

    final equipmentListDynamic = await _equipmentService.getAllEquipment();
    final equipmentList =
        equipmentListDynamic.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          ..sort(
            (a, b) => (a['name'] as String).toLowerCase().compareTo(
                  (b['name'] as String).toLowerCase(),
                ),
          );

    String? selectedEquipmentId;
    final newEquipmentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final newName = newEquipmentController.text.trim();
            final canMove =
                (selectedEquipmentId != null && selectedEquipmentId!.isNotEmpty) ||
                    newName.isNotEmpty;

            return AlertDialog(
              title: Text('Move “$exerciseName”'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Move to existing equipment:'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedEquipmentId,
                    isExpanded: true,
                    items: [
                      for (final e in equipmentList)
                        DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text(e['name'].toString()),
                        ),
                    ],
                    onChanged: newEquipmentController.text.isNotEmpty
                        ? null
                        : (val) {
                            setDialogState(() {
                              selectedEquipmentId = val;
                              if (val != null) newEquipmentController.text = '';
                            });
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select equipment',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Or create a new equipment:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newEquipmentController,
                    enabled: selectedEquipmentId == null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'New equipment name',
                    ),
                    onChanged: (_) {
                      setDialogState(() {
                        if (newEquipmentController.text.isNotEmpty) {
                          selectedEquipmentId = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canMove
                      ? () async {
                          String targetEquipmentId;

                          final typedName = newEquipmentController.text.trim();

                          if (typedName.isNotEmpty) {
                            final created =
                                await _equipmentService.insertEquipment(typedName);
                            targetEquipmentId = created['id'].toString();
                            targetEquipmentName = created['name'].toString();
                          } else {
                            targetEquipmentId = selectedEquipmentId!;
                            targetEquipmentName = equipmentList
                                .firstWhere((e) => e['id'].toString() == selectedEquipmentId)['name']
                                .toString();
                          }

                          await _exerciseService.moveExerciseToEquipment(
                            exerciseId: exerciseId,
                            equipmentId: targetEquipmentId,
                          );

                          if (!mounted) return;
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('“$exerciseName” moved to $targetEquipmentName'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );

                          await _loadExercises();
                        }
                      : null,
                  child: const Text('Move'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------- DELETE EXERCISE ----------
  Future<void> _deleteExercise(Map<String, dynamic> exercise) async {
    final name = (exercise['name'] ?? 'this exercise').toString();
    final exerciseId = exercise['id'].toString();

    final sessionCount = await _exerciseService.getSessionCountForExercise(exerciseId);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Exercise?"),
        content: Text(
          sessionCount > 0
              ? "“$name” has $sessionCount recorded session${sessionCount == 1 ? '' : 's'}.\n\n"
                    "Deleting this exercise will also delete those session${sessionCount == 1 ? '' : 's'}.\n\n"
                    "Do you want to continue?"
              : "Are you sure you want to delete “$name”?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _exerciseService.deleteExerciseCascade(exerciseId);

    if (!mounted) return;
    await _loadExercises();
  }

  // ---------- MENU HANDLER ----------
  Future<void> _onMenuSelected(String value, Map<String, dynamic> exercise) async {
    switch (value) {
      case 'edit':
        await _editExerciseName(exercise);
        break;
      case 'move':
        await _moveExercise(exercise);
        break;
      case 'delete':
        await _deleteExercise(exercise);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.equipmentName)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : exercises.isEmpty
              ? const Center(child: Text("No exercises available for this equipment."))
              : RefreshIndicator(
                  onRefresh: _loadExercises,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      final exerciseId = exercise['id']?.toString() ?? '';
                      final hasSessionToday = exercisesWithSessionsToday.contains(exerciseId);

                      final hasVideo = _hasFormVideo(exercise);

                      return ListTile(
                        title: Text(
                          exercise['name'],
                          style: hasSessionToday
                              ? TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                        ),
                        subtitle: Text("${exercise['primary_muscle_group']} • ${exercise['type']}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: hasVideo ? 'Form video available' : 'No form video',
                              child: Icon(
                                hasVideo ? Icons.play_circle_fill : Icons.videocam_off,
                                color: hasVideo
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).disabledColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(hasSessionToday ? Icons.check_circle : Icons.fitness_center),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              onSelected: (value) => _onMenuSelected(value, exercise),
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit name')),
                                PopupMenuItem(value: 'move', child: Text('Move to equipment…')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExerciseSessionPage(exercise: exercise),
                            ),
                          );
                          await _loadExercises();
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
    );
  }
}
