import 'package:flutter/material.dart';
import '../services/exercise_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => isLoading = true);
    final list =
        await ExerciseService().getExercisesForEquipment(widget.equipmentId);

    final sorted = List<Map<String, dynamic>>.from(list)
      ..sort((a, b) => (a['name'] as String)
          .toLowerCase()
          .compareTo((b['name'] as String).toLowerCase()));

    setState(() {
      exercises = sorted;
      isLoading = false;
    });
  }

  // ---------- ADD EXERCISE ----------
  Future<void> _addExercise() async {
    final nameController = TextEditingController();

    // Default values
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
                    decoration:
                        const InputDecoration(labelText: "Exercise Name"),
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
                              value: 'chest', child: Text('Chest')),
                          DropdownMenuItem(
                              value: 'shoulders', child: Text('Shoulders')),
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
                          if (val != null) {
                            setDialogState(() => type = val);
                          }
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

                    await ExerciseService().insertExercise(
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

              await ExerciseService().updateExerciseName(
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

  // ---------- DELETE EXERCISE ----------
  Future<void> _deleteExercise(Map<String, dynamic> exercise) async {
  final name = (exercise['name'] ?? 'this exercise').toString();
  final exerciseId = exercise['id'].toString();

  // 1) Check if sessions exist
  final sessionCount =
      await ExerciseService().getSessionCountForExercise(exerciseId);

  // 2) Show confirmation (different wording if sessions exist)
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

  // 3) Cascade delete
  await ExerciseService().deleteExerciseCascade(exerciseId);

  if (!mounted) return;
  await _loadExercises();
}


  // ---------- MENU HANDLER ----------
  Future<void> _onMenuSelected(String value, Map<String, dynamic> exercise) async {
    switch (value) {
      case 'edit':
        await _editExerciseName(exercise);
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
                      // Dumbbell icon + 3-dot menu
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fitness_center),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            onSelected: (value) =>
                                _onMenuSelected(value, exercise),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit name'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
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
