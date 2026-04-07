// VORLAGE — nicht direkt verwenden!
//
// Diese Datei zeigt die Struktur von firebase_options.dart.
// Erstelle deine eigene Konfiguration mit:
//   flutterfire configure
//
// Oder kopiere diese Datei nach firebase_options.dart und
// ersetze alle Platzhalter mit deinen Firebase-Projektwerten.
// Diese findest du in der Firebase Console unter:
//   Projekteinstellungen → Allgemein → Deine Apps

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions sind für diese Plattform nicht konfiguriert.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'DEIN_WEB_API_KEY',
    appId: 'DEINE_WEB_APP_ID',
    messagingSenderId: 'DEINE_SENDER_ID',
    projectId: 'DEIN_PROJEKT_ID',
    authDomain: 'DEIN_PROJEKT_ID.firebaseapp.com',
    storageBucket: 'DEIN_PROJEKT_ID.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'DEIN_ANDROID_API_KEY',
    appId: 'DEINE_ANDROID_APP_ID',
    messagingSenderId: 'DEINE_SENDER_ID',
    projectId: 'DEIN_PROJEKT_ID',
    storageBucket: 'DEIN_PROJEKT_ID.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'DEIN_IOS_API_KEY',
    appId: 'DEINE_IOS_APP_ID',
    messagingSenderId: 'DEINE_SENDER_ID',
    projectId: 'DEIN_PROJEKT_ID',
    storageBucket: 'DEIN_PROJEKT_ID.firebasestorage.app',
    iosBundleId: 'DEINE_IOS_BUNDLE_ID',
  );
}
