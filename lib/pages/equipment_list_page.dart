import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/equipment_service.dart';
import 'exercise_list_page.dart';

class EquipmentListPage extends StatefulWidget {
  const EquipmentListPage({super.key});

  @override
  State<EquipmentListPage> createState() => _EquipmentListPageState();
}

class _EquipmentListPageState extends State<EquipmentListPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> equipmentList = [];
  bool isLoading = true;

  /// Equipment IDs that have at least one exercise session today
  Set<String> equipmentWithSessionsToday = {};

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    setState(() => isLoading = true);

    try {
      final list = await EquipmentService().getAllEquipment();

      final sorted = List<Map<String, dynamic>>.from(list)
        ..sort((a, b) => (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase()));

      final todaySet = await _loadEquipmentIdsWithSessionsToday();

      if (!mounted) return;
      setState(() {
        equipmentList = sorted;
        equipmentWithSessionsToday = todaySet;
        isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading equipment: $e');
      debugPrint('$st');

      if (!mounted) return;
      setState(() {
        equipmentList = [];
        equipmentWithSessionsToday = {};
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load equipment: $e')),
      );
    }
  }

  /// Because exercise_sessions references exercise_id,
  /// we join to exercises to get exercises.equipment_id
  Future<Set<String>> _loadEquipmentIdsWithSessionsToday() async {
    final user = supabase.auth.currentUser;
    if (user == null) return {};

    final nowLocal = DateTime.now();
    final startLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final endLocal = startLocal.add(const Duration(days: 1));

    // Convert to UTC for consistent filtering with timestamptz
    final startUtc = startLocal.toUtc().toIso8601String();
    final endUtc = endLocal.toUtc().toIso8601String();

    final rows = await supabase
        .from('exercise_sessions')
        .select('created_at, exercises!inner(equipment_id)')
        .eq('user_id', user.id)
        .gte('created_at', startUtc)
        .lt('created_at', endUtc);

    final ids = <String>{};

    for (final row in rows) {
      final exJoined = row['exercises'];

      if (exJoined is Map<String, dynamic>) {
        final eqId = exJoined['equipment_id'];
        if (eqId != null) ids.add(eqId.toString());
      } else if (exJoined is List) {
        // In case the join comes back as a list
        for (final item in exJoined) {
          if (item is Map) {
            final eqId = item['equipment_id'];
            if (eqId != null) ids.add(eqId.toString());
          }
        }
      }
    }

    return ids;
  }

  Future<void> _addEquipment() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add New Equipment"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Equipment Name",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              await EquipmentService().insertEquipment(name);

              Navigator.pop(context);
              await _loadEquipment(); // reload list + today's highlights
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadEquipment,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: equipmentList.length,
                  itemBuilder: (context, index) {
                    final equipment = equipmentList[index];
                    final equipmentId = equipment['id']?.toString() ?? '';
                    final hasSessionToday =
                        equipmentWithSessionsToday.contains(equipmentId);

                    return ListTile(
                      title: Text(
                        equipment['name'],
                        style: hasSessionToday
                            ? TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                      subtitle: Text("QR: ${equipment['qr_code'] ?? 'N/A'}"),
                      trailing: hasSessionToday
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExerciseListPage(
                              equipmentId: equipment['id'],
                              equipmentName: equipment['name'],
                            ),
                          ),
                        );

                        // Refresh on return so highlight updates immediately
                        await _loadEquipment();
                      },
                    );
                  },
                ),
              ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _addEquipment,
            tooltip: 'Add Equipment',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
