import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendProfilePage extends StatefulWidget {
  final String friendUserId;
  final String friendUsername; // passed from list; can be refreshed via RPC if you want

  const FriendProfilePage({
    super.key,
    required this.friendUserId,
    required this.friendUsername,
  });

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late final TabController _tabController;

  // Data
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final friendId = widget.friendUserId;

      final results = await Future.wait<dynamic>([
        supabase.rpc('get_friend_workout_history', params: {
          'friend_user_id': friendId,
          'max_rows': 250,
        }),
        supabase.rpc('get_friend_equipment', params: {
          'friend_user_id': friendId,
        }),
        supabase.rpc('get_friend_exercises', params: {
          'friend_user_id': friendId,
        }),
      ]);

      final historyRaw = results[0];
      final equipmentRaw = results[1];
      final exercisesRaw = results[2];

      setState(() {
        _history = historyRaw is List ? List<Map<String, dynamic>>.from(historyRaw) : [];
        _equipment = equipmentRaw is List ? List<Map<String, dynamic>>.from(equipmentRaw) : [];
        _exercises = exercisesRaw is List ? List<Map<String, dynamic>>.from(exercisesRaw) : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDateTime(dynamic ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts.toString());
    if (dt == null) return ts.toString();
    final local = dt.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return "$m/$d/$y • $hh:$mm $ap";
    }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.friendUsername.isNotEmpty ? "@${widget.friendUsername}" : "Friend";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "History"),
            Tab(text: "Equipment"),
            Tab(text: "Exercises"),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _BlockedOrErrorView(
                  message:
                      "Couldn't load friend data.\n\nThis usually means you aren't accepted friends yet (or an RPC error occurred).\n\n$_error",
                  onRetry: _loadAll,
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _HistoryTab(history: _history, fmtDateTime: _fmtDateTime),
                    _EquipmentTab(equipment: _equipment),
                    _ExercisesTab(exercises: _exercises),
                  ],
                ),
    );
  }
}

class _BlockedOrErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _BlockedOrErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final String Function(dynamic) fmtDateTime;

  const _HistoryTab({required this.history, required this.fmtDateTime});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(child: Text("No workout history found."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = history[i];
        final exercise = (row['exercise_name'] ?? '').toString();
        final equipment = (row['equipment_name'] ?? '').toString();
        final weight = row['weight'];
        final reps = row['reps'];
        final when = fmtDateTime(row['created_at']);

        return Card(
          child: ListTile(
            title: Text(exercise),
            subtitle: Text("$equipment\n$when"),
            isThreeLine: true,
            trailing: Text(
              "${weight ?? ''} x ${reps ?? ''}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}

class _EquipmentTab extends StatelessWidget {
  final List<Map<String, dynamic>> equipment;

  const _EquipmentTab({required this.equipment});

  @override
  Widget build(BuildContext context) {
    if (equipment.isEmpty) {
      return const Center(child: Text("No equipment found."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: equipment.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = equipment[i];
        return ListTile(
          leading: const Icon(Icons.fitness_center),
          title: Text((e['name'] ?? '').toString()),
        );
      },
    );
  }
}

class _ExercisesTab extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;

  const _ExercisesTab({required this.exercises});

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return const Center(child: Text("No exercises found."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: exercises.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final ex = exercises[i];
        final name = (ex['name'] ?? '').toString();
        final equipName = (ex['equipment_name'] ?? '').toString();
        final mg = (ex['primary_muscle_group'] ?? '').toString();
        final type = (ex['type'] ?? '').toString();

        return Card(
          child: ListTile(
            title: Text(name),
            subtitle: Text("$equipName • $mg • $type"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // optional later: show that exercise's history detail
              // you can navigate to another page with friend exercise sessions filtered by exercise_id
            },
          ),
        );
      },
    );
  }
}
