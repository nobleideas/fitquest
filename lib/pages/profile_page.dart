import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/xp_utils.dart';
import 'gym_list_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  bool _isSavingGoal = false;

  static const _goalOptions = <String, String>{
    'lose_weight': 'Lose Weight',
    'gain_mass': 'Gain Mass',
    'gain_strength': 'Gain Strength',
  };

  String _goalLabel(String? goal) {
    if (goal == null) return 'Not set';
    return _goalOptions[goal] ?? goal;
  }

  Future<void> _editGoal(BuildContext context, Map<String, dynamic> profile) async {
    final currentGoal = (profile['goal'] as String?) ?? 'gain_strength';

    String tempSelection = currentGoal;

    final selected = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Goal'),
        content: StatefulBuilder(
          builder: (context, setLocalState) {
            return DropdownButtonFormField<String>(
              value: tempSelection,
              items: _goalOptions.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setLocalState(() => tempSelection = val);
              },
              decoration: const InputDecoration(
                labelText: 'Goal',
                border: OutlineInputBorder(),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, tempSelection),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (selected == null) return;

    setState(() => _isSavingGoal = true);

    try {
      await supabase
          .from('profiles')
          .update({'goal': selected})
          .eq('id', supabase.auth.currentUser!.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goal updated')),
      );

      // refetch in FutureBuilder
      setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingGoal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return FutureBuilder(
      // cheap way to refetch after setState()
      future: supabase.from('profiles').select().eq('id', user!.id).single(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final profile = snapshot.data as Map<String, dynamic>;
        final xp = XPUtils.totalXP(profile);
        final level = XPUtils.computeLevel(xp);
        final progress = XPUtils.levelProgress(xp);
        final rank = XPUtils.computeRank(xp);

        final goal = profile['goal'] as String?;

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

                    // -------- Goal Card --------
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.flag_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Goal",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _goalLabel(goal),
                                    style: TextStyle(
                                      color: goal == null ? Colors.grey : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed:
                                  _isSavingGoal ? null : () => _editGoal(context, profile),
                              icon: _isSavingGoal
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.edit),
                              label: const Text("Edit"),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GymListPage()),
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
