import 'package:flutter/material.dart';
import 'package:flutter_application_template_1/services/exercise_service.dart';
import 'exercise_session_page.dart';

class EquipmentPage extends StatelessWidget {
  final Map<String, dynamic> equipment;

  const EquipmentPage({super.key, required this.equipment});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ExerciseService().getExercisesForEquipment(equipment['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        final exercises = snapshot.data as List;

        return Scaffold(
          appBar: AppBar(title: Text(equipment['name'])),
          body: ListView(
            children: exercises.map((ex) {
              return ListTile(
                title: Text(ex['name']),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExerciseSessionPage(exercise: ex),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
