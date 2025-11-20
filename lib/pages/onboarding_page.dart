import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/profile_service.dart';
import 'profile_page.dart'; // <-- Update path if needed

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _usernameController = TextEditingController();
  String _selectedGoal = 'gain_strength'; // default
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

    await ProfileService().createProfile(
      userId: user.id,
      username: username,
      goal: _selectedGoal,
    );

    setState(() => _isLoading = false);

    // Navigate to Profile Page
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome!"),
        automaticallyImplyLeading: false, // prevent back button
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

            // Username
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            // Goal dropdown
            const Text("Your Goal", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedGoal,
              items: const [
                DropdownMenuItem(
                    value: 'lose_weight', child: Text("Lose Weight")),
                DropdownMenuItem(
                    value: 'gain_mass', child: Text("Gain Mass")),
                DropdownMenuItem(
                    value: 'gain_strength', child: Text("Gain Strength")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedGoal = val);
                }
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 40),

            Center(
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
