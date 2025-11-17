import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'home_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://innhkmqtrdxpsggxutxw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlubmhrbXF0cmR4cHNnZ3h1dHh3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjEzMzU0MjgsImV4cCI6MjA3NjkxMTQyOH0.zdYjjpHiEW03cp_MHOuzZHXFzTKQSrdBkmugUQhscWI',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Supabase Auth Demo',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const AuthGate(),
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
        if (session == null) {
          return AuthPage(); // 👈 show login/signup
        } else {
          return HomePage(); // 👈 your main content

        }
      },
    );
  }
}
