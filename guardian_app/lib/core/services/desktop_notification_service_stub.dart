// Stub – used when compiling for web (dart.library.io is unavailable).
// Provides the same public API as desktop_notification_service.dart but does nothing.

import 'package:appwrite/appwrite.dart';
import '../appwrite_client.dart' show RealtimeBroadcaster;
import 'package:go_router/go_router.dart';

class DesktopNotificationService {
  static final DesktopNotificationService instance = DesktopNotificationService._();
  DesktopNotificationService._();
  factory DesktopNotificationService() => instance;

  static void setRouter(GoRouter router) {}
  Future<void> initialize() async {}
  void startListening(Client client, RealtimeBroadcaster broadcaster, String uid) {}
  void stopListening() {}
  void dispose() {}
}
