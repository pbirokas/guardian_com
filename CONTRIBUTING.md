# Beitragen zu Guardian App

Danke für dein Interesse! Hier sind die wichtigsten Hinweise.

## Voraussetzungen

Lies zuerst die [Setup-Anleitung im README](README.md#setup) und richte deine eigene
Firebase-Instanz ein, bevor du Code-Änderungen vornimmst.

## Ablauf

1. **Fork** erstellen → eigenen Branch anlegen (`feature/mein-feature`)
2. Änderungen implementieren
3. Sicherstellen dass `flutter analyze` fehlerfrei läuft
4. **Pull Request** gegen `main` stellen mit einer klaren Beschreibung

## Was nicht committet werden darf

| Datei | Grund |
|---|---|
| `google-services.json` | Firebase API-Schlüssel |
| `lib/firebase_options.dart` | Firebase-Konfiguration |
| `android/key.properties` | Keystore-Passwörter |
| `*.jks` / `*.keystore` | Signatur-Zertifikate |
| `.env` / `.env.*` | Umgebungsvariablen |

Diese Dateien sind in `.gitignore` eingetragen und dürfen unter keinen Umständen
in einem Commit landen.

## Code-Stil

- Standard Flutter/Dart-Konventionen (`flutter analyze` muss sauber sein)
- Riverpod für State Management, GoRouter für Navigation
- Deutsche Strings in der UI (App-Sprache ist Deutsch)

## Lizenz

Mit einem Pull Request stimmst du zu, dass dein Beitrag unter der
[MIT-Lizenz](LICENSE) veröffentlicht wird.
