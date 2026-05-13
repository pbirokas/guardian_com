import 'package:appwrite/appwrite.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  static RemoteMessage? _pendingMessage;

  // Appwrite-Ressourcen als statische Felder, da die Klasse als Singleton via
  // static-State genutzt wird (mehrere NotificationService()-Instanzen teilen
  // denselben initialisierten Zustand).
  static Databases? _awDb;
  static String? _awUid;

  static void setRouter(GoRouter router) {
    _router = router;
    if (_pendingMessage != null) {
      final msg = _pendingMessage!;
      _pendingMessage = null;
      Future.microtask(() => _staticHandleTap(msg));
    }
  }

  static void _staticHandleTap(RemoteMessage message) {
    final convId = message.data['convId'] as String?;
    if (convId != null) {
      _router?.push('/chat/$convId',
          extra: message.data['chatTitle'] as String?);
    }
  }

  static const _channel = MethodChannel('com.guardianapp.guardian_app/battery');

  /// Entfernt alle offenen App-Benachrichtigungen aus der Statusleiste.
  /// Wird aufgerufen wenn die App in den Vordergrund kommt.
  static Future<void> clearAll() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod('clearAllNotifications');
    } catch (_) {}
  }

  static bool _initialized = false;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> initialize([Databases? db, String? uid]) async {
    if (db != null) _awDb = db;
    if (uid != null) _awUid = uid;

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
      if (_router != null) {
        _handleTap(initial);
      } else {
        // Router noch nicht bereit → zwischenspeichern, wird in setRouter() abgefeuert
        _pendingMessage = initial;
      }
    }
  }

  Future<void> refreshToken() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux)) { return; }
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _saveToken(String token) async {
    final db = _awDb;
    final uid = _awUid;
    if (uid == null || db == null) return;
    await db.updateDocument(
      databaseId: 'guardian',
      collectionId: 'users',
      documentId: uid,
      data: {'fcmToken': token},
    );
  }

  void _handleTap(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final convId = message.data['convId'] as String?;
    final orgId = message.data['orgId'] as String?;

    if (type == 'new_announcement' && orgId != null) {
      _router?.push('/organizations/$orgId');
    } else if (convId != null) {
      _router?.push('/chat/$convId',
          extra: message.data['chatTitle'] as String?);
    }
  }
}
