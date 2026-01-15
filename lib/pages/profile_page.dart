import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'friend_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  bool _isSavingGoal = false;
  final _friendUsernameController = TextEditingController();
  bool _isSendingRequest = false;
  bool _isResettingStats = false;

  static const _goalOptions = <String, String>{
    'lose_weight': 'Lose Weight',
    'gain_mass': 'Gain Mass',
    'gain_strength': 'Gain Strength',
  };

  String _goalLabel(String? goal) => _goalOptions[goal] ?? (goal ?? 'Not set');

  static const double _volumePerLevel = 25000.0;

  int _computeLevel(double totalVolume) => max(1, (totalVolume / _volumePerLevel).floor() + 1);

  double _levelProgress(double totalVolume) => ((totalVolume % _volumePerLevel) / _volumePerLevel).clamp(0.0, 1.0);

  String _computeRank(int level) {
    if (level >= 40) return "Legend";
    if (level >= 25) return "Elite";
    if (level >= 15) return "Advanced";
    if (level >= 7) return "Intermediate";
    return "Beginner";
  }

  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // (everything above unchanged...)

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
        final acceptedFriends = snapshot.data!['acceptedFriends'] as List<Map<String, dynamic>>;
        final incomingRequests = snapshot.data!['incomingRequests'] as List<Map<String, dynamic>>;

        final totalVol = _numToDouble(vol['total_volume']);
        final level = _computeLevel(totalVol);
        final progress = _levelProgress(totalVol);
        final rank = _computeRank(level);

        final goal = profile['goal'] as String?;
        final username = (profile['username'] as String?)?.trim();

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

              // (profile header, goal, friends input etc remain unchanged...)

              // -------- Muscle bars --------
              const Text("Muscle Group Volume", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _volumeBar("Back", back),
              _volumeBar("Chest", chest),
              _volumeBar("Shoulders", shoulders),
              _volumeBar("Arms", arms),
              _volumeBar("Legs", legs),
              _volumeBar("Core", core),

              const SizedBox(height: 16),

              // -------- Reset Stats (moved here) --------
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _isResettingStats
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restart_alt),
                  label: const Text("Reset Stats"),
                  onPressed: _isResettingStats ? null : () => _resetStats(context),
                ),
              ),

              const SizedBox(height: 12),

              // -------- Log Out (moved here) --------
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
        );
      },
    );
  }
}
