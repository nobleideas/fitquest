import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final supabase = Supabase.instance.client;

  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String? message;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    // After the user clicks the email link, Supabase will redirect here and
    // the web client should have a recovery session available.
    // We'll show a helpful message if not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = supabase.auth.currentSession;
      if (session == null) {
        setState(() {
          message =
              "This reset link is not active in this browser session. Please open the newest reset email link again.";
        });
      }
    });
  }

  Future<void> _setNewPassword() async {
    final p1 = newPasswordController.text.trim();
    final p2 = confirmPasswordController.text.trim();

    if (p1.isEmpty || p2.isEmpty) {
      setState(() => message = "Please enter and confirm your new password.");
      return;
    }
    if (p1 != p2) {
      setState(() => message = "Passwords do not match.");
      return;
    }
    if (p1.length < 6) {
      setState(() => message = "Password must be at least 6 characters.");
      return;
    }

    setState(() {
      isSaving = true;
      message = null;
    });

    try {
      // This updates the password for the currently recovered session.
      await supabase.auth.updateUser(UserAttributes(password: p1));

      if (!mounted) return;
      setState(() {
        message = "Password updated! You can go back and log in.";
      });

      // Optional: send them back to the normal auth flow
      // Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => message = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Enter a new password for your account.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirm New Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : _setNewPassword,
                child: isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save New Password"),
              ),
            ),

            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
              },
              child: const Text("Back to Login"),
            ),

            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: TextStyle(
                  color: message!.toLowerCase().contains("updated")
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
