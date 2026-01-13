import 'package:flutter/material.dart';
import 'package:fit_quest/services/gym_service.dart';
import '../services/equipment_service.dart';
import 'exercise_list_page.dart';

class GymDetailPage extends StatefulWidget {
  final Map<String, dynamic> gym;

  const GymDetailPage({super.key, required this.gym});

  @override
  State<GymDetailPage> createState() => _GymDetailPageState();
}

class _GymDetailPageState extends State<GymDetailPage> {
  List<Map<String, dynamic>> gymEquipment = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGymEquipment();
  }

  Future<void> _loadGymEquipment() async {
    setState(() => isLoading = true);
    // Assuming you have a method to get equipment for a gym
    final list = await GymService().getGymEquipment(widget.gym['id']);
    setState(() {
      gymEquipment = List<Map<String, dynamic>>.from(list);
      isLoading = false;
    });
  }

  Future<void> _addEquipment(String equipmentId) async {
    await GymService().addEquipmentToGym(
      gymId: widget.gym['id'],
      equipmentId: equipmentId,
    );
    await _loadGymEquipment();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.gym['name'])),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: gymEquipment.length,
              itemBuilder: (context, index) {
                final equipment = gymEquipment[index];

                return ListTile(
                  title: Text(equipment['name']),
                  subtitle: Text("QR: ${equipment['qr_code'] ?? 'N/A'}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to exercises for this equipment
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
        heroTag: "add_equipment",
        child: const Icon(Icons.add),
        onPressed: () async {
          // Add equipment using a dropdown or selection dialog
          final allEquipment = await EquipmentService().getAllEquipment();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Add Equipment to Gym"),
              content: DropdownButtonFormField<String>(
                items: allEquipment.map<DropdownMenuItem<String>>((eq) {
                  return DropdownMenuItem<String>(
                    value: eq['id'] as String,
                    child: Text(eq['name']),
                  );
                }).toList(),
                onChanged: (val) async {
                  if (val != null) {
                    Navigator.pop(context);
                    await _addEquipment(val);
                  }
                },
                decoration: const InputDecoration(
                  labelText: "Select Equipment",
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
