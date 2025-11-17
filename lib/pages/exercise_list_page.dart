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
    final list = await ExerciseService().getExercisesForEquipment(widget.equipmentId);
    setState(() {
      exercises = List<Map<String, dynamic>>.from(list);
      isLoading = false;
    });
  }

  Future<void> _addExercise() async {
    final nameController = TextEditingController();
    final muscleController = TextEditingController();
    String type = 'push'; // default value for database

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
                    decoration: const InputDecoration(labelText: "Exercise Name"),
                  ),
                  TextField(
                    controller: muscleController,
                    decoration: const InputDecoration(labelText: "Primary Muscle Group"),
                  ),
                  const SizedBox(height: 12),
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
                              type = val; // update selected type
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
                    final muscle = muscleController.text.trim();
                    if (name.isEmpty || muscle.isEmpty) return;

                    await ExerciseService().insertExercise(
                      name: name,
                      primaryMuscleGroup: muscle,
                      type: type, // lowercase
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
              ? const Center(child: Text("No exercises available for this equipment."))
              : ListView.builder(
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = exercises[index];

                    return ListTile(
                      title: Text(exercise['name']),
                      subtitle: Text("${exercise['primary_muscle_group']} • ${exercise['type']}"),
                      trailing: const Icon(Icons.fitness_center),
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
