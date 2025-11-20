import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/xp_utils.dart';
import 'equipment_list_page.dart'; // <-- Import your EquipmentListPage

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Your Profile")),
      body: FutureBuilder(
        future: Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', user!.id)
            .single(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data as Map<String, dynamic>;
          final xp = XPUtils.totalXP(profile);
          final level = XPUtils.computeLevel(xp);
          final progress = XPUtils.levelProgress(xp);
          final rank = XPUtils.computeRank(xp);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank + Level section
                Center(
                  child: Column(
                    children: [
                      Text(
                        rank,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Level $level",
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Level progress bar
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                const Text(
                  "Muscle Group XP",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                _xpBar("Back", profile['xp_back']),
                _xpBar("Chest", profile['xp_chest']),
                _xpBar("Shoulders", profile['xp_shoulders']),
                _xpBar("Arms", profile['xp_arms']),
                _xpBar("Legs", profile['xp_legs']),
                _xpBar("Core", profile['xp_core']),
              ],
            ),
          );
        },
      ),
      // ------------------ Floating Action Button ------------------
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EquipmentListPage()),
          );
        },
        icon: const Icon(Icons.fitness_center),
        label: const Text("View Equipment"),
      ),
    );
  }

  Widget _xpBar(String label, int xp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label — $xp XP",
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: min(xp / 5000, 1), // 5k cap purely visual
          minHeight: 10,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
