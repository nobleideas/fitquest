import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import '../theme/fitquest_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _usernameController = TextEditingController();
  final _gymSearchController = TextEditingController();
  String _selectedGoal = 'gain_strength';
  String? _selectedGymId;
  String? _destinationGymId; // Retains a newly created gym ID if setup is retried
  List<Map<String, dynamic>> _gyms = [];
  List<Map<String, dynamic>> _availableEquipment = [];
  final Set<String> _selectedEquipmentIds = {};
  bool _isLoading = false;
  bool _loadingGyms = true;
  bool _loadingEquipment = false;
  String? _gymError;
  String? _equipmentError;

  @override
  void initState() {
    super.initState();
    _loadGyms();
  }

  Future<void> _loadGyms() async {
    try {
      // The RPC groups gyms by normalized name and chooses the source
      // with the most assigned equipment. No source records are modified.
      final rows = await Supabase.instance.client
          .rpc('onboarding_unique_gyms');
      if (!mounted) return;
      setState(() {
        _gyms = List<Map<String, dynamic>>.from(rows);
        _gymError = null;
        _loadingGyms = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gymError = 'Could not load gyms. You can still finish setup.';
        _loadingGyms = false;
      });
    }
  }

  Future<void> _chooseGym() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FitQuestTheme.surface,
      builder: (sheetContext) => Theme(
        data: FitQuestTheme.dark,
        child: StatefulBuilder(
        builder: (sheetContext, refresh) {
          final term = _gymSearchController.text.trim().toLowerCase();
          final filtered = _gyms.where((gym) =>
              (gym['name'] ?? '').toString().toLowerCase().contains(term)).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.viewInsetsOf(sheetContext).bottom + 16),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.55,
                child: Column(children: [
                  const Text('Choose a gym',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gymSearchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (_) => refresh(() {}),
                    decoration: const InputDecoration(
                        hintText: 'Search gyms', prefixIcon: Icon(Icons.search)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: ListView(children: [
                    ListTile(
                      leading: const Icon(Icons.not_interested),
                      title: const Text('No gym / Skip for now',
                          style: TextStyle(color: Colors.white)),
                      onTap: () => Navigator.pop(sheetContext, ''),
                    ),
                    ...filtered.map((gym) => ListTile(
                      leading: const Icon(Icons.business_outlined),
                      title: Text((gym['name'] ?? '').toString(),
                          style: const TextStyle(color: Colors.white)),
                      onTap: () => Navigator.pop(sheetContext, gym['id'].toString()),
                    )),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No matching gyms.'),
                      ),
                  ])),
                ]),
              ),
            ),
          );
        },
        ),
      ),
    );
    _gymSearchController.clear();
    if (!mounted || chosen == null) return;
    final gymId = chosen.isEmpty ? null : chosen;
    setState(() {
      _selectedGymId = gymId;
      _destinationGymId = null;
      _availableEquipment = [];
      _selectedEquipmentIds.clear();
      _equipmentError = null;
    });
    if (gymId != null) await _loadGymEquipment(gymId);
  }

  Future<void> _loadGymEquipment(String gymId) async {
    setState(() => _loadingEquipment = true);
    try {
      // A read-only SECURITY DEFINER RPC exposes only names/IDs in the
      // selected gym's catalog; private exercises and workout data stay private.
      final assignments = await Supabase.instance.client.rpc(
        'onboarding_gym_equipment', params: {'p_gym_id': gymId});
      final byId = <String, Map<String, dynamic>>{};
      for (final row in assignments) {
        final item = row;
        if (item is Map && item['id'] != null) {
          final record = Map<String, dynamic>.from(item);
          byId[record['id'].toString()] = record;
        }
      }
      final equipment = byId.values.toList()
        ..sort((a, b) => a['name'].toString().toLowerCase()
            .compareTo(b['name'].toString().toLowerCase()));
      if (!mounted || _selectedGymId != gymId) return;
      setState(() {
        _availableEquipment = equipment;
        _selectedEquipmentIds
          ..clear()
          ..addAll(equipment.map((e) => e['id'].toString()));
        _equipmentError = null;
        _loadingEquipment = false;
      });
    } catch (_) {
      if (!mounted || _selectedGymId != gymId) return;
      setState(() {
        _availableEquipment = [];
        _selectedEquipmentIds.clear();
        _equipmentError = 'Could not load gym equipment. Try another gym or skip.';
        _loadingEquipment = false;
      });
    }
  }

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a username')));
      return;
    }
    if (_loadingEquipment || _equipmentError != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please wait for equipment to load, or skip the gym.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final selected = _availableEquipment
          .where((e) => _selectedEquipmentIds.contains(e['id'].toString()))
          .toList();
      // A gym references profiles(id), so the profile must exist first.
      // Reuse it on retry if an earlier attempt already created it.
      final existingProfile = await client.from('profiles')
          .select('id').eq('id', user.id).maybeSingle();
      if (existingProfile == null) {
        await ProfileService().createProfile(
            userId: user.id, username: username, goal: _selectedGoal);
      }
      String? destinationId = _destinationGymId;
      final sourceGym = _gyms.firstWhere(
          (g) => g['id'].toString() == _selectedGymId,
          orElse: () => <String, dynamic>{});
      if (_selectedGymId != null && destinationId == null) {
          final created = await client.from('gyms').insert({
            'user_id': user.id,
            'name': sourceGym['name'].toString(),
          }).select('id').single();
          destinationId = created['id'].toString();
          _destinationGymId = destinationId;
        }
        if (selected.isNotEmpty && destinationId != null) {
          final inserted = await client.from('equipment').insert([
            for (final item in selected)
              {'user_id': user.id, 'name': item['name'],
               'kind': 'equipment', 'gym_id': destinationId},
          ]).select('id');
          await client.from('equipment_gyms').insert([
            for (final item in inserted)
              {'equipment_id': item['id'], 'gym_id': destinationId,
               'user_id': user.id},
          ]);
          // Copy exercises for each selected source machine into its new
          // personal equipment record. The server verifies both ownerships.
          // Original exercises and workout history are never modified.
          await client.rpc('onboarding_copy_equipment_exercises', params: {
            'p_source_gym_id': _selectedGymId,
            'p_equipment_map': [
              for (var i = 0; i < selected.length; i++)
                {
                  'source_id': selected[i]['id'].toString(),
                  'destination_id': inserted[i]['id'].toString(),
                },
            ],
          });
        }
        if (destinationId != null) {
          await client.from('profiles').update({'active_gym_id': destinationId})
              .eq('id', user.id);
        }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _gymSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: FitQuestTheme.dark,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to FitQuest'),
        automaticallyImplyLeading: false,
      ),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.fitness_center, size: 42, color: FitQuestTheme.accent),
            const SizedBox(height: 14),
            const Text('Set up your profile', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              enabled: !_isLoading,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _selectedGoal,
              dropdownColor: FitQuestTheme.surface,
              decoration: const InputDecoration(labelText: 'Your fitness goal'),
              items: const [
                DropdownMenuItem(value: 'lose_weight', child: Text('Lose Weight')),
                DropdownMenuItem(value: 'gain_mass', child: Text('Gain Mass')),
                DropdownMenuItem(value: 'gain_strength', child: Text('Gain Strength')),
              ],
              onChanged: _isLoading ? null : (value) {
                if (value != null) setState(() => _selectedGoal = value);
              },
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _isLoading || _loadingGyms || _gymError != null
                  ? null : _chooseGym,
              icon: const Icon(Icons.business_outlined),
              label: Text(_selectedGymId == null
                  ? 'Choose a gym (optional)'
                  : (_gyms.where((g) => g['id'].toString() == _selectedGymId)
                      .map((g) => g['name'].toString()).firstOrNull ?? 'Selected gym')),
              style: OutlinedButton.styleFrom(
                foregroundColor: FitQuestTheme.dark.colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              ),
            ),
            if (_loadingGyms) const Padding(
                padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            if (_gymError != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_gymError!,
                    style: const TextStyle(color: FitQuestTheme.muted))),
            if (_loadingEquipment) const Padding(
                padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_equipmentError != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_equipmentError!,
                    style: const TextStyle(color: FitQuestTheme.muted))),
            if (_selectedGymId != null && !_loadingEquipment && _equipmentError == null) ...[
              const SizedBox(height: 18),
              Row(children: [
                const Expanded(child: Text('Equipment to import',
                    style: TextStyle(fontWeight: FontWeight.bold))),
                Text('${_selectedEquipmentIds.length} / ${_availableEquipment.length}'),
              ]),
              Row(children: [
                TextButton(onPressed: _isLoading ? null : () => setState(() {
                  _selectedEquipmentIds
                    ..clear()
                    ..addAll(_availableEquipment.map((e) => e['id'].toString()));
                }), child: const Text('Select all')),
                TextButton(onPressed: _isLoading ? null : () => setState(() {
                  _selectedEquipmentIds.clear();
                }), child: const Text('Clear')),
              ]),
              if (_availableEquipment.isEmpty)
                const Text('This gym has no shared equipment yet.',
                    style: TextStyle(color: FitQuestTheme.muted)),
              ..._availableEquipment.map((item) {
                final id = item['id'].toString();
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name'].toString()),
                  value: _selectedEquipmentIds.contains(id),
                  onChanged: _isLoading ? null : (checked) => setState(() {
                    if (checked == true) {
                      _selectedEquipmentIds.add(id);
                    } else {
                      _selectedEquipmentIds.remove(id);
                    }
                  }),
                );
              }),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _isLoading || _loadingEquipment ? null : _submit,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Finish Setup'),
            ),
          ]),
        ),
      )),
    ),
  );
}
