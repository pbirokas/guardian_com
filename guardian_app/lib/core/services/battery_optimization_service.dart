import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Prüft und fordert die Ausnahme von der Android-Akku-Optimierung (Doze) an.
/// Auf allen anderen Plattformen sind alle Methoden no-ops.
class BatteryOptimizationService {
  static const _channel =
      MethodChannel('com.guardianapp.guardian_app/battery');

  /// Gibt `true` zurück, wenn die App bereits von der Akku-Optimierung
  /// ausgenommen ist (oder die Plattform kein Android ist).
  static Future<bool> isIgnoring() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } on PlatformException {
      return true;
    }
  }

  /// Öffnet den Systemdialog, über den der Nutzer die Akku-Optimierung für
  /// die App deaktivieren kann.
  static Future<void> requestIgnore() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on PlatformException {
      // Ignorieren – Nutzer kann die Einstellung manuell in den Systemeinstellungen ändern.
    }
  }
}
