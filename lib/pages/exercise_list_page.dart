import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> exercises = [];
  bool isLoading = true;

  final _exerciseService = ExerciseService();
  final _equipmentService = EquipmentService();

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => isLoading = true);
    final list = await _exerciseService.getExercisesForEquipment(
      widget.equipmentId,
    );

    final sorted = List<Map<String, dynamic>>.from(list)
      ..sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      );

    setState(() {
      exercises = sorted;
      isLoading = false;
    });
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
                          DropdownMenuItem(
                            value: 'chest',
                            child: Text('Chest'),
                          ),
                          DropdownMenuItem(
                            value: 'shoulders',
                            child: Text('Shoulders'),
                          ),
                          DropdownMenuItem(value: 'arms', child: Text('Arms')),
                          DropdownMenuItem(value: 'legs', child: Text('Legs')),
                          DropdownMenuItem(value: 'core', child: Text('Core')),
                        ],
                        onChanged: (val) {
                          if (val != null)
                            setDialogState(() => primaryMuscleGroup = val);
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

    // load equipment
    final equipmentListDynamic = await _equipmentService.getAllEquipment();
    final equipmentList =
        equipmentListDynamic
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
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
                (selectedEquipmentId != null &&
                    selectedEquipmentId!.isNotEmpty) ||
                newName.isNotEmpty;

            return AlertDialog(
              title: Text('Move “$exerciseName”'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Move to existing equipment:'),
                  const SizedBox(height: 8),

                  // ---------- EXISTING EQUIPMENT DROPDOWN ----------
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
                        ? null // 🔒 disabled while typing new name
                        : (val) {
                            setDialogState(() {
                              selectedEquipmentId = val;
                              if (val != null) {
                                newEquipmentController.text = '';
                              }
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

                  // ---------- NEW EQUIPMENT TEXT FIELD ----------
                  TextField(
                    controller: newEquipmentController,
                    enabled:
                        selectedEquipmentId ==
                        null, // 🔒 disabled if dropdown selected
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
                            // Create new equipment then move
                            final created = await _equipmentService
                                .insertEquipment(typedName);
                            targetEquipmentId = created['id'].toString();
                            targetEquipmentName = created['name'].toString();
                          } else {
                            // Move to existing equipment
                            targetEquipmentId = selectedEquipmentId!;
                            targetEquipmentName = equipmentList
                                .firstWhere(
                                  (e) =>
                                      e['id'].toString() == selectedEquipmentId,
                                )['name']
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
                              content: Text(
                                '“$exerciseName” moved to $targetEquipmentName',
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );

                          // If moved off this equipment, refresh list
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

    final sessionCount = await _exerciseService.getSessionCountForExercise(
      exerciseId,
    );

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
  Future<void> _onMenuSelected(
    String value,
    Map<String, dynamic> exercise,
  ) async {
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
          ? const Center(
              child: Text("No exercises available for this equipment."),
            )
          : ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final exercise = exercises[index];

                return ListTile(
                  title: Text(exercise['name']),
                  subtitle: Text(
                    "${exercise['primary_muscle_group']} • ${exercise['type']}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fitness_center),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (value) => _onMenuSelected(value, exercise),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit name'),
                          ),
                          PopupMenuItem(
                            value: 'move',
                            child: Text('Move to equipment…'),
                          ),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseSessionPage(exercise: exercise),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
    );
  }
}
