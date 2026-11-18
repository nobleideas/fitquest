import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/fitquest_theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final supabase = Supabase.instance.client;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLogin = true, isLoading = false, awaitingConfirmation = false;
  bool _obscurePassword = true;
  String? errorMessage, successMessage;

  void _setError(String msg) {
    if (!mounted) return;
    setState(() { errorMessage = msg; successMessage = null; isLoading = false; });
  }
  void _setSuccess(String msg) {
    if (!mounted) return;
    setState(() { successMessage = msg; errorMessage = null; isLoading = false; });
  }
  bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(s.trim());

  Future<void> _authAction() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    setState(() {
      errorMessage = null; successMessage = null;
      awaitingConfirmation = false; isLoading = true;
    });
    if (!_looksLikeEmail(email)) { _setError('Please enter a valid email address.'); return; }
    if (password.length < 6) { _setError('Password must be at least 6 characters.'); return; }
    try {
      if (isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } else {
        final res = await supabase.auth.signUp(email: email, password: password);
        if (!mounted) return;
        if (res.session == null) {
          setState(() => awaitingConfirmation = true);
          _setSuccess('Account created! Check your email to confirm your address before logging in.');
        } else {
          _setSuccess("Account created! You're logged in.");
        }
      }
    } on AuthException catch (e) { _setError(e.message); }
    catch (e) { _setError(e.toString()); }
    finally { if (mounted) setState(() => isLoading = false); }
  }

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();
    setState(() { errorMessage = null; successMessage = null; isLoading = true; });
    if (!_looksLikeEmail(email)) {
      _setError("Enter your email above first, then tap 'Forgot Password?'."); return;
    }
    try {
      await supabase.auth.resetPasswordForEmail(email,
        redirectTo: 'https://app.fitquest.space/#/reset-password');
      _setSuccess('If an account exists for this email, we sent a password reset link.\n\n'
        'Make sure you entered the email address you originally used to sign up for Fit Quest. '
        'If you are unsure which email you used, search your email accounts for "Fit Quest" '
        'to find your original verification email.\n\nAlso check your spam or junk folder.');
    } on AuthException catch (e) { _setError(e.message); }
    catch (e) { _setError(e.toString()); }
    finally { if (mounted) setState(() => isLoading = false); }
  }

  Future<void> _resendConfirmation() async {
    final email = emailController.text.trim();
    if (!_looksLikeEmail(email)) { _setError('Enter your email above so we know where to resend.'); return; }
    setState(() { errorMessage = null; successMessage = null; isLoading = true; });
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
      _setSuccess('Confirmation email resent. Please check your inbox.');
    } on AuthException catch (e) { _setError(e.message); }
    catch (e) { _setError(e.toString()); }
    finally { if (mounted) setState(() => isLoading = false); }
  }

  void _toggleMode() => setState(() {
    isLogin = !isLogin; awaitingConfirmation = false;
    errorMessage = null; successMessage = null;
  });

  @override
  void dispose() { emailController.dispose(); passwordController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Theme(data: FitQuestTheme.dark, child:
    Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Sign Up')),
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fitness_center, size: 44, color: FitQuestTheme.accent),
            const SizedBox(height: 16),
            Text(isLogin ? 'Log in to your FitQuest account.'
                : 'Create an account. You must confirm your email before logging in.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FitQuestTheme.muted)),
            const SizedBox(height: 20),
            TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: passwordController, obscureText: _obscurePassword,
              autofillHints: [isLogin ? AutofillHints.password : AutofillHints.newPassword],
              decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: isLoading ? null : _authAction,
              child: isLoading ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                : Text(isLogin ? 'Login' : 'Create Account'))),
            const SizedBox(height: 8),
            TextButton(onPressed: isLoading ? null : _toggleMode,
              child: Text(isLogin ? 'Need an account? Sign Up' : 'Already have an account? Login')),
            TextButton(onPressed: isLoading ? null : _forgotPassword,
              child: const Text('Forgot Password?')),
            if (awaitingConfirmation) TextButton(
              onPressed: isLoading ? null : _resendConfirmation,
              child: const Text('Resend confirmation email')),
            if (successMessage != null) _message(successMessage!, const Color(0xFF86EFAC)),
            if (errorMessage != null) _message(errorMessage!, const Color(0xFFFCA5A5)),
          ]),
        ),
      )),
    ));

  Widget _message(String message, Color color) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(color: color))));
}
