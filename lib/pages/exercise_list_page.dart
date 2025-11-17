import 'package:flutter/material.dart';
import '../services/exercise_service.dart';
import 'exercise_session_page.dart';

class ExerciseListPage extends StatelessWidget {
  final String equipmentId;
  final String equipmentName;

  const ExerciseListPage({
    super.key,
    required this.equipmentId,
    required this.equipmentName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(equipmentName)),
      body: FutureBuilder(
        future: ExerciseService().getExercisesForEquipment(equipmentId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final exercises = snapshot.data as List<dynamic>;

          if (exercises.isEmpty) {
            return const Center(
              child: Text("No exercises available for this equipment."),
            );
          }

          return ListView.builder(
            itemCount: exercises.length,
            itemBuilder: (context, index) {
              final exercise = exercises[index];

              return ListTile(
                title: Text(exercise['name']),
                subtitle: Text(
                  "${exercise['primary_muscle_group']} • ${exercise['type']}",
                ),
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
          );
        },
      ),
    );
  }
}
