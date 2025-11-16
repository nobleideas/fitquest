import 'package:flutter/material.dart';
import '../services/session_service.dart';

class ExerciseSessionPage extends StatefulWidget {
  final Map<String, dynamic> exercise;

  const ExerciseSessionPage({
    super.key,
    required this.exercise,
  });

  @override
  State<ExerciseSessionPage> createState() => _ExerciseSessionPageState();
}

class _ExerciseSessionPageState extends State<ExerciseSessionPage> {
  final weightController = TextEditingController();
  final repsController = TextEditingController();

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise['name']),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              "Log your session",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),

            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Weight",
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Reps",
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () async {
                await SessionService().insertSession(
                  exerciseId: exercise['id'],
                  weight: double.parse(weightController.text),
                  reps: int.parse(repsController.text),
                );

                Navigator.pop(context);
              },
              child: const Text("Save Session"),
            )
          ],
        ),
      ),
    );
  }
}
