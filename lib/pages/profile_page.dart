import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/xp_utils.dart';
import 'gym_list_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return FutureBuilder(
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
                      style: const TextStyle(fontSize: 22, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GymListPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: const Text("My Gyms"),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text("Log Out"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          await Supabase.instance.client.auth.signOut();
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Muscle Group XP",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              _xpBar("Back", profile['xp_back'] ?? 0),
              _xpBar("Chest", profile['xp_chest'] ?? 0),
              _xpBar("Shoulders", profile['xp_shoulders'] ?? 0),
              _xpBar("Arms", profile['xp_arms'] ?? 0),
              _xpBar("Legs", profile['xp_legs'] ?? 0),
              _xpBar("Core", profile['xp_core'] ?? 0),
            ],
          ),
        );
      },
    );
  }

  Widget _xpBar(String label, int xp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label — $xp XP", style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: min(xp / 5000, 1), minHeight: 10),
        const SizedBox(height: 20),
      ],
    );
  }
}
