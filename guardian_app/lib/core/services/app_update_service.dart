import 'dart:io' show Platform;

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Dringlichkeitsstufe eines verfügbaren Updates.
enum UpdateLevel {
  /// App ist aktuell (oder Prüfung nicht anwendbar / fehlgeschlagen).
  none,

  /// Neuere Version verfügbar — wegklickbarer Hinweis.
  recommended,

  /// Version unter Mindestversion — blockierende Sperre.
  required,
}

/// Ergebnis der Update-Prüfung inkl. passendem Ziel-Link (Play Store bei
/// Store-Installation, sonst GitHub-Releases).
class AppUpdateStatus {
  final UpdateLevel level;
  final String targetUrl;
  final String? latestVersionName;

  const AppUpdateStatus({
    required this.level,
    required this.targetUrl,
    this.latestVersionName,
  });

  static const none =
      AppUpdateStatus(level: UpdateLevel.none, targetUrl: '');
}

/// Prüft beim App-Start gegen das Appwrite-Versions-Manifest (`app_config/android`),
/// ob ein Update verfügbar bzw. erforderlich ist. Aktuell nur Android.
///
/// Grundsatz: Schlägt irgendetwas fehl (offline, Manifest fehlt, Feld fehlt),
/// wird [UpdateLevel.none] zurückgegeben — die App darf NIE wegen einer
/// fehlgeschlagenen Prüfung blockieren.
class AppUpdateService {
  AppUpdateService(Client client) : _db = Databases(client);

  final Databases _db;

  static const _dbId = 'guardian';
  static const _col = 'app_config';
  static const _docId = 'android';
  static const _playStoreInstaller = 'com.android.vending';
  static const _channel =
      MethodChannel('com.guardianapp.guardian_app/app_info');

  Future<AppUpdateStatus> check() async {
    // Nur Android — Windows/Web sind aktuell ausgenommen.
    if (kIsWeb || !Platform.isAndroid) return AppUpdateStatus.none;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber);
      // Ohne verlässliche Build-Nummer nicht blockieren (Fail-Safe).
      if (currentCode == null) return AppUpdateStatus.none;

      final doc = await _db.getDocument(
        databaseId: _dbId,
        collectionId: _col,
        documentId: _docId,
      );
      final data = doc.data;
      final latestCode = (data['latestVersionCode'] as num?)?.toInt() ?? 0;
      final minCode = (data['minVersionCode'] as num?)?.toInt() ?? 0;
      final latestName = data['latestVersionName'] as String?;
      final playUrl = data['playStoreUrl'] as String? ?? '';
      final githubUrl = data['githubReleasesUrl'] as String? ?? '';

      final needsRequired = currentCode < minCode;
      final needsRecommended = currentCode < latestCode;
      // Aktuell → kein nativer Install-Source-Aufruf nötig.
      if (!needsRequired && !needsRecommended) return AppUpdateStatus.none;

      // Ziel-Link je nach Installationsquelle, mit Fallback auf den anderen Link,
      // falls das gewählte Feld leer ist.
      final fromPlay = await _isFromPlayStore();
      var targetUrl = fromPlay ? playUrl : githubUrl;
      if (targetUrl.isEmpty) targetUrl = fromPlay ? githubUrl : playUrl;

      if (needsRequired) {
        // Eine blockierende Sperre ohne funktionierenden Link wäre eine Sackgasse
        // → dann lieber nicht erzwingen.
        if (targetUrl.isEmpty) return AppUpdateStatus.none;
        return AppUpdateStatus(
          level: UpdateLevel.required,
          targetUrl: targetUrl,
          latestVersionName: latestName,
        );
      }
      return AppUpdateStatus(
        level: UpdateLevel.recommended,
        targetUrl: targetUrl,
        latestVersionName: latestName,
      );
    } catch (_) {
      // Fehlgeschlagene Prüfung darf nie blockieren.
      return AppUpdateStatus.none;
    }
  }

  Future<bool> _isFromPlayStore() async {
    try {
      final src = await _channel.invokeMethod<String>('getInstallSource');
      return src == _playStoreInstaller;
    } catch (_) {
      return false; // im Zweifel als Sideload behandeln → GitHub-Link
    }
  }
}
