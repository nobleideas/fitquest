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
  Map<DateTime, List<String>> exercisesByDay = {};

  @override
  void initState() {
    super.initState();
    _loadRecentExercises();
  }

  /* -------------------------------------------------------------------------- */
  /*                       LOAD RECENT WORKOUT EXERCISES                         */
  /* -------------------------------------------------------------------------- */

  Future<void> _loadRecentExercises() async {
  setState(() => isLoading = true);

  final userId = supabase.auth.currentUser!.id;

  // Step 1: fetch recent sessions
  final sessions = await supabase
      .from('exercise_sessions')
      .select('created_at')
      .eq('user_id', userId)
      .order('created_at', ascending: false);

  final Set<DateTime> uniqueDays = {};

  for (final row in sessions) {
    final utc = DateTime.parse(row['created_at']);
    final dayUtc = DateTime.utc(utc.year, utc.month, utc.day);
    uniqueDays.add(dayUtc);

    if (uniqueDays.length >= 3) break;
  }

  final sortedDays = uniqueDays.toList()
    ..sort((a, b) => b.compareTo(a));

  final Map<DateTime, List<String>> results = {};

  // Step 2: fetch exercise names per UTC day
  for (final dayUtc in sortedDays) {
    final startUtc = dayUtc;
    final endUtc = dayUtc.add(const Duration(days: 1));

    final response = await supabase
        .from('exercise_sessions')
        .select('exercises(name)')
        .eq('user_id', userId)
        .gte('created_at', startUtc.toIso8601String())
        .lt('created_at', endUtc.toIso8601String());

    final names = response
        .map<String>((row) => row['exercises']['name'] as String)
        .toSet()
        .toList();

    results[dayUtc.toLocal()] = names; // convert for display only
  }

  setState(() {
    exercisesByDay = results;
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
            /* -------------------------- RECENT WORKOUTS ------------------------- */
            const Text(
              'Recent Workouts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (exercisesByDay.isEmpty)
              const Text('No workouts logged.')
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
                      ...exercises.map(
                        (name) => Text('• $name'),
                      ),
                    ],
                  ),
                );
              }),

            const Divider(height: 32),

            /* -------------------------- NAVIGATION BUTTON ------------------------ */
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
          ],
        ),
      ),
    );
  }
}
