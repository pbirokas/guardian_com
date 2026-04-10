// Stub – used when compiling for web (dart.library.io is unavailable).
// Provides the same public API as tray_service.dart but does nothing.

class TrayService {
  static final TrayService instance = TrayService._();
  TrayService._();

  Future<void> initialize() async {}
  void updateBadge(int count) {}
  void dispose() {}
}
