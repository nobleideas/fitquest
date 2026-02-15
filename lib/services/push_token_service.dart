import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  final _supabase = Supabase.instance.client;

  bool _initialized = false;
  StreamSubscription<AuthState>? _authSub;

  /// If false (recommended while feature is incomplete), we will NOT prompt
  /// for notification permission automatically. We will only register if
  /// permission is already granted.
  ///
  /// Set true later when you're actually shipping notifications.
  final bool shouldRequestPermissionOnInit = false;

  // --- Simple throttle to avoid duplicate attempts/logs (init + auth event)
  DateTime? _lastAttemptAt;
  String? _lastAttemptUserId;

  /// Call ONCE (e.g., in MainShell.initState()).
  Future<void> initAndRegister() async {
    debugPrint("✅ PushTokenService.initAndRegister() called");

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
    _lastAttemptAt = null;
    _lastAttemptUserId = null;
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Returns true if notifications are allowed (authorized or provisional).
  /// If [shouldRequestPermissionOnInit] is false, we only check existing status
  /// and avoid prompting.
  Future<bool> _ensurePermissionAllowed() async {
    try {
      if (kIsWeb) {
        // Web permission model varies by browser; requestPermission is OK,
        // but you may prefer prompting only on user action later.
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }

      if (!shouldRequestPermissionOnInit) {
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e, st) {
      debugPrint('PushTokenService permission check failed: $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> registerCurrentToken() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Throttle duplicate attempts within 10 seconds for same user
    final now = DateTime.now();
    if (_lastAttemptUserId == user.id &&
        _lastAttemptAt != null &&
        now.difference(_lastAttemptAt!).inSeconds < 10) {
      return;
    }
    _lastAttemptUserId = user.id;
    _lastAttemptAt = now;

    try {
      // 1) Permission gate
      final allowed = await _ensurePermissionAllowed();
      if (!allowed) return;

      // 2) iOS APNs token gate (prevents crash + avoids simulator noise)
      if (!kIsWeb && Platform.isIOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null || apnsToken.isEmpty) {
          debugPrint(
            'PushTokenService: APNs token not available yet; skipping FCM token registration for now.',
          );
          return;
        }
      }

      // 3) Get FCM token
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey:
            kIsWeb ? const String.fromEnvironment('FIREBASE_VAPID_KEY') : null,
      );
      if (token == null || token.trim().isEmpty) return;

      // 4) Store token in Supabase (dedupe by token)
      await _supabase.from('user_push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': _platformName(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'disabled_at': null,
      }, onConflict: 'token');

      final check = await _supabase
          .from('user_push_tokens')
          .select('id,user_id,token,platform,last_seen_at,disabled_at')
          .eq('token', token)
          .maybeSingle();

      debugPrint('Saved token row: $check');
    } on FirebaseException catch (e, st) {
      // Never crash the app over push setup.
      debugPrint('PushTokenService FirebaseException: ${e.code} ${e.message}');
      debugPrint('$st');
      return;
    } catch (e, st) {
      debugPrint('PushTokenService unexpected error: $e');
      debugPrint('$st');
      return;
    }
  }
}
