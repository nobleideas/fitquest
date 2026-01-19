import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // ✅ MUST be here

import 'auth_page.dart';
import 'pages/main_shell.dart';
import 'pages/onboarding_page.dart';
import 'pages/reset_password_page.dart';
import 'services/profile_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Web REQUIRES options; mobile uses native config
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://innhkmqtrdxpsggxutxw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlubmhrbXF0cmR4cHNnZ3h1dHh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEzMzU0MjgsImV4cCI6MjA3NjkxMTQyOH0.zdYjjpHiEW03cp_MHOuzZHXFzTKQSrdBkmugUQhscWI',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fit Quest',
      theme: ThemeData(primarySwatch: Colors.deepPurple),

      // Routes for web deep links (including Supabase recovery redirect)
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/reset-password') {
          return MaterialPageRoute(builder: (_) => const ResetPasswordPage());
        }

        // default
        return MaterialPageRoute(builder: (_) => const AuthGate());
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;

        // ---- NOT LOGGED IN ----
        if (session == null) {
          return const AuthPage();
        }

        // ---- LOGGED IN: LOAD PROFILE ----
        return FutureBuilder<Map<String, dynamic>?>(
          future: ProfileService().getProfile(session.user.id),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final profile = profileSnap.data;

            if (profile == null) return const OnboardingPage();
            if (profile['goal'] == null) return const OnboardingPage();

            return const MainShell();
          },
        );
      },
    );
  }
}
