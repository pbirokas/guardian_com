// Stub – used when compiling for web (dart.library.io is unavailable).
// Provides the same public API as desktop_notification_service.dart but does nothing.

import 'package:appwrite/appwrite.dart';
import 'package:go_router/go_router.dart';

class DesktopNotificationService {
  static void setRouter(GoRouter router) {}
  Future<void> initialize() async {}
  void startListening(Client client, String uid) {}
  void stopListening() {}
  void dispose() {}
}
