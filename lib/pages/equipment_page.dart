import 'package:flutter/material.dart';
import 'package:flutter_application_template_1/services/equipment_service.dart';
import 'package:flutter_application_template_1/services/exercise_service.dart';
import 'exercise_session_page.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  List<Map<String, dynamic>> equipments = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEquipments();
  }

  Future<void> _loadEquipments() async {
    setState(() => isLoading = true);
    final list = await EquipmentService().getAllEquipment(); // fetch all equipment
    setState(() {
      equipments = List<Map<String, dynamic>>.from(list);
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
          decoration: const InputDecoration(labelText: "Equipment Name"),
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
              await EquipmentService().insertEquipment(name); // insert into Supabase
              Navigator.pop(context);
              await _loadEquipments(); // reload list
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
      appBar: AppBar(title: const Text("Equipment")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: equipments.map((equipment) {
                return ListTile(
                  title: Text(equipment['name']),
                  onTap: () async {
                    // Navigate to exercises for this equipment
                    final exercises = await ExerciseService().getExercisesForEquipment(equipment['id']);
                    if (exercises.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseSessionPage(exercise: exercises[0]), // open first exercise as example
                      ),
                    );
                  },
                );
              }).toList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEquipment,
        child: const Icon(Icons.add),
        backgroundColor: Colors.blue, // force visibility
      ),
    );
  }
}
