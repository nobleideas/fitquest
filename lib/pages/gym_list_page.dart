import 'package:flutter/material.dart';
import '../services/gym_service.dart';
import 'gym_detail_page.dart';

class GymListPage extends StatefulWidget {
  const GymListPage({super.key});

  @override
  State<GymListPage> createState() => _GymListPageState();
}

class _GymListPageState extends State<GymListPage> {
  final GymService gymService = GymService();
  List<Map<String, dynamic>> gyms = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGyms();
  }

  Future<void> _loadGyms() async {
    setState(() => isLoading = true);
    final list = await gymService.getUserGyms();
    setState(() {
      gyms = List<Map<String, dynamic>>.from(list);
      isLoading = false;
    });
  }

  Future<void> _createGym() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Create New Gym"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Gym Name"),
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
              await gymService.createGym(name);
              Navigator.pop(context);
              await _loadGyms();
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Your Gyms")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : gyms.isEmpty
              ? const Center(child: Text("You haven't created any gyms yet."))
              : ListView.builder(
                  itemCount: gyms.length,
                  itemBuilder: (context, index) {
                    final gym = gyms[index];
                    return ListTile(
                      title: Text(gym['name']),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GymDetailPage(
                              gym: gym,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGym,
        child: const Icon(Icons.add),
      ),
    );
  }
}
