import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  final _supabase = Supabase.instance.client;

  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  /// Call ONCE (e.g., in MainShell.initState()).
  Future<void> initAndRegister() async {
    if (_initialized) return;
    _initialized = true;

    // Re-register whenever auth changes (login/logout/refresh)
    _authSub = _supabase.auth.onAuthStateChange.listen((event) async {
      final session = event.session;
      if (session == null) return; // logged out => do nothing
      await registerCurrentToken();
    });

    // Also try once immediately if already logged in
    if (_supabase.auth.currentSession != null) {
      await registerCurrentToken();
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
    _initialized = false;
  }

  Future<void> registerCurrentToken() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 1) Ask permission (web + mobile)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!allowed) {
      // user denied notifications
      return;
    }

    // 2) Get FCM token
    // ✅ Web requires a VAPID key (see step 3). If missing, token will be null.
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: const String.fromEnvironment('FIREBASE_VAPID_KEY'),
    );
    if (token == null || token.trim().isEmpty) return;

    // 3) Store token in Supabase
    await _supabase.from('user_push_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'web',
    }, onConflict: 'token');
  }
}
