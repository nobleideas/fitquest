import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _usernameController = TextEditingController();
  String _selectedGoal = 'gain_strength';
  bool _isLoading = false;

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a username")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ProfileService().createProfile(
        userId: user.id,
        username: username,
        goal: _selectedGoal,
      );

      if (!mounted) return;

      // ✅ Let AuthGate decide where to go next (it will see goal is set and go to MainShell)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Setup failed: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome!"),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Let's set up your profile",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            const Text("Your Goal", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: _selectedGoal,
              items: const [
                DropdownMenuItem(value: 'lose_weight', child: Text("Lose Weight")),
                DropdownMenuItem(value: 'gain_mass', child: Text("Gain Mass")),
                DropdownMenuItem(value: 'gain_strength', child: Text("Gain Strength")),
              ],
              onChanged: _isLoading
                  ? null
                  : (val) {
                      if (val != null) setState(() => _selectedGoal = val);
                    },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Finish Setup"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
