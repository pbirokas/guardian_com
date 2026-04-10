import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Muss top-level sein (außerhalb jeder Klasse) für Background-Handler.
/// Wird nur auf mobilen Plattformen registriert.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM zeigt Background/Terminated-Notifications automatisch an
}

/// FCM-basierter Notification-Service für Android und iOS.
/// Auf Windows/Linux wird stattdessen [DesktopNotificationService] verwendet.
class NotificationService {
  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  static bool _initialized = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initialize() async {
    // FCM wird auf Windows/Linux nicht unterstützt
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux)) { return; }

    if (_initialized) {
      await refreshToken();
      return;
    }
    _initialized = true;

    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
    _fcm.onTokenRefresh.listen(_saveToken);

    // Foreground: System zeigt die Notification – kein In-App-Banner nötig
    FirebaseMessaging.onMessage.listen((_) {});

    // App war im Hintergrund, Notification getippt → navigieren
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App war geschlossen, Notification getippt → navigieren
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _handleTap(initial),
      );
    }
  }

  Future<void> refreshToken() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux)) { return; }
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }

  void _handleTap(RemoteMessage message) {
    final convId = message.data['convId'] as String?;
    if (convId != null) {
      _router?.push('/chat/$convId',
          extra: message.data['chatTitle'] as String?);
    }
  }
}
