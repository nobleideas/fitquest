import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'friend_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

// ✅ PUBLIC state type so MainShell can use GlobalKey<ProfilePageState>
class ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  // ✅ store the future so we can force a refetch on demand
  late Future<Map<String, dynamic>> _dataFuture;

  // Goal editing state
  bool _isSavingGoal = false;

  // Friends UI state
  final _friendUsernameController = TextEditingController();
  bool _isSendingRequest = false;

  // Reset stats UI state
  bool _isResettingStats = false;

  static const _goalOptions = <String, String>{
    'lose_weight': 'Lose Weight',
    'gain_mass': 'Gain Mass',
    'gain_strength': 'Gain Strength',
  };

  String _goalLabel(String? goal) => _goalOptions[goal] ?? (goal ?? 'Not set');

  // ---- Level math based on total volume (weight * reps) ----
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

  double _numToDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  // ✅ called by MainShell when Profile tab is tapped
  void refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final user = supabase.auth.currentUser!;

    final profileFuture = supabase
        .from('profiles')
        .select('id, username, goal, reset_at')
        .eq('id', user.id)
        .single();

    final volumeFuture = supabase.rpc('get_training_volume_summary');

    final acceptedFriendsFuture = supabase.rpc('get_accepted_friends');
    final incomingRequestsFuture = supabase.rpc('get_incoming_friend_requests');

    final results = await Future.wait<dynamic>([
      profileFuture,
      volumeFuture,
      acceptedFriendsFuture,
      incomingRequestsFuture,
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

    final acceptedFriends = (results[2] is List)
        ? List<Map<String, dynamic>>.from(results[2] as List)
        : <Map<String, dynamic>>[];

    final incomingRequests = (results[3] is List)
        ? List<Map<String, dynamic>>.from(results[3] as List)
        : <Map<String, dynamic>>[];

    return {
      'profile': profile,
      'volume': volRow,
      'acceptedFriends': acceptedFriends,
      'incomingRequests': incomingRequests,
    };
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
      await supabase
          .from('profiles')
          .update({'goal': selected})
          .eq('id', supabase.auth.currentUser!.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goal updated')));
      refresh(); // ✅ refetch
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _isSavingGoal = false);
    }
  }

  Future<void> _resetStats(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset stats?"),
        content: const Text(
          "This will reset your Level/Rank/Volume stats back to zero.\n\n"
          "Your workout history will NOT be deleted — it just won’t count toward stats anymore.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Reset")),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isResettingStats = true);

    try {
      await supabase
          .from('profiles')
          .update({'reset_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', supabase.auth.currentUser!.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stats reset")));
      refresh(); // ✅ refetch
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Reset failed: $e")));
    } finally {
      if (mounted) setState(() => _isResettingStats = false);
    }
  }

  Future<void> _sendFriendRequest(BuildContext context) async {
    final username = _friendUsernameController.text.trim();
    if (username.isEmpty) return;

    setState(() => _isSendingRequest = true);

    try {
      await supabase.rpc('send_friend_request_by_username', params: {
        'friend_username': username,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friend request sent to $username")),
      );
      _friendUsernameController.clear();
      refresh(); // ✅ refetch
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Send failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSendingRequest = false);
    }
  }

  Future<void> _respondToRequest(BuildContext context, String requestId, String newStatus) async {
    try {
      await supabase.rpc('respond_to_friend_request', params: {
        'req_id': requestId,
        'new_status': newStatus,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newStatus == 'accepted' ? "Request accepted" : "Request declined")),
      );
      refresh(); // ✅ refetch
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Action failed: $e")),
      );
    }
  }

  Widget _volumeBar(String label, double volume) {
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
  void dispose() {
    _friendUsernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _dataFuture, // ✅ uses stored future
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
              Center(
                child: Column(
                  children: [
                    Text(rank, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    if (username != null && username.isNotEmpty)
                      Text(
                        "@$username",
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),

                    const SizedBox(height: 6),
                    Text("Level $level", style: const TextStyle(fontSize: 22, color: Colors.grey)),
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
                                  const Text("Goal", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Text(_goalLabel(goal)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: _isSavingGoal ? null : () => _editGoal(context, profile),
                              icon: _isSavingGoal
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.edit),
                              label: const Text("Edit"),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // -------- Friends: Add by username --------
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Friends", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _friendUsernameController,
                              decoration: InputDecoration(
                                labelText: "Add friend by username",
                                hintText: "e.g. john123",
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: _isSendingRequest
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.person_add),
                                  onPressed: _isSendingRequest ? null : () => _sendFriendRequest(context),
                                ),
                              ),
                              onSubmitted: (_) => _isSendingRequest ? null : _sendFriendRequest(context),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // -------- Incoming friend requests --------
              if (incomingRequests.isNotEmpty) ...[
                const Text("Friend Requests", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...incomingRequests.map((r) {
                  final reqId = (r['request_id'] ?? '').toString();
                  final fromUsername = (r['from_username'] ?? 'Unknown').toString();

                  return Card(
                    child: ListTile(
                      title: Text(fromUsername),
                      subtitle: const Text("Wants to add you"),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => _respondToRequest(context, reqId, 'declined'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: () => _respondToRequest(context, reqId, 'accepted'),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],

              // -------- Accepted friends --------
              const Text("Friends", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (acceptedFriends.isEmpty)
                const Text("No friends yet. Add someone by username above.")
              else
                ...acceptedFriends.map((f) {
                  final uname = (f['username'] ?? 'Friend').toString();
                  return Card(
                    child: ListTile(
                      title: Text(uname),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FriendProfilePage(
                              friendUserId: f['friend_id'].toString(),
                              friendUsername: (f['username'] ?? '').toString(),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),

              const SizedBox(height: 20),

              // -------- Muscle bars --------
              const Text("Muscle Group Volume", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _volumeBar("Back", back),
              _volumeBar("Chest", chest),
              _volumeBar("Shoulders", shoulders),
              _volumeBar("Arms", arms),
              _volumeBar("Legs", legs),
              _volumeBar("Core", core),

              // Reset Stats after stats
              const SizedBox(height: 8),
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

              // Log Out after Reset Stats
              const SizedBox(height: 12),
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
