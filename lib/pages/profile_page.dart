import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'friend_profile_page.dart';
import '../services/exercise_service.dart';
import '../services/profile_service.dart';
import '../theme/fitquest_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

// ✅ PUBLIC state type so MainShell can use GlobalKey<ProfilePageState>
class ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final ExerciseService _exerciseService = ExerciseService();
  final ProfileService _profileService = ProfileService();

  // ✅ store the future so we can force a refetch on demand
  late Future<Map<String, dynamic>> _dataFuture;

  // Goal editing state
  bool _isSavingGoal = false;

  // Friends UI state
  final _friendUsernameController = TextEditingController();
  bool _isSendingRequest = false;

  // Reset stats UI state
  bool _isResettingStats = false;

  // Body weight UI state
  bool _isSavingWeight = false;

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

    final exerciseVideoStatsFuture = supabase
        .from('exercises')
        .select('id, video_url')
        .eq('user_id', user.id);

    final yearWorkoutStatsFuture =
        _profileService.getCurrentYearWorkoutStats();

    final bodyWeightHistoryFuture =
        _profileService.getBodyWeightHistory();

    final results = await Future.wait<dynamic>([
      profileFuture,
      volumeFuture,
      acceptedFriendsFuture,
      incomingRequestsFuture,
      exerciseVideoStatsFuture,
      yearWorkoutStatsFuture,
      bodyWeightHistoryFuture,
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

    final exercises = (results[4] is List)
        ? List<Map<String, dynamic>>.from(results[4] as List)
        : <Map<String, dynamic>>[];

    final totalExercises = exercises.length;

    final videosUploaded = exercises.where((e) {
      final videoUrl = (e['video_url'] ?? '').toString().trim();
      return videoUrl.isNotEmpty;
    }).length;

    final yearWorkoutStats = results[5] as YearWorkoutStats;
    final bodyWeightHistory =
        List<BodyWeightEntry>.from(results[6] as List);

    return {
      'profile': profile,
      'volume': volRow,
      'acceptedFriends': acceptedFriends,
      'incomingRequests': incomingRequests,
      'totalExercises': totalExercises,
      'videosUploaded': videosUploaded,
      'yearWorkoutStats': yearWorkoutStats,
      'bodyWeightHistory': bodyWeightHistory,
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

  

  String _formatWeightDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _activityLabel(String? level) {
    switch (level) {
      case 'low':
        return 'Low';
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      default:
        return 'Not recorded';
    }
  }

  String _activityDescription(String level) {
    switch (level) {
      case 'low':
        return 'Mostly sitting, driving, or resting.';
      case 'medium':
        return 'Regularly on your feet, walking, errands, or light physical work.';
      case 'high':
        return 'Physically demanding day with lots of walking, lifting, or manual work.';
      default:
        return '';
    }
  }

  Future<void> _showWeightEntryDialog({
    BodyWeightEntry? existing,
  }) async {
    final controller = TextEditingController(
      text: existing?.weightLbs.toStringAsFixed(1) ?? '',
    );
    DateTime selectedDate = existing?.date ?? DateTime.now();
    String? selectedActivity = existing?.activityLevel;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: Text(existing == null ? 'Log daily metrics' : 'Edit daily metrics'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight (lbs)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Daily activity excluding workouts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Do not count your FitQuest workout here.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'low',
                        label: Text('Low'),
                      ),
                      ButtonSegment<String>(
                        value: 'medium',
                        label: Text('Medium'),
                      ),
                      ButtonSegment<String>(
                        value: 'high',
                        label: Text('High'),
                      ),
                    ],
                    selected: selectedActivity == null
                        ? <String>{}
                        : <String>{selectedActivity!},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (selection) {
                      setLocalState(() {
                        selectedActivity = selection.isEmpty
                            ? null
                            : selection.first;
                      });
                    },
                  ),
                  if (selectedActivity != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _activityDescription(selectedActivity!),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (existing == null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setLocalState(() => selectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(_formatWeightDate(selectedDate)),
                    )
                  else
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(_formatWeightDate(selectedDate)),
                      ],
                    ),
                  if (existing == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Choose an earlier date to add or correct a previous day.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (shouldSave != true) {
      controller.dispose();
      return;
    }

    final parsedWeight = double.tryParse(controller.text.trim());
    controller.dispose();

    if (parsedWeight == null || parsedWeight <= 20 || parsedWeight >= 2000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight in pounds.')),
      );
      return;
    }

    if (selectedActivity == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose Low, Medium, or High daily activity.'),
        ),
      );
      return;
    }

    setState(() => _isSavingWeight = true);

    try {
      await _profileService.saveBodyWeight(
        date: selectedDate,
        weightLbs: parsedWeight,
        activityLevel: selectedActivity!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Daily metrics saved' : 'Daily metrics updated',
          ),
        ),
      );
      refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Daily metrics save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingWeight = false);
    }
  }

  Future<void> _showWeightHistory(List<BodyWeightEntry> entries) async {
    if (entries.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final newestFirst = entries.reversed.toList();

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.monitor_weight_outlined),
                      SizedBox(width: 8),
                      Text(
                        'Weight & activity history',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: newestFirst.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = newestFirst[index];
                      return ListTile(
                        title: Text('${entry.weightLbs.toStringAsFixed(1)} lbs'),
                        subtitle: Text(
                          '${_formatWeightDate(entry.date)} • '
                          '${_activityLabel(entry.activityLevel)} activity',
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Future.microtask(
                              () => _showWeightEntryDialog(existing: entry),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bodyWeightCard(List<BodyWeightEntry> entries) {
    final chartEntries = entries.length > 30
        ? entries.sublist(entries.length - 30)
        : entries;
    final latest = entries.isEmpty ? null : entries.last;
    final previous = entries.length >= 2 ? entries[entries.length - 2] : null;
    final delta = latest != null && previous != null
        ? latest.weightLbs - previous.weightLbs
        : null;

    String deltaLabel = '';
    if (delta != null) {
      if (delta.abs() < 0.05) {
        deltaLabel = 'No change from previous entry';
      } else {
        final prefix = delta > 0 ? '+' : '';
        deltaLabel = '$prefix${delta.toStringAsFixed(1)} lbs from previous entry';
      }
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_weight_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Body Weight & Daily Activity',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_isSavingWeight)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (latest == null) ...[
              Text(
                'No daily metrics recorded yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    latest.weightLbs.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 5, bottom: 4),
                    child: Text(
                      'lbs',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatWeightDate(latest.date),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.directions_walk_outlined, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    '${_activityLabel(latest.activityLevel)} activity',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '(excluding workouts)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (deltaLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  deltaLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 118,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WeightChartPainter(
                    entries: chartEntries,
                    lineColor: Theme.of(context).colorScheme.primary,
                    gridColor: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _formatWeightDate(chartEntries.first.date),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatWeightDate(chartEntries.last.date),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSavingWeight
                        ? null
                        : () => _showWeightEntryDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Log today'),
                  ),
                ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSavingWeight
                          ? null
                          : () => _showWeightHistory(entries),
                      icon: const Icon(Icons.history),
                      label: const Text('History'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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


  List<String> _splitStatLabels(String value) {
    return value
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != '—')
        .toList();
  }

  Widget _compactStat({
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bestPeriodSection({
    required String label,
    required int workoutDays,
    required String rawLabels,
  }) {
    final labels = _splitStatLabels(rawLabels);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: labels.isEmpty
              ? const Text('—')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$workoutDays workout day${workoutDays == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...labels.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _trainingStatsCard(YearWorkoutStats stats) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${stats.year} Training',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _compactStat(
                  label: 'Workout days',
                  value: '${stats.workoutDays}',
                ),
                Container(
                  width: 1,
                  height: 42,
                  color: Theme.of(context).dividerColor,
                ),
                _compactStat(
                  label: 'Estimated hours',
                  value: stats.estimatedWorkoutHours.toStringAsFixed(1),
                ),
              ],
            ),
            const Divider(height: 26),
            _bestPeriodSection(
              label: 'Best month',
              workoutDays: stats.bestMonthWorkoutDays,
              rawLabels: stats.bestMonthLabel,
            ),
            const SizedBox(height: 14),
            _bestPeriodSection(
              label: 'Best week',
              workoutDays: stats.bestWeekWorkoutDays,
              rawLabels: stats.bestWeekLabel,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _friendUsernameController.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(child: Text(title, style: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800,
        ))),
      ]),
    );
  }

  Widget _surfaceCard(Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _profileHero({
    required String rank,
    required String? username,
    required int level,
    required double progress,
    required double totalVolume,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary.withValues(alpha: 0.22),
            colors.surfaceContainerHighest],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOUR FITQUEST PROFILE', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6,
          color: colors.primary,
        )),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.military_tech_outlined, size: 30, color: colors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rank, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            if (username != null && username.isNotEmpty)
              Text('@$username', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant)),
          ])),
          Text('LVL $level', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900, color: colors.primary)),
        ]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Level progress', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('${(progress * 100).round()}%', style: TextStyle(
            fontSize: 12, color: colors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(
          value: progress, minHeight: 9,
          backgroundColor: colors.onSurface.withValues(alpha: 0.10),
        )),
        const SizedBox(height: 13),
        Text('Total training volume  •  ${totalVolume.toStringAsFixed(0)} lbs',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]),
    );
  }

  Widget _friendsCard(
    List<Map<String, dynamic>> acceptedFriends,
    List<Map<String, dynamic>> incomingRequests,
  ) {
    final colors = Theme.of(context).colorScheme;
    return _surfaceCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Friends', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w800))),
        Text('${acceptedFriends.length} connected', style: TextStyle(
          fontSize: 12, color: colors.onSurfaceVariant)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _friendUsernameController,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          labelText: 'Add by username',
          hintText: 'Enter username',
          isDense: true,
          prefixIcon: const Icon(Icons.person_search_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: IconButton(
            tooltip: 'Send friend request',
            icon: _isSendingRequest
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.person_add_alt_1_outlined),
            onPressed: _isSendingRequest ? null : () => _sendFriendRequest(context),
          ),
        ),
        onSubmitted: (_) {
          if (!_isSendingRequest) _sendFriendRequest(context);
        },
      ),
      if (incomingRequests.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('REQUESTS (${incomingRequests.length})', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1,
          color: colors.primary)),
        const SizedBox(height: 6),
        ...incomingRequests.map((r) {
          final reqId = (r['request_id'] ?? '').toString();
          final fromUsername = (r['from_username'] ?? 'Unknown').toString();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.person_outline),
            title: Text(fromUsername, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Wants to connect'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Decline', icon: const Icon(Icons.close),
                onPressed: () => _respondToRequest(context, reqId, 'declined')),
              IconButton(tooltip: 'Accept', icon: const Icon(Icons.check_circle_outline),
                color: colors.primary,
                onPressed: () => _respondToRequest(context, reqId, 'accepted')),
            ]),
          );
        }),
      ],
      const SizedBox(height: 15),
      Row(children: [
        const Expanded(child: Text('YOUR FRIENDS', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
        if (acceptedFriends.length > 4)
          Text('Scroll to browse', style: TextStyle(
            fontSize: 11, color: colors.onSurfaceVariant)),
      ]),
      const SizedBox(height: 7),
      if (acceptedFriends.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('No friends yet. Add someone above to connect.',
            style: TextStyle(color: colors.onSurfaceVariant)))
      else
        SizedBox(
          height: acceptedFriends.length <= 4
              ? acceptedFriends.length * 58.0
              : 232,
          child: Scrollbar(
            thumbVisibility: acceptedFriends.length > 4,
            child: ListView.builder(
              primary: false,
              physics: const ClampingScrollPhysics(),
              itemCount: acceptedFriends.length,
              itemBuilder: (context, index) {
                final friend = acceptedFriends[index];
                final name = (friend['username'] ?? 'Friend').toString();
                return SizedBox(height: 58, child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundColor: colors.primary.withValues(alpha: 0.14),
                    child: Icon(Icons.person_outline, size: 19, color: colors.primary),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right, size: 19),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FriendProfilePage(
                      friendUserId: friend['friend_id'].toString(),
                      friendUsername: (friend['username'] ?? '').toString(),
                    ),
                  )),
                ));
              },
            ),
          ),
        ),
    ]));
  }

  Widget _muscleVolumeCard(Map<String, double> volumes) {
    final colors = Theme.of(context).colorScheme;
    final maxVolume = volumes.values.fold<double>(0, (a, b) => max(a, b));
    return _surfaceCard(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Total volume by muscle group', style: TextStyle(
        fontSize: 12, color: colors.onSurfaceVariant)),
      const SizedBox(height: 14),
      ...volumes.entries.map((entry) => Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(entry.key, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700))),
            Text('${entry.value.toStringAsFixed(0)} lbs', style: TextStyle(
              fontSize: 12, color: colors.onSurfaceVariant)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: maxVolume <= 0 ? 0 : (entry.value / maxVolume).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: colors.onSurface.withValues(alpha: 0.09),
            )),
        ]),
      )),
      Text('Bars compare your muscle groups to your highest-volume group.',
        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: FitQuestTheme.dark,
      child: Builder(builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 34),
                const SizedBox(height: 12),
                const Text('Unable to load your profile.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: refresh,
                  icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]),
            ));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final profile = data['profile'] as Map<String, dynamic>;
          final vol = data['volume'] as Map<String, dynamic>;
          final acceptedFriends = data['acceptedFriends'] as List<Map<String, dynamic>>;
          final incomingRequests = data['incomingRequests'] as List<Map<String, dynamic>>;
          final totalExercises = data['totalExercises'] as int;
          final videosUploaded = data['videosUploaded'] as int;
          final yearWorkoutStats = data['yearWorkoutStats'] as YearWorkoutStats;
          final bodyWeightHistory = data['bodyWeightHistory'] as List<BodyWeightEntry>;
          final totalVol = _numToDouble(vol['total_volume']);
          final level = _computeLevel(totalVol);
          final goal = profile['goal'] as String?;
          final username = (profile['username'] as String?)?.trim();

          return RefreshIndicator(
            onRefresh: () async {
              final next = _loadData();
              setState(() => _dataFuture = next);
              await next;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              children: [
                _profileHero(rank: _computeRank(level), username: username,
                  level: level, progress: _levelProgress(totalVol),
                  totalVolume: totalVol),
                const SizedBox(height: 22),
                _sectionTitle('Body & activity', Icons.monitor_weight_outlined),
                _bodyWeightCard(bodyWeightHistory),
                const SizedBox(height: 22),
                _sectionTitle('Training overview', Icons.insights_outlined),
                _trainingStatsCard(yearWorkoutStats),
                const SizedBox(height: 22),
                _sectionTitle('My goals & videos', Icons.flag_outlined),
                _surfaceCard(Column(children: [
                  Row(children: [
                    const Icon(Icons.flag_outlined, size: 20),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fitness goal', style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(_goalLabel(goal)),
                      ])),
                    TextButton.icon(
                      onPressed: _isSavingGoal ? null : () => _editGoal(context, profile),
                      icon: _isSavingGoal
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Edit'),
                    ),
                  ]),
                  const Divider(height: 28),
                  Row(children: [
                    const Icon(Icons.video_library_outlined, size: 20),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Exercise videos', style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('$videosUploaded of $totalExercises exercises have videos'),
                      ])),
                  ]),
                ])),
                const SizedBox(height: 22),
                _sectionTitle('Community', Icons.people_outline),
                _friendsCard(acceptedFriends, incomingRequests),
                const SizedBox(height: 22),
                _sectionTitle('Muscle group volume', Icons.bar_chart_outlined),
                _muscleVolumeCard({
                  'Back': _numToDouble(vol['volume_back']),
                  'Chest': _numToDouble(vol['volume_chest']),
                  'Shoulders': _numToDouble(vol['volume_shoulders']),
                  'Arms': _numToDouble(vol['volume_arms']),
                  'Legs': _numToDouble(vol['volume_legs']),
                  'Core': _numToDouble(vol['volume_core']),
                }),
                const SizedBox(height: 26),
                _sectionTitle('Account', Icons.settings_outlined),
                OutlinedButton.icon(
                  icon: _isResettingStats
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.restart_alt),
                  label: const Text('Reset Stats'),
                  onPressed: _isResettingStats ? null : () => _resetStats(context),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Out'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () async => supabase.auth.signOut(),
                ),
              ],
            ),
          );
        },
      )),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<BodyWeightEntry> entries;
  final Color lineColor;
  final Color gridColor;

  const _WeightChartPainter({
    required this.entries,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    const leftPadding = 4.0;
    const rightPadding = 4.0;
    const topPadding = 8.0;
    const bottomPadding = 8.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final weights = entries.map((entry) => entry.weightLbs).toList();
    double minWeight = weights.reduce(min);
    double maxWeight = weights.reduce(max);

    if ((maxWeight - minWeight).abs() < 0.1) {
      minWeight -= 1;
      maxWeight += 1;
    } else {
      final padding = (maxWeight - minWeight) * 0.15;
      minWeight -= padding;
      maxWeight += padding;
    }

    final firstDate = entries.first.date;
    final lastDate = entries.last.date;
    final totalDays = max(1, lastDate.difference(firstDate).inDays);

    final gridPaint = Paint()
      ..color = gridColor.withOpacity(0.45)
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = topPadding + (chartHeight * i / 3);
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    Offset pointFor(BodyWeightEntry entry) {
      final dayOffset = entry.date.difference(firstDate).inDays;
      final x = leftPadding + (dayOffset / totalDays) * chartWidth;
      final normalized =
          (entry.weightLbs - minWeight) / (maxWeight - minWeight);
      final y = topPadding + chartHeight - (normalized * chartHeight);
      return Offset(x, y);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    if (entries.length == 1) {
      canvas.drawCircle(pointFor(entries.first), 4, pointPaint);
      return;
    }

    final path = Path();
    for (var i = 0; i < entries.length; i++) {
      final point = pointFor(entries[i]);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(path, linePaint);

    for (final entry in entries) {
      canvas.drawCircle(pointFor(entry), 3.2, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}
