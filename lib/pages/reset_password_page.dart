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
  bool isLoadingSession = true;

  bool showNewPassword = false;
  bool showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    _recoverSessionFromResetLink();
  }

  Future<void> _recoverSessionFromResetLink() async {
    try {
      final uri = Uri.base;
      final code = uri.queryParameters['code'];

      if (code != null && code.isNotEmpty) {
        await supabase.auth.exchangeCodeForSession(code);
      }

      final session = supabase.auth.currentSession;

      if (!mounted) return;

      setState(() {
        isLoadingSession = false;
        message = session == null
            ? "This reset link is not active. Please request a new password reset email and open the newest link."
            : null;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        isLoadingSession = false;
        message = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoadingSession = false;
        message = e.toString();
      });
    }
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

    if (supabase.auth.currentSession == null) {
      setState(() {
        message =
            "Your reset session is missing. Please request a new reset email.";
      });
      return;
    }

    setState(() {
      isSaving = true;
      message = null;
    });

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: p1),
      );

      if (!mounted) return;

      setState(() {
        message = "Password updated successfully!";
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => message = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => message = e.toString());
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
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
    final bool isSuccess =
        message?.toLowerCase().contains("success") ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Reset Password"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                const SizedBox(height: 32),

                const Text(
                  "Enter a new password for your account.",
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                if (isLoadingSession)
                  const CircularProgressIndicator()
                else ...[
                  TextField(
                    controller: newPasswordController,
                    obscureText: !showNewPassword,
                    decoration: InputDecoration(
                      labelText: "New Password",
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showNewPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            showNewPassword = !showNewPassword;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: confirmPasswordController,
                    obscureText: !showConfirmPassword,
                    decoration: InputDecoration(
                      labelText: "Confirm New Password",
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            showConfirmPassword = !showConfirmPassword;
                          });
                        },
                      ),
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
                ],

                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (_) => false,
                    );
                  },
                  child: const Text("Back to Login"),
                ),

                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSuccess ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}