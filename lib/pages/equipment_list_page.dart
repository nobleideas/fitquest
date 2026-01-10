import 'package:flutter/material.dart';
import '../services/equipment_service.dart';
import 'exercise_list_page.dart';
import 'profile_page.dart'; // <-- Import ProfilePage

class EquipmentListPage extends StatefulWidget {
  const EquipmentListPage({super.key});

  @override
  State<EquipmentListPage> createState() => _EquipmentListPageState();
}

class _EquipmentListPageState extends State<EquipmentListPage> {
  List<Map<String, dynamic>> equipmentList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    setState(() => isLoading = true);
    final list = await EquipmentService().getAllEquipment();

    final sorted = List<Map<String, dynamic>>.from(list)
      ..sort((a, b) => (a['name'] as String)
          .toLowerCase()
          .compareTo((b['name'] as String).toLowerCase()));

    setState(() {
      equipmentList = sorted;
      isLoading = false;
    });
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

              // Insert new equipment
              await EquipmentService().insertEquipment(name);

              Navigator.pop(context);
              await _loadEquipment(); // reload list
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Equipment"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Go to Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: equipmentList.length,
              itemBuilder: (context, index) {
                final equipment = equipmentList[index];

                return ListTile(
                  title: Text(equipment['name']),
                  subtitle: Text("QR: ${equipment['qr_code'] ?? 'N/A'}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseListPage(
                          equipmentId: equipment['id'],
                          equipmentName: equipment['name'],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEquipment,
        tooltip: 'Add Equipment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
