import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/fitquest_theme.dart';

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
  bool isSaving = false, isLoadingSession = true;
  bool showNewPassword = false, showConfirmPassword = false;
  bool _success = false;

  @override
  void initState() { super.initState(); _recoverSessionFromResetLink(); }

  Future<void> _recoverSessionFromResetLink() async {
    try {
      final code = Uri.base.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        await supabase.auth.exchangeCodeForSession(code);
      }
      final session = supabase.auth.currentSession;
      if (!mounted) return;
      setState(() {
        isLoadingSession = false;
        message = session == null
            ? 'This reset link is not active. Please request a new password reset email and open the newest link.'
            : null;
      });
    } on AuthException catch (e) {
      if (mounted) setState(() { isLoadingSession = false; message = e.message; });
    } catch (e) {
      if (mounted) setState(() { isLoadingSession = false; message = e.toString(); });
    }
  }

  Future<void> _setNewPassword() async {
    final p1 = newPasswordController.text;
    final p2 = confirmPasswordController.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => message = 'Please enter and confirm your new password.'); return;
    }
    if (p1 != p2) { setState(() => message = 'Passwords do not match.'); return; }
    if (p1.length < 6) {
      setState(() => message = 'Password must be at least 6 characters.'); return;
    }
    if (supabase.auth.currentSession == null) {
      setState(() => message = 'Your reset session is missing. Please request a new reset email.'); return;
    }
    setState(() { isSaving = true; message = null; _success = false; });
    try {
      await supabase.auth.updateUser(UserAttributes(password: p1));
      if (!mounted) return;
      setState(() { message = 'Password updated successfully!'; _success = true; });
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally { if (mounted) setState(() => isSaving = false); }
  }

  @override
  void dispose() {
    newPasswordController.dispose(); confirmPasswordController.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(data: FitQuestTheme.dark, child:
    Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(children: [
            const SizedBox(height: 32),
            const Icon(Icons.lock_reset, size: 44, color: FitQuestTheme.accent),
            const SizedBox(height: 16),
            const Text('Enter a new password for your account.',
              style: TextStyle(fontSize: 16, color: FitQuestTheme.muted),
              textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (isLoadingSession) const CircularProgressIndicator() else ...[
              TextField(controller: newPasswordController,
                obscureText: !showNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(showNewPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => showNewPassword = !showNewPassword)))),
              const SizedBox(height: 12),
              TextField(controller: confirmPasswordController,
                obscureText: !showConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: 'Confirm New Password',
                  suffixIcon: IconButton(
                    icon: Icon(showConfirmPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => showConfirmPassword = !showConfirmPassword)))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: isSaving || _success || supabase.auth.currentSession == null
                    ? null : _setNewPassword,
                child: isSaving ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save New Password'))),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.of(context)
              .pushNamedAndRemoveUntil('/', (_) => false),
              child: const Text('Back to Login')),
            if (message != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(message!, textAlign: TextAlign.center,
                style: TextStyle(color: _success
                    ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)))),
          ]),
        )),
      ),
    ));
}
