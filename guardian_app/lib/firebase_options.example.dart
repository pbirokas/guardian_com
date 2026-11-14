// VORLAGE — nicht direkt verwenden!
//
// Struktur von lib/firebase_options.dart (gitignored, enthält API-Keys).
// Firebase wird nur noch für Push (FCM) und Crashlytics auf Android genutzt;
// Backend, Auth und Storage laufen über Appwrite.
//
// Kopiere diese Datei nach firebase_options.dart und trage die Werte der
// Android-App aus der Firebase Console ein:
//   Projekteinstellungen → Allgemein → Deine Apps → Android
// (Web-Optionen kommen erst mit Web Push hinzu.)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'Firebase ist nur für Android konfiguriert (FCM + Crashlytics).',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'DEIN_ANDROID_API_KEY',
    appId: 'DEINE_ANDROID_APP_ID',
    messagingSenderId: 'DEINE_SENDER_ID',
    projectId: 'DEIN_PROJEKT_ID',
  );
}
