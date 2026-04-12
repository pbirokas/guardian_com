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

### Guardian-Kind-Beziehung (Org-lokal)
- Kind-Mitglieder werden einem oder mehreren Guardians innerhalb der Organisation zugewiesen
- Guardian muss die Einladung seines Kindes bestätigen
- Guardian-Kind-Beziehung wird in der Mitgliederliste mit Symbol angezeigt
- Guardian hat Lesezugriff auf die Chats seines Kindes

### Verifizierte Eltern-Kind-Verknüpfung (konto-übergreifend)

Eltern und Kinder können eine **globale, organisationsunabhängige** Verknüpfung aufbauen, die sicherheitskritische Funktionen für alle Organisationen aktiviert.

#### Prozess

| Schritt | Wer | Was passiert |
|---|---|---|
| **1. Anfrage senden** | Elternteil | Öffnet *Profil → Meine Verknüpfungen*, gibt E-Mail des Kindes ein → `ClaimRequest` wird erstellt (7 Tage gültig), Kind erhält Push-Benachrichtigung |
| **2. Anfrage bestätigen** | Kind | Sieht eingehende Anfrage in *Meine Verknüpfungen*, bestätigt oder lehnt ab |
| **3. Verknüpfung aktiv** | System | Cloud Function aktualisiert beide Konten (`verifiedParentUids` / `verifiedChildUids`), Elternteil erhält Bestätigungs-Push |
| **4. Verknüpfung aufheben** | Elternteil | Nur Elternteile können die Verbindung trennen — Kinder haben kein Recht zur Aufhebung |

#### Org-Einladung eines verknüpften Kindes

Sobald ein Kind verifizierte Eltern hat, wird eine direkte Org-Einladung **blockiert** und ein Einwilligungsprozess gestartet:

1. Admin lädt Kind in eine Organisation ein
2. Statt direktem Beitritt: `OrgInviteConsent`-Dokument wird angelegt
3. **Alle** verifizierten Eltern erhalten eine Push-Benachrichtigung
4. Eltern sehen die ausstehende Einwilligung unter *Meine Verknüpfungen*

**Genehmigung:** Ein einziges Elternteil genügt → Kind wird mit Status `pending` hinzugefügt (Guardian muss danach noch separat bestätigen)  
**Veto:** Jedes Elternteil kann alleine ablehnen → Einladung wird verworfen, Admin erhält Benachrichtigung

#### Rollenschutz für Kind-Konten

- Konten mit `isChild: true` können ausschließlich die Rolle **Kind** in Organisationen innehaben
- Rollenänderungen auf Admin/Moderator/Mitglied werden blockiert (`child_account_role_locked`)
- Kind-Konten können keine neuen Organisationen erstellen

### Meine Verknüpfungen (Profil-Bereich)

Erreichbar über **Profil → Meine Verknüpfungen**. Der Screen vereint alle Aspekte der konto-übergreifenden Eltern-Kind-Verwaltung:

- **Eingehende Anfragen** (Kind-Ansicht): Anfragen von Elternteilen bestätigen oder ablehnen
- **Ausgehende Anfragen** (Eltern-Ansicht): aktive Anfragen einsehen und zurückziehen
- **Kind verknüpfen**: E-Mail des Kindes eingeben und Anfrage senden
- **Meine Kinder / Meine Eltern**: Liste der verifizierten Verbindungen mit Möglichkeit zur Aufhebung
- **Ausstehende Einwilligungen**: Org-Einladungen für eigene Kinder genehmigen oder ablehnen
- Verifizierte Verbindungen werden in der Mitgliederliste der Organisation mit `🏡`-Symbol angezeigt

### Chat-Funktionen
- Textnachrichten senden
- **URLs und E-Mail-Adressen** in Nachrichten sind anklickbar
- **Eigene Nachrichten bearbeiten** (per Langer Druck → Bearbeiten)
- **Text in Zwischenablage kopieren** (per Langer Druck → Kopieren)
- Bearbeitete Nachrichten von Admin/Moderator werden automatisch archiviert (Moderations-Log)
- Bilder senden (JPEG, max. 2 MB, automatisch komprimiert)
- **Bild antippen** öffnet Vollbild-Ansicht mit Pinch-to-Zoom und Speicher-Button (lokale Ordnerauswahl)
- Bilder im Chat werden zwischengespeichert (keine Laderuckler beim Scrollen)
- Sprachnachrichten aufnehmen und abspielen (AAC/Opus, max. 10 MB)
- **Dateien senden** (max. 5 MB, beliebige Dateitypen) — per „+"-Menü im Chat
- **Abstimmungen** in Sheltered-Chats erstellen und abstimmen
- **Tipp-Indikator** — „schreibt gerade…" in Echtzeit über der Eingabeleiste, mit animierten Punkten
- **Nachrichten-Reaktionen** — per langem Druck Emoji-Reaktion wählen (👍❤️😂😮😢😡👎), Reaktionen erscheinen als Chips unter der Nachricht; erneutes Antippen entfernt die eigene Reaktion
- **Antworten auf Nachrichten** (Reply-Zitat in der Blase)
- Scrollbar an der rechten Seite
- Ältere Nachrichten automatisch nachladen beim Hochscrollen
- **Nachrichten anpinnen** — Admin/Moderator kann eine Nachricht anpinnen; wird als Banner oben im Chat angezeigt
- **Geplante Nachrichten** — Nachricht für einen späteren Zeitpunkt planen
- **Abstimmungen (Polls)** — Frage mit Optionen erstellen (Einzel- oder Mehrfachauswahl), optionale Anonymisierung; Abstimmungsergebnisse mit Wähler-Namen (bei nicht-anonymen Umfragen)

