import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final supabase = Supabase.instance.client;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool awaitingConfirmation = false;

  String? errorMessage;
  String? successMessage;

  void _setError(String msg) {
    setState(() {
      errorMessage = msg;
      successMessage = null;
      isLoading = false;
    });
  }

  void _setSuccess(String msg) {
    setState(() {
      successMessage = msg;
      errorMessage = null;
      isLoading = false;
    });
  }

  bool _looksLikeEmail(String s) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(s.trim());
  }

  Future<void> _authAction() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    setState(() {
      errorMessage = null;
      successMessage = null;
      awaitingConfirmation = false;
      isLoading = true;
    });

    if (!_looksLikeEmail(email)) {
      _setError("Please enter a valid email address.");
      return;
    }

    if (password.length < 6) {
      _setError("Password must be at least 6 characters.");
      return;
    }

    try {
      if (isLogin) {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        // AuthGate handles navigation
      } else {
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (res.session == null) {
          setState(() {
            awaitingConfirmation = true;
          });
          _setSuccess(
            "Account created! Check your email to confirm your address before logging in.",
          );
        } else {
          _setSuccess("Account created! You're logged in.");
        }
      }
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = emailController.text.trim();

    setState(() {
      errorMessage = null;
      successMessage = null;
      isLoading = true;
    });

    if (!_looksLikeEmail(email)) {
      _setError("Enter your email above first, then tap 'Forgot Password?'.");
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://supabase-auth-sigma.vercel.app/#/reset-password',
      );
      _setSuccess("Check your email for a password reset link.");
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = emailController.text.trim();

    if (!_looksLikeEmail(email)) {
      _setError("Enter your email above so we know where to resend.");
      return;
    }

    setState(() {
      errorMessage = null;
      successMessage = null;
      isLoading = true;
    });

    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      _setSuccess("Confirmation email resent. Please check your inbox.");
    } on AuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      isLogin = !isLogin;
      awaitingConfirmation = false;
      errorMessage = null;
      successMessage = null;
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = isLogin ? 'Login' : 'Sign Up';
    final primaryText = isLogin ? 'Login' : 'Create Account';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLogin
                      ? "Log in to your Fit Quest account."
                      : "Create an account. You must confirm your email before logging in.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _authAction,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(primaryText),
                  ),
                ),

                const SizedBox(height: 8),

                TextButton(
                  onPressed: isLoading ? null : _toggleMode,
                  child: Text(
                    isLogin
                        ? 'Need an account? Sign Up'
                        : 'Already have an account? Login',
                  ),
                ),

                TextButton(
                  onPressed: isLoading ? null : _forgotPassword,
                  child: const Text('Forgot Password?'),
                ),

                if (awaitingConfirmation)
                  TextButton(
                    onPressed: isLoading ? null : _resendConfirmation,
                    child: const Text('Resend confirmation email'),
                  ),

                if (successMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(successMessage!, style: const TextStyle(color: Colors.green)),
                  ),
                ],

                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
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
