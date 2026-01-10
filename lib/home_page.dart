import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/equipment_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  /// Local workout day -> unique exercise names
  Map<DateTime, List<String>> exercisesByDay = {};

  @override
  void initState() {
    super.initState();
    _loadRecentExercises();
  }

  /* -------------------------------------------------------------------------- */
  /*                     LOAD ALL WORKOUT DAYS (UNIQUE EXERCISES)               */
  /* -------------------------------------------------------------------------- */
  Future<void> _loadRecentExercises() async {
    setState(() => isLoading = true);

    final userId = supabase.auth.currentUser!.id;

    final sessions = await supabase
        .from('exercise_sessions')
        .select('created_at, exercises!inner(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final List<DateTime> workoutDays = [];
    for (final row in sessions) {
      final local = DateTime.parse(row['created_at']).toLocal();
      final day = DateTime(local.year, local.month, local.day);

      if (!workoutDays.contains(day)) {
        workoutDays.add(day);
      }
    }

    final Map<DateTime, Set<String>> temp = {};
    for (final row in sessions) {
      final local = DateTime.parse(row['created_at']).toLocal();
      final day = DateTime(local.year, local.month, local.day);

      final exerciseName = row['exercises']['name'] as String;

      temp.putIfAbsent(day, () => <String>{});
      temp[day]!.add(exerciseName);
    }

    final Map<DateTime, List<String>> result = {};
    for (final day in workoutDays) {
      final exercises = temp[day] ?? {};
      result[day] = exercises.toList()..sort();
    }

    setState(() {
      exercisesByDay = result;
      isLoading = false;
    });
  }

  /* -------------------------------------------------------------------------- */
  /*                                   UI                                       */
  /* -------------------------------------------------------------------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fit Quest')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EquipmentListPage(),
                  ),
                );
              },
              child: const Text("View My Equipment"),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            const Text(
              'Recent Workouts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (exercisesByDay.isEmpty)
              const Text('No workouts logged yet.')
            else
              ...exercisesByDay.entries.map((entry) {
                final date = entry.key;
                final exercises = entry.value;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.month}/${date.day}/${date.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...exercises.map((name) => Text('• $name')),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
