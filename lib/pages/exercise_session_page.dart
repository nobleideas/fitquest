import 'package:flutter/material.dart';
import '../services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseSessionPage extends StatefulWidget {
  final Map<String, dynamic> exercise;
  const ExerciseSessionPage({super.key, required this.exercise});

  @override
  State<ExerciseSessionPage> createState() => _ExerciseSessionPageState();
}

class _ExerciseSessionPageState extends State<ExerciseSessionPage> {
  final weightController = TextEditingController();
  final repsController = TextEditingController();
  final SessionService sessionService = SessionService();
  List<DateTime> last3Dates = [];
  Map<DateTime, List<Map<String, dynamic>>> sessionsByDate = {};

  @override
  void initState() {
    super.initState();
    _loadLast3DatesAndSessions();
  }

  Future<void> _loadLast3DatesAndSessions() async {
    final dates = await sessionService.getLast3SessionDates(widget.exercise['id']);
    final Map<DateTime, List<Map<String, dynamic>>> map = {};

    for (final date in dates) {
      map[date] = await sessionService.getSessionsForDate(widget.exercise['id'], date);
    }

    setState(() {
      last3Dates = dates;
      sessionsByDate = map;
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    await sessionService.deleteSession(sessionId);
    await _loadLast3DatesAndSessions();
  }

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
      appBar: AppBar(title: Text(exercise['name'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------- Log Form -----------------
            Text(
              "Log Your Session",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Weight",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Reps",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("Save Session"),
                onPressed: () async {
                  final weight = double.tryParse(weightController.text);
                  final reps = int.tryParse(repsController.text);

                  if (weight == null || reps == null) return;

                  final res = await sessionService.insertSession(
                    exerciseId: exercise['id'],
                    weight: weight,
                    reps: reps,
                  );

                  final sessionID = res['id'];

                  await Supabase.instance.client.rpc(
                    'add_session_xp',
                    params: {'session_id': sessionID},
                  );


                  weightController.clear();
                  repsController.clear();
                  await _loadLast3DatesAndSessions();
                },
              ),
            ),
            const SizedBox(height: 24),

            // ----------------- Last 3 Recorded Days -----------------
            if (last3Dates.isNotEmpty)
              Text(
                "Last 3 Recorded Days",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 12),
            ...last3Dates.map((date) {
              final sessions = sessionsByDate[date] ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  title: Text("${date.month}/${date.day}/${date.year}"),
                  children: sessions.map((s) {
                    return Dismissible(
                      key: Key(s['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: Colors.red,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteSession(s['id']),
                      child: ListTile(
                        leading: const Icon(Icons.fitness_center),
                        title: Text("Weight: ${s['weight']}"),
                        subtitle: Text("Reps: ${s['reps']}"),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
