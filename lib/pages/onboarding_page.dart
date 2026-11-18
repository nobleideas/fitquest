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
  List<Map<String, dynamic>> _gyms = [];
  bool _isLoading = false;
  bool _loadingGyms = true;
  String? _gymError;

  @override
  void initState() {
    super.initState();
    _loadParticipatingGyms();
  }

  Future<void> _loadParticipatingGyms() async {
    try {
      final rows = await Supabase.instance.client
          .from('participating_gyms')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _gyms = List<Map<String, dynamic>>.from(rows);
        _gymError = null;
        _loadingGyms = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _gymError = 'Could not load participating gyms. You can still finish setup.';
        _loadingGyms = false;
      });
    }
  }

  Future<void> _chooseGym() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FitQuestTheme.surface,
      builder: (sheetContext) => StatefulBuilder(
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
                  const Text('Choose a participating gym',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _gymSearchController,
                    autofocus: true,
                    onChanged: (_) => refresh(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search gyms', prefixIcon: Icon(Icons.search)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: ListView(children: [
                    ListTile(
                      leading: const Icon(Icons.not_interested),
                      title: const Text('No gym / Skip for now'),
                      onTap: () => Navigator.pop(sheetContext, ''),
                    ),
                    ...filtered.map((gym) => ListTile(
                      leading: const Icon(Icons.business_outlined),
                      title: Text((gym['name'] ?? '').toString()),
                      onTap: () => Navigator.pop(sheetContext, gym['id'].toString()),
                    )),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No matching participating gyms.'),
                      ),
                  ])),
                ]),
              ),
            ),
          );
        },
      ),
    );
    _gymSearchController.clear();
    if (!mounted || chosen == null) return;
    setState(() => _selectedGymId = chosen.isEmpty ? null : chosen);
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
    setState(() => _isLoading = true);
    try {
      await ProfileService().createProfile(
        userId: user.id, username: username, goal: _selectedGoal);

      // Membership is optional. If the request fails, onboarding still succeeds.
      if (_selectedGymId != null) {
        try {
          await Supabase.instance.client.from('gym_memberships').insert({
            'gym_id': _selectedGymId,
            'user_id': user.id,
            'status': 'pending',
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Profile saved, but gym request failed: $e')));
          }
        }
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
  Widget build(BuildContext context) => Theme(data: FitQuestTheme.dark, child:
    Scaffold(
      appBar: AppBar(title: const Text('Welcome to FitQuest'), automaticallyImplyLeading: false),
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
            TextField(controller: _usernameController, enabled: !_isLoading,
              decoration: const InputDecoration(labelText: 'Username')),
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
              onPressed: _isLoading || _loadingGyms || _gymError != null ? null : _chooseGym,
              icon: const Icon(Icons.business_outlined),
              label: Text(_selectedGymId == null
                  ? 'Choose a participating gym (optional)'
                  : (_gyms.where((g) => g['id'].toString() == _selectedGymId)
                      .map((g) => g['name'].toString()).firstOrNull ?? 'Selected gym')),
              style: OutlinedButton.styleFrom(
                foregroundColor: FitQuestTheme.dark.colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12)),
            ),
            if (_loadingGyms) const Padding(padding: EdgeInsets.all(8),
              child: LinearProgressIndicator()),
            if (_gymError != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_gymError!, style: const TextStyle(color: FitQuestTheme.muted))),
            const Padding(padding: EdgeInsets.only(top: 8),
              child: Text('Gym membership requests require gym approval. You can join later.',
                style: TextStyle(color: FitQuestTheme.muted, fontSize: 12))),
            const SizedBox(height: 28),
            ElevatedButton(onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Finish Setup')),
          ]),
        ),
      )),
    ));
}
