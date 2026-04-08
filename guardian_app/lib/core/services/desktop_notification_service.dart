import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop-Ersatz für FCM-Push-Benachrichtigungen (Windows / Linux).
///
/// Lauscht per Firestore-Listener auf neue Nachrichten in allen genehmigten
/// Conversations des eingeloggten Nutzers und zeigt native Toast-Notifications.
class DesktopNotificationService {
  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  static bool _initialized = false;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StreamSubscription? _authSub;
  StreamSubscription? _convListSub;

  /// convId → aktive Message-Subscription
  final Map<String, StreamSubscription> _msgSubs = {};

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    await localNotifier.setup(appName: 'Guardian Com');

    _authSub = _auth.authStateChanges().listen((user) {
      _stopListening();
      if (user != null) _startListening(user.uid);
    });

    debugPrint('DesktopNotificationService initialized');
  }

  void _startListening(String uid) {
    _convListSub = _db
        .collection('conversations')
        .where('participantUids', arrayContains: uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snap) {
      final currentIds = snap.docs.map((d) => d.id).toSet();

      // Neue Conversations überwachen
      for (final doc in snap.docs) {
        if (!_msgSubs.containsKey(doc.id)) {
          _watchMessages(
            convId: doc.id,
            convName: doc.data()['name'] as String?,
            currentUid: uid,
          );
        }
      }

      // Beendete Conversations abmelden
      final removed = _msgSubs.keys.toSet().difference(currentIds);
      for (final convId in removed) {
        _msgSubs[convId]?.cancel();
        _msgSubs.remove(convId);
      }
    });
  }

  void _watchMessages({
    required String convId,
    required String? convName,
    required String currentUid,
  }) {
    // Nur Nachrichten empfangen, die ab jetzt ankommen
    final startTime = Timestamp.now();

    final sub = _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .where('sentAt', isGreaterThan: startTime)
        .orderBy('sentAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isEmpty) return;

      final data = snap.docs.first.data();

      // Eigene Nachrichten und archivierte überspringen
      final senderUid = data['senderUid'] as String?;
      if (senderUid == null || senderUid == currentUid) return;
      if (data['isArchived'] == true) return;

      final senderName = data['senderName'] as String? ?? 'Unbekannt';
      final text = data['text'] as String? ?? '';
      final isImage = data['imageUrl'] != null;
      final isAudio = data['audioUrl'] != null;

      final body = isImage
          ? 'Bild'
          : isAudio
              ? 'Sprachnachricht'
              : text.length > 100
                  ? '${text.substring(0, 100)}…'
                  : text;

      final title =
          convName != null ? '$convName: $senderName' : senderName;
      final chatTitle = convName ?? senderName;

      _showNotification(
        title: title,
        body: body,
        convId: convId,
        chatTitle: chatTitle,
      );
    });

    _msgSubs[convId] = sub;
  }

  Future<void> _showNotification({
    required String title,
    required String body,
    required String convId,
    required String chatTitle,
  }) async {
    final notification = LocalNotification(
      title: title,
      body: body,
    );
    notification.onClick = () async {
      // Fenster in den Vordergrund bringen
      await windowManager.show();
      await windowManager.focus();
      _router?.push('/chat/$convId', extra: chatTitle);
    };
    await notification.show();
  }

  void _stopListening() {
    _convListSub?.cancel();
    _convListSub = null;
    for (final sub in _msgSubs.values) {
      sub.cancel();
    }
    _msgSubs.clear();
  }

  void dispose() {
    _authSub?.cancel();
    _stopListening();
    _initialized = false;
  }
}
