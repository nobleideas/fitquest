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
                            setDialogState(() {
                              primaryMuscleGroup = val;
                            });
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
                            setDialogState(() {
                              type = val;
                            });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.equipmentName)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : exercises.isEmpty
              ? const Center(
                  child: Text("No exercises available for this equipment."))
              : ListView.builder(
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = exercises[index];

                    return ListTile(
                      title: Text(exercise['name']),
                      subtitle: Text(
                          "${exercise['primary_muscle_group']} • ${exercise['type']}"),
                      trailing: const Icon(Icons.fitness_center),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ExerciseSessionPage(exercise: exercise),
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
