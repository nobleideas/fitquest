import 'package:flutter/material.dart';
import '../services/equipment_service.dart';
import 'exercise_list_page.dart';

class EquipmentListPage extends StatelessWidget {
  const EquipmentListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gym Equipment")),
      body: FutureBuilder(
        future: EquipmentService().getAllEquipment(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final equipmentList = snapshot.data as List<dynamic>;

          return ListView.builder(
            itemCount: equipmentList.length,
            itemBuilder: (context, index) {
              final equipment = equipmentList[index];

              return ListTile(
                title: Text(equipment['name']),
                subtitle: Text("QR: ${equipment['qr_code']}"),
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
          );
        },
      ),
    );
  }
}
