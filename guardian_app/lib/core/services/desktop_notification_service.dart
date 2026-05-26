import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import '../appwrite_client.dart' show RealtimeBroadcaster;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_service.dart';

/// Desktop-Ersatz für FCM-Push-Benachrichtigungen (Windows / Linux).
///
/// - Lauscht auf neue Nachrichten → zeigt Toast-Notifications
/// - Verfolgt ungelesene Chats → aktualisiert Tray-Badge
///
/// Verwendung: [initialize] einmalig beim Start, danach [startListening] mit
/// uid aufrufen wenn der Nutzer eingeloggt ist, [stopListening] beim Logout.
class DesktopNotificationService {
  static final DesktopNotificationService instance = DesktopNotificationService._();
  DesktopNotificationService._();
  factory DesktopNotificationService() => instance;

  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  static bool _initialized = false;

  Databases? _db;
  RealtimeBroadcaster? _broadcaster;

  StreamSubscription? _convSub;
  StreamSubscription? _unreadSub;

  /// convId → aktive Message-Subscription (für Toast-Notifications)
  final Map<String, StreamSubscription> _msgSubs = {};

  /// Aktueller Unread-Count für Tray-Badge
  int _unreadCount = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await localNotifier.setup(appName: 'Guardian Com');
    debugPrint('DesktopNotificationService initialized');
  }

  void startListening(Client client, RealtimeBroadcaster broadcaster, String uid) {
    stopListening();
    _db = Databases(client);
    _broadcaster = broadcaster;
    _startConversationTracking(uid);
    _startUnreadTracking(uid);
  }

  void stopListening() {
    _convSub?.cancel();
    _convSub = null;
    _unreadSub?.cancel();
    _unreadSub = null;
    for (final sub in _msgSubs.values) {
      sub.cancel();
    }
    _msgSubs.clear();
    _unreadCount = 0;
    TrayService.instance.updateBadge(0);
    _db = null;
    _broadcaster = null;
  }

  // ── Toast-Notifications ────────────────────────────────────────────────────

  void _startConversationTracking(String uid) {
    final db = _db!;

    Future<void> refresh() async {
      try {
        final result = await db.listDocuments(
          databaseId: 'guardian',
          collectionId: 'conversations',
          queries: [
            Query.contains('participantUids', [uid]),
            Query.equal('status', 'approved'),
            Query.limit(200),
          ],
        );
        final currentIds = result.documents.map((d) => d.$id).toSet();

        for (final doc in result.documents) {
          if (!_msgSubs.containsKey(doc.$id)) {
            _watchMessages(
              convId: doc.$id,
              convName: doc.data['name'] as String?,
              currentUid: uid,
            );
          }
        }

        final removed = _msgSubs.keys.toSet().difference(currentIds);
        for (final convId in removed) {
          _msgSubs[convId]?.cancel();
          _msgSubs.remove(convId);
        }
      } catch (_) {}
    }

    _convSub = _broadcaster!
        .stream('databases.guardian.collections.conversations.documents')
        .listen((_) => refresh());
    refresh();
  }

  void _watchMessages({
    required String convId,
    required String? convName,
    required String currentUid,
  }) {
    final startTime = DateTime.now();

    final sub = _broadcaster!
        .stream('databases.guardian.collections.chat_messages.documents')
        .listen((event) {
      // Only care about newly created messages in this conversation
      final isCreate =
          event.events.any((e) => e.endsWith('.create'));
      if (!isCreate) return;

      final data = event.payload;
      if (data['convId'] != convId) return;

      final sentAtRaw = data['sentAt'] as String?;
      if (sentAtRaw != null) {
        final sentAt = DateTime.tryParse(sentAtRaw);
        if (sentAt != null && sentAt.isBefore(startTime)) return;
      }

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
    final db = _db!;

    Future<void> recalculate() async {
      try {
        final result = await db.listDocuments(
          databaseId: 'guardian',
          collectionId: 'conversations',
          queries: [
            Query.contains('participantUids', [uid]),
            Query.equal('status', 'approved'),
            Query.limit(200),
          ],
        );

        int count = 0;
        for (final doc in result.documents) {
          final data = doc.data;
          final lastMessageAtRaw = data['lastMessageAt'] as String?;
          if (lastMessageAtRaw == null) continue;
          final lastMessageAt = DateTime.tryParse(lastMessageAtRaw);
          if (lastMessageAt == null) continue;

          final lastReadJson = data['lastReadAtJson'] as String?;
          DateTime? lastRead;
          if (lastReadJson != null) {
            final map = jsonDecode(lastReadJson) as Map<String, dynamic>?;
            final raw = map?[uid] as String?;
            if (raw != null) lastRead = DateTime.tryParse(raw);
          }

          if (lastRead == null || lastMessageAt.isAfter(lastRead)) count++;
        }

        if (count != _unreadCount) {
          _unreadCount = count;
          TrayService.instance.updateBadge(count);
        }
      } catch (_) {}
    }

    _unreadSub = _broadcaster!
        .stream('databases.guardian.collections.conversations.documents')
        .listen((_) => recalculate());
    recalculate();
  }

  void dispose() {
    stopListening();
    _initialized = false;
  }
}
