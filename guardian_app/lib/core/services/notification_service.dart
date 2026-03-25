import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Muss top-level sein (außerhalb jeder Klasse) für Background-Handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM zeigt Background/Terminated-Notifications automatisch an
}

class NotificationService {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  static bool _initialized = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initialize() async {
    if (_initialized) {
      await refreshToken();
      return;
    }
    _initialized = true;
    // Berechtigung anfragen
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // FCM-Token speichern
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
    _fcm.onTokenRefresh.listen(_saveToken);

    // Foreground-Nachrichten als SnackBar anzeigen
    FirebaseMessaging.onMessage.listen(_showForegroundBanner);

    // App war im Hintergrund, Notification getippt
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App war geschlossen, Notification getippt
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Kurz warten bis Router bereit ist
      Future.delayed(const Duration(milliseconds: 500), () => _handleTap(initial));
    }
  }

  Future<void> refreshToken() async {
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }

  void _showForegroundBanner(RemoteMessage message) {
    final convId = message.data['convId'] as String?;
    final chatTitle = message.data['chatTitle'] as String?;
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
            if (body.isNotEmpty)
              Text(body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70)),
          ],
        ),
        action: convId != null
            ? SnackBarAction(
                label: 'Öffnen',
                textColor: Colors.white,
                onPressed: () => _router?.push('/chat/$convId', extra: chatTitle),
              )
            : null,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleTap(RemoteMessage message) {
    final convId = message.data['convId'] as String?;
    if (convId != null) {
      _router?.push('/chat/$convId', extra: message.data['chatTitle'] as String?);
    }
  }
}
