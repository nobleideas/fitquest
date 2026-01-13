import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gym_list_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  // Goal editing state (dropdown)
  bool _isSavingGoal = false;

  static const _goalOptions = <String, String>{
    'lose_weight': 'Lose Weight',
    'gain_mass': 'Gain Mass',
    'gain_strength': 'Gain Strength',
  };

  String _goalLabel(String? goal) => _goalOptions[goal] ?? (goal ?? 'Not set');

  // ---- Level math based on total volume (weight * reps) ----
  // Tune this later. Pick something that feels good with real data.
  static const double _volumePerLevel = 25000.0;

  int _computeLevel(double totalVolume) {
    return max(1, (totalVolume / _volumePerLevel).floor() + 1);
  }

  double _levelProgress(double totalVolume) {
    final mod = totalVolume % _volumePerLevel;
    return (mod / _volumePerLevel).clamp(0.0, 1.0);
  }

  String _computeRank(int level) {
    if (level >= 40) return "Legend";
    if (level >= 25) return "Elite";
    if (level >= 15) return "Advanced";
    if (level >= 7) return "Intermediate";
    return "Beginner";
  }

  Future<Map<String, dynamic>> _loadData() async {
  final user = supabase.auth.currentUser!;

  final Future<dynamic> profileFuture =
      supabase.from('profiles').select().eq('id', user.id).single();

  final Future<dynamic> volumeFuture =
      supabase.rpc('get_training_volume_summary');

  final List<dynamic> results = await Future.wait<dynamic>([
    profileFuture,
    volumeFuture,
  ]);

  final profile = Map<String, dynamic>.from(results[0] as Map);

  final volRaw = results[1];
  Map<String, dynamic> volRow;

  if (volRaw is List && volRaw.isNotEmpty) {
    volRow = Map<String, dynamic>.from(volRaw.first as Map);
  } else if (volRaw is Map) {
    volRow = Map<String, dynamic>.from(volRaw);
  } else {
    volRow = {};
  }

  return {
    'profile': profile,
    'volume': volRow,
  };
}


  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
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
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
      await supabase.from('profiles').update({'goal': selected}).eq('id', supabase.auth.currentUser!.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goal updated')));

      setState(() {}); // refetch
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _isSavingGoal = false);
    }
  }

  Widget _volumeBar(String label, double volume) {
    // A per-muscle "target" for the progress bar. Tune later.
    const double target = 25000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label — ${volume.toStringAsFixed(0)} total lbs', style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: (volume / target).clamp(0.0, 1.0),
          minHeight: 10,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final profile = snapshot.data!['profile'] as Map<String, dynamic>;
        final vol = snapshot.data!['volume'] as Map<String, dynamic>;

        final totalVol = _numToDouble(vol['total_volume']);
        final level = _computeLevel(totalVol);
        final progress = _levelProgress(totalVol);
        final rank = _computeRank(level);

        final goal = profile['goal'] as String?;

        final back = _numToDouble(vol['volume_back']);
        final chest = _numToDouble(vol['volume_chest']);
        final shoulders = _numToDouble(vol['volume_shoulders']);
        final arms = _numToDouble(vol['volume_arms']);
        final legs = _numToDouble(vol['volume_legs']);
        final core = _numToDouble(vol['volume_core']);

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
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 10),
                    Text(
                      "Total Volume: ${totalVol.toStringAsFixed(0)} lbs",
                      style: const TextStyle(color: Colors.grey),
                    ),

                    // -------- Goal Card --------
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_goalLabel(goal)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: _isSavingGoal ? null : () => _editGoal(context, profile),
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
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const GymListPage()));
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
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () async {
                          await supabase.auth.signOut();
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              const Text(
                "Muscle Group Volume",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              _volumeBar("Back", back),
              _volumeBar("Chest", chest),
              _volumeBar("Shoulders", shoulders),
              _volumeBar("Arms", arms),
              _volumeBar("Legs", legs),
              _volumeBar("Core", core),
            ],
          ),
        );
      },
    );
  }
}