### Chat-Verwaltung (Admin & Moderator)
- Chats archivieren (werden read-only)
- Chats dauerhaft löschen (inkl. aller Nachrichten)
- Ausstehende Chat-Anfragen genehmigen oder ablehnen
- **Geplante Nachrichten** können auch von Admins/Moderatoren geplant werden, die nicht direkte Chat-Teilnehmer sind (z. B. Admin in Sheltered-Gruppen)

### Ungelesene Nachrichten
- Badge-Anzeige auf Chat-Kacheln
- Badge auf dem Chats-Tab mit Unterscheidung: rot (ausstehende Anfragen) / blau (ungelesene Nachrichten)
- Badge auf Organisations-Karten im Startbildschirm

### Push-Benachrichtigungen

#### Android (FCM)
- Benachrichtigung bei neuer Nachricht in genehmigten Chats
- Benachrichtigung bei neuer Chat-Anfrage (Guardian-Modus) — für Approver, Guardian und Angefragten
- Foreground & Background: native System-Benachrichtigung
- **Tap auf Benachrichtigung öffnet direkt den Chat** — auch wenn die App geschlossen war (robustes Deep-Link-Handling via Pending-Message-Pattern, kein fragiles Timeout mehr)
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
- **UI-Skalierung (Windows/Linux)** — 100 % bis 200 % in Schritten, einstellbar im Profil — optimiert für 4K-Monitore
- **„Über die App"-Dialog** — zeigt Versionsnummer, Open-Source-Lizenzen und GitHub-Link
- Organisations-Liste auf Desktop auf max. 640 px Breite begrenzt (linksbündig)
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
│   │   ├── models/          # Datenmodelle:
│   │   │                    #   AppUser, Organization, Conversation, Message,
│   │   │                    #   OrgMember, Poll, ClaimRequest, OrgInviteConsent, …
│   │   ├── router/          # GoRouter-Konfiguration
│   │   └── services/        # Firebase-Dienste:
│   │                        #   Auth, Chat, Organization, ParentClaim,
│   │                        #   Notification, DesktopNotification, TrayService
│   └── features/
│       ├── auth/            # Login-Screen, Provider
│       ├── chat/            # Chat-Screen, Provider
│       ├── organizations/   # Org-Liste, Org-Detail, Bulk-Import, Provider
│       ├── profile/         # Profil-Screen
│       └── relationships/   # Verknüpfungs-Screen (Eltern-Kind-Flow), Provider
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
                             #   onPollVote, onClaimRequest, onClaimConfirmed,
                             #   onChildOrgInvite, onParentConsent,
                             #   processMyInvitations, getCustomToken
```

---

## Firebase-Struktur (Firestore)

```
users/{uid}
  memberships[]
  isChild                       ← Kind-Konto (sperrt nicht-Kind-Rollen)
  fcmToken
  verifiedParentUids[]          ← Verifizierte Eltern (konto-übergreifend)
  verifiedChildUids[]           ← Verifizierte Kinder (konto-übergreifend)

organizations/{orgId}
  members/{uid}
    messageAlertInterval
    childAlertInterval
    lastMessageAlertAt
    lastChildAlertAt

conversations/{convId}
  pinnedMessageId               ← Angepinnte Nachricht
  pinnedMessageText
  typingUsers/{uid}             ← Timestamp (Tipp-Indikator)
  messages/{msgId}
    reactions/{uid}             ← Emoji-String (Nachrichten-Reaktionen)
  polls/{pollId}
    isAnonymous
    votes{}
  scheduledMessages/{smId}      ← Geplante Nachrichten

invitations/{inviteId}
invitationLookup/{email}
reports/{reportId}

claimRequests/{requestId}       ← Verknüpfungsanfragen Elternteil→Kind
  fromUid, fromName, fromEmail
  toUid, toEmail
  status                        ← pending | confirmed | rejected | cancelled
  createdAt, expiresAt

orgInviteConsents/{consentId}   ← Einwilligung der Eltern für Org-Einladungen
  childUid, childName
  orgId, orgName
  parentUids[]                  ← Alle verifizierten Eltern
  proposedGuardianUids[]
  status                        ← pending | approved | vetoed
  approvedBy, vetoedBy
```

---

## Cloud Functions

| Funktion | Trigger | Beschreibung |
|---|---|---|
| `onNewMessage` | Firestore Create | FCM-Push bei neuer Nachricht, Cooldown-Logik, Keyword-Monitoring |
| `onNewConversationRequest` | Firestore Create | Push an Approver, Guardian und Angefragten bei Chat-Anfrage |
| `onNewInvitation` | Firestore Create | Push an Guardians (Kind-Einladung) + E-Mail an nicht registrierte Nutzer |
| `onNewReport` | Firestore Create | Push an Admin + Moderatoren bei gemeldeter Nachricht |
| `onPollVote` | Firestore Update | Push an Ersteller bei neuer Abstimmung (nicht-anonym, nicht geschlossen) |
| `onClaimRequest` | Firestore Create | Push an Kind: „X möchte dein Elternteil sein" |
| `onClaimConfirmed` | Firestore Update | Aktualisiert `verifiedParentUids` / `verifiedChildUids` beidseitig; Push an Elternteil |
| `onChildOrgInvite` | Firestore Create | Push an alle verifizierten Eltern bei Org-Einladung des Kindes |
| `onParentConsent` | Firestore Update | Bei Genehmigung: Kind als `pending`-Mitglied hinzufügen; Push an einladenden Admin |
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
