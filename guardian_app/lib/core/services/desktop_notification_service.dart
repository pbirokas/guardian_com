import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_service.dart';

/// Desktop-Ersatz für FCM-Push-Benachrichtigungen (Windows / Linux).
///
/// - Lauscht auf neue Nachrichten → zeigt Toast-Notifications
/// - Verfolgt ungelesene Chats → aktualisiert Tray-Badge
class DesktopNotificationService {
  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  static bool _initialized = false;

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StreamSubscription? _authSub;
  StreamSubscription? _convListSub;
  StreamSubscription? _unreadSub;

  /// convId → aktive Message-Subscription (für Toast-Notifications)
  final Map<String, StreamSubscription> _msgSubs = {};

  /// Aktueller Unread-Count für Tray-Badge
  int _unreadCount = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await localNotifier.setup(appName: 'Guardian Com');

    _authSub = _auth.authStateChanges().listen((user) {
      _stopListening();
      if (user != null) {
        _startListening(user.uid);
        _startUnreadTracking(user.uid);
      }
    });

    debugPrint('DesktopNotificationService initialized');
  }

  // ── Toast-Notifications ────────────────────────────────────────────────────

  void _startListening(String uid) {
    _convListSub = _db
        .collection('conversations')
        .where('participantUids', arrayContains: uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snap) {
      final currentIds = snap.docs.map((d) => d.id).toSet();

      for (final doc in snap.docs) {
        if (!_msgSubs.containsKey(doc.id)) {
          _watchMessages(
            convId: doc.id,
            convName: doc.data()['name'] as String?,
            currentUid: uid,
          );
        }
      }

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

      final title = convName != null ? '$convName: $senderName' : senderName;
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
    final notification = LocalNotification(title: title, body: body);
    notification.onClick = () async {
      await windowManager.show();
      await windowManager.focus();
      _router?.push('/chat/$convId', extra: chatTitle);
    };
    await notification.show();
  }

  // ── Unread-Tracking für Tray-Badge ─────────────────────────────────────────

  void _startUnreadTracking(String uid) {
    _unreadSub = _db
        .collection('conversations')
        .where('participantUids', arrayContains: uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snap) {
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final lastMessageAt = data['lastMessageAt'] as Timestamp?;
        if (lastMessageAt == null) continue;

        final lastReadMap = data['lastReadAt'] as Map<String, dynamic>?;
        final lastRead = lastReadMap?[uid] as Timestamp?;

        final hasUnread = lastRead == null ||
            lastMessageAt.toDate().isAfter(lastRead.toDate());
        if (hasUnread) count++;
      }

      if (count != _unreadCount) {
        _unreadCount = count;
        TrayService.instance.updateBadge(count);
      }
    });
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  void _stopListening() {
    _convListSub?.cancel();
    _convListSub = null;
    _unreadSub?.cancel();
    _unreadSub = null;
    for (final sub in _msgSubs.values) {
      sub.cancel();
    }
    _msgSubs.clear();
    _unreadCount = 0;
    TrayService.instance.updateBadge(0);
  }

  void dispose() {
    _authSub?.cancel();
    _stopListening();
    _initialized = false;
  }
}
