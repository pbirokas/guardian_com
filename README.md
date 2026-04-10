# Guardian App

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-green)](#builds)

Eine Flutter-App für sichere, überwachte Kommunikation zwischen Kindern, Erziehungsberechtigten und Organisationen.

Diese App wurde vollständig durch vibe-coding generiert.
Dazu wurde ClaudeCode verwendet um meine Vorstellungen in eine App zu gießen.

## Technologie

| Bereich | Stack |
|---|---|
| **Frontend** | Flutter 3.x (Dart) |
| **Backend** | Firebase (Auth, Firestore, Storage, FCM, App Check) |
| **State Management** | Riverpod 3.x |
| **Navigation** | GoRouter |
| **Authentifizierung** | Google Sign-In (Android), E-Mail-Link (Android, Windows) |
| **Cloud Functions** | Node.js 22 (Benachrichtigungen, E-Mail-Einladungen) |

---

## Funktionsübersicht

### Authentifizierung
- **Google Sign-In** (Android)
- **E-Mail-Link (passwortlos):** Nutzer gibt E-Mail ein → erhält Anmeldelink per E-Mail → Klick öffnet die App und meldet direkt an. Kein Passwort nötig.
  - Auf Android: Deep Link öffnet die App automatisch (App Links mit assetlinks.json)
  - Auf Windows: Link aus dem Browser kopieren und in der App einfügen
- Automatische Benutzerprofil-Erstellung bei der ersten Anmeldung
- Pre-Registrierung: Einladungen werden beim ersten Login automatisch verarbeitet, sodass Rollen sofort aktiv sind

### Organisationen
- Organisationen erstellen mit Name, Kategorie (Familie, Freunde, Schule, Vereine, Sonstiges) und Chat-Modus
- Namen sind auf 40 Zeichen begrenzt
- Mitglieder per E-Mail einladen mit Rollenzuweisung
- **Bulk-Import:** Mehrere Mitglieder gleichzeitig per CSV-Datei importieren (nur für Admins in Sheltered-Orgs)
- **Automatische Einladungs-E-Mail** an noch nicht registrierte Nutzer (via Gmail SMTP + Cloud Function)
- **Pre-Registrierung:** Einladung für noch nicht registrierte Nutzer — beim ersten Login erhalten sie automatisch die richtige Rolle
- Organisation bearbeiten (Name, Kategorie, Chat-Modus)
- Organisation archivieren (read-only) oder dauerhaft löschen
- Admin-Rolle auf ein anderes Mitglied übertragen
- Aus einer Organisation austreten (nicht für Admins)
- Versionsnummer mit Build-Nummer in der Organisations-Übersicht

#### Rollen
| Rolle | Beschreibung |
|---|---|
| **Admin** | Volle Kontrolle über die Organisation |
| **Moderator** | Kann Chats einsehen, genehmigen und verwalten |
| **Mitglied** | Normales Mitglied, kann Chats anfordern |
| **Kind** | Eingeschränktes Mitglied, benötigt einen Guardian |

- Rollenänderung auf **Kind** öffnet direkt die Guardian-Auswahl

### Chat-Modi

#### Guardian-Modus
- Mitglieder können Chats mit anderen Mitgliedern anfordern
- Admin oder Moderator genehmigt oder lehnt Anfragen ab
- Abgelehnte Anfragen werden gelöscht → neue Anfrage jederzeit möglich
- Nach Chat-Löschung kann ebenfalls eine neue Anfrage gestellt werden
- Genehmigte Chats sind für den Guardian des Kindes sichtbar

#### Sheltered-Modus
- Admin legt vorab fest, wer mit wem kommunizieren darf
- Nur freigegebene Verbindungen sind möglich
- Moderatoren haben Einsicht in alle Chats der Organisation
- Gruppen-Chats möglich
- **Abstimmungen/Umfragen** können von Teilnehmern gestartet werden (Einzel- oder Mehrfachauswahl)

### Guardian-Kind-Beziehung
- Kind-Mitglieder werden einem oder mehreren Guardians zugewiesen
- Guardian muss die Einladung seines Kindes bestätigen
- Guardian-Kind-Beziehung wird in der Mitgliederliste mit Symbol angezeigt
- Guardian hat Lesezugriff auf die Chats seines Kindes

### Chat-Funktionen
- Textnachrichten senden
- **URLs und E-Mail-Adressen** in Nachrichten sind anklickbar
- **Eigene Nachrichten bearbeiten** (per Langer Druck → Bearbeiten)
- **Text in Zwischenablage kopieren** (per Langer Druck → Kopieren)
- Bearbeitete Nachrichten von Admin/Moderator werden automatisch archiviert (Moderations-Log)
- Bilder senden (JPEG, max. 2 MB, automatisch komprimiert)
- **Bild antippen** öffnet Vollbild-Ansicht mit Pinch-to-Zoom
- Sprachnachrichten aufnehmen und abspielen (AAC/Opus, max. 10 MB)
- **Dateien senden** (max. 5 MB, beliebige Dateitypen) — per „+"-Menü im Chat
- **Abstimmungen** in Sheltered-Chats erstellen und abstimmen
- Scrollbar an der rechten Seite
- Ältere Nachrichten automatisch nachladen beim Hochscrollen

### Chat-Verwaltung (Admin & Moderator)
- Chats archivieren (werden read-only)
- Chats dauerhaft löschen (inkl. aller Nachrichten)
- Ausstehende Chat-Anfragen genehmigen oder ablehnen

### Ungelesene Nachrichten
- Badge-Anzeige auf Chat-Kacheln
- Badge auf dem Chats-Tab mit Unterscheidung: rot (ausstehende Anfragen) / blau (ungelesene Nachrichten)
- Badge auf Organisations-Karten im Startbildschirm

### Push-Benachrichtigungen

#### Android (FCM)
- Benachrichtigung bei neuer Nachricht in genehmigten Chats
- Benachrichtigung bei neuer Chat-Anfrage (Guardian-Modus) — für Approver, Guardian und Angefragten
- Foreground & Background: native System-Benachrichtigung
- Tap auf Benachrichtigung öffnet direkt den Chat
- Benachrichtigungsintervall global und pro Organisation einstellbar:
  - Jede Nachricht
  - Max. 1x pro Stunde
  - Max. 1x pro Tag
  - Nie

#### Windows (Firestore-Listener)
- Echtzeit-Listener auf alle genehmigten Chats
- Native Windows Toast-Benachrichtigung bei neuer Nachricht
- Tap auf Toast navigiert direkt zum Chat
- **Tray-Icon** mit Rechtsklick-Menü (Öffnen / Beenden)
- **Tray-Icon** wechselt bei ungelesenen Nachrichten zu Badge-Version mit rotem Punkt
- **Taskleisten-Symbol** zeigt Overlay-Badge und blinkt bei neuen Nachrichten
- Tooltip zeigt Anzahl ungelesener Chats

### Bulk-Import (CSV)
- Admins von Sheltered-Orgs können Mitglieder per CSV-Datei importieren
- Delimiter (`,` oder `;`) wird automatisch erkannt
- Spalten: `email`, `rolle`, `guardians` (Leerzeichen-getrennte E-Mails)
- Vorschau mit Validierung vor dem Import (✓ gültig, ⚠ Warnung, ✗ Fehler)
- Beispiel-CSV unter [`guardian_app/assets/bulk_import_example.csv`](guardian_app/assets/bulk_import_example.csv)

### Keyword-Monitoring
- Admin kann pro Organisation eine Liste von Schlüsselwörtern pflegen
- Bei Auftreten eines Keywords werden Guardians, Moderatoren und der Admin per Push-Benachrichtigung informiert
- Verwaltung über das 🔍-Icon in der AppBar der Organisation

### Guardian-Aktivitäts-Benachrichtigungen
- Guardian wird benachrichtigt, wenn sein Kind eine Nachricht sendet oder empfängt
- Benachrichtigungsintervall einstellbar (pro Guardian, pro Organisation):
  - Jede Nachricht
  - Max. 1x pro Stunde *(Standard)*
  - Max. 1x pro Tag
  - Nie

### Nachrichten melden
- Mitglieder können fremde Nachrichten per Langer Druck melden
- Admin und Moderatoren erhalten eine Push-Benachrichtigung
- Meldungen sind im **Meldungen-Tab** der Organisation einsehbar
- Geprüfte Meldungen werden als archiviert markiert und ausgeblendet (Toggle zum Einblenden)
- Badge mit Anzahl ausstehender Meldungen auf dem Tab
- Admin/Moderator kann Meldung prüfen, Nachricht löschen oder direkt in den Chat springen

### Sonstiges
- Dark / Light Mode
- Spenden-Popup (Ko-fi / PayPal) — erscheint max. 1× pro Woche, nicht für Kinder
- Firebase Crashlytics (Android)
- Firebase App Check (Android)
- Versionsnummer automatisch aus Git-Commit-Anzahl generiert

---

## Builds

| Plattform | Status | Besonderheiten |
|---|---|---|
| **Android** | ✅ | Google Play, FCM, Google Sign-In + E-Mail-Link, App Check |
| **Windows** | ✅ | System Tray, Taskleisten-Badge, E-Mail-Link |
| **iOS / macOS** | ⏳ nicht konfiguriert | – |

### Windows-Build erstellen

```bash
cd guardian_app
flutter build windows --release
```

Die fertige App liegt unter:
```
build/windows/x64/runner/Release/
```

### Android-Build erstellen

```bash
cd guardian_app
flutter build appbundle --release
```

---

## Projektstruktur

```
guardian_app/
├── lib/
│   ├── core/
│   │   ├── models/          # Datenmodelle (AppUser, Organization, Conversation, Message, Poll, …)
│   │   ├── router/          # GoRouter-Konfiguration
│   │   └── services/        # Firebase-Dienste (Auth, Chat, Organization, Notification,
│   │                        #   DesktopNotification, TrayService, TrayService-Stub)
│   └── features/
│       ├── auth/            # Login-Screen, Provider
│       ├── chat/            # Chat-Screen, Provider
│       ├── organizations/   # Org-Liste, Org-Detail, Bulk-Import, Provider
│       └── profile/         # Profil-Screen
├── android/                 # Android-spezifische Konfiguration
├── windows/                 # Windows-spezifische Konfiguration
└── assets/
    ├── icon/                # App-Icons
    └── bulk_import_example.csv

firestore.rules              # Firestore Security Rules
storage.rules                # Firebase Storage Security Rules
firebase.json                # Firebase-Konfiguration (Firestore, Storage, Functions)
functions/
└── index.js                 # Cloud Functions:
                             #   onNewMessage, onNewConversationRequest,
                             #   onNewInvitation (inkl. E-Mail), onNewReport,
                             #   processMyInvitations, getCustomToken
```

---

## Firebase-Struktur (Firestore)

```
users/{uid}
  memberships[]
  isChild
  fcmToken

organizations/{orgId}
  members/{uid}
    messageAlertInterval
    childAlertInterval
    lastMessageAlertAt
    lastChildAlertAt

conversations/{convId}
  messages/{msgId}
  polls/{pollId}

invitations/{inviteId}
invitationLookup/{email}
reports/{reportId}
```

---

## Cloud Functions

| Funktion | Trigger | Beschreibung |
|---|---|---|
| `onNewMessage` | Firestore Create | FCM-Push bei neuer Nachricht, Cooldown-Logik, Keyword-Monitoring |
| `onNewConversationRequest` | Firestore Create | Push an Approver, Guardian und Angefragten bei Chat-Anfrage |
| `onNewInvitation` | Firestore Create | Push an Guardians (Kind-Einladung) + E-Mail an nicht registrierte Nutzer |
| `onNewReport` | Firestore Create | Push an Admin + Moderatoren bei gemeldeter Nachricht |
| `processMyInvitations` | Callable | Verarbeitet ausstehende Einladungen beim Login |
| `getCustomToken` | HTTP | Tauscht Firebase-idToken gegen Custom Token (Windows E-Mail-Link-Login) |

---

## Setup

> **Hinweis:** Firebase-Konfigurationsdateien (`google-services.json`, `firebase_options.dart`, `key.properties`) sind nicht im Repository enthalten — sie müssen für deine eigene Firebase-Instanz erstellt werden.

### Voraussetzungen

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.x
- [Firebase CLI](https://firebase.google.com/docs/cli) + [FlutterFire CLI](https://firebase.flutter.dev/docs/cli)
- Android Studio (für Android-Builds) oder Visual Studio 2022 mit C++-Workload (für Windows-Builds)
- Node.js 22 (für Cloud Functions)

### Schritt-für-Schritt

```bash
# 1. Repository klonen
git clone https://github.com/pbirokas/guardian_com.git
cd guardian_com

# 2. Firebase-Projekt erstellen (console.firebase.google.com)
#    → Authentication (Google Sign-In + E-Mail-Link aktivieren)
#    → Firestore Database anlegen
#    → Storage aktivieren
#    → Cloud Functions aktivieren (Blaze-Plan)
#    → App Check aktivieren (Android: Play Integrity)

# 3. FlutterFire konfigurieren (erzeugt firebase_options.dart + google-services.json)
cd guardian_app
flutterfire configure --platforms=android,windows

# 4. Abhängigkeiten installieren
flutter pub get

# 5. Cloud Functions Abhängigkeiten installieren
cd ../functions
npm install

# 6. Gmail App-Passwort für Einladungs-E-Mails hinterlegen (optional)
firebase functions:secrets:set GMAIL_APP_PASSWORD

# 7. Firebase-Regeln & Functions deployen
cd ..
firebase deploy --only firestore:rules,storage,functions

# 8. App starten
cd guardian_app
flutter run                     # Android
flutter run -d windows          # Windows
```

### IAM-Berechtigung für Custom Token (Windows-Login)

Damit der E-Mail-Link-Login auf Windows funktioniert, benötigt der Cloud Functions
Service Account die Berechtigung zum Erstellen von Tokens:

```bash
gcloud projects add-iam-policy-binding PROJEKT_ID \
  --member="serviceAccount:PROJEKTNUMMER-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

Projektnummer findest du unter: Firebase Console → Projekteinstellungen → Allgemein.

### Vorlage für firebase_options.dart

Eine Vorlage befindet sich unter [`guardian_app/lib/firebase_options.example.dart`](guardian_app/lib/firebase_options.example.dart).  
Umbenennen und mit eigenen Firebase-Werten befüllen, oder `flutterfire configure` verwenden.

---

## Beitragen

Beiträge sind willkommen! Bitte lies zuerst [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## Lizenz

Dieses Projekt steht unter der [MIT-Lizenz](LICENSE).  
© 2025 Pantelis Birokas
