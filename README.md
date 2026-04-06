# Guardian App

Eine Flutter-App für sichere, überwachte Kommunikation zwischen Kindern, Erziehungsberechtigten und Organisationen.

## Technologie

| Bereich | Stack |
|---|---|
| **Frontend** | Flutter 3.x (Dart) |
| **Backend** | Firebase (Auth, Firestore, Storage, FCM) |
| **State Management** | Riverpod 3.x |
| **Navigation** | GoRouter |
| **Authentifizierung** | Google Sign-In |

---

## Funktionsübersicht

### Authentifizierung
- Google Sign-In
- Automatische Benutzerprofil-Erstellung bei der ersten Anmeldung
- Pre-Registrierung: Einladungen werden beim ersten Login automatisch verarbeitet, sodass Rollen sofort aktiv sind

### Organisationen
- Organisationen erstellen mit Name, Kategorie (Familie, Freunde, Schule, Vereine, Sonstiges) und Chat-Modus
- Mitglieder per E-Mail einladen mit Rollenzuweisung
- **Pre-Registrierung:** Einladung für noch nicht registrierte Nutzer — beim ersten Login erhalten sie automatisch die richtige Rolle
- Organisation bearbeiten (Name, Kategorie, Chat-Modus)
- Organisation archivieren (read-only) oder dauerhaft löschen
- Admin-Rolle auf ein anderes Mitglied übertragen
- Aus einer Organisation austreten (nicht für Admins)

#### Rollen
| Rolle | Beschreibung |
|---|---|
| **Admin** | Volle Kontrolle über die Organisation |
| **Moderator** | Kann Chats einsehen, genehmigen und verwalten |
| **Mitglied** | Normales Mitglied, kann Chats anfordern |
| **Kind** | Eingeschränktes Mitglied, benötigt einen Guardian |

### Chat-Modi

#### Guardian-Modus
- Mitglieder können Chats mit anderen Mitgliedern anfordern
- Admin oder Moderator genehmigt oder lehnt Anfragen ab
- Genehmigte Chats sind für den Guardian des Kindes sichtbar

#### Sheltered-Modus
- Admin legt vorab fest, wer mit wem kommunizieren darf
- Nur freigegebene Verbindungen sind möglich
- Moderatoren haben Einsicht in alle Chats der Organisation
- Gruppen-Chats möglich
- **Abstimmungen/Umfragen** können von Teilnehmern gestartet werden (Einzel- oder Mehrfachauswahl)

### Guardian-Kind-Beziehung
- Kind-Mitglieder werden einem Guardian zugewiesen
- Guardian muss die Einladung seines Kindes bestätigen
- Guardian-Kind-Beziehung wird in der Mitgliederliste mit Symbol angezeigt
- Guardian hat Lesezugriff auf die Chats seines Kindes

### Chat-Funktionen
- Textnachrichten senden
- **Eigene Nachrichten bearbeiten** (per Langer Druck → Bearbeiten)
- Bilder senden (JPEG, max. 2 MB, automatisch komprimiert)
- **Bild antippen** öffnet Vollbild-Ansicht mit Pinch-to-Zoom
- Sprachnachrichten aufnehmen und abspielen (AAC, max. 10 MB)
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

### Push-Benachrichtigungen (FCM)
- Benachrichtigung bei neuer Nachricht in genehmigten Chats
- Foreground & Background: native System-Benachrichtigung
- Tap auf Benachrichtigung öffnet direkt den Chat

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
- Badge mit Anzahl ausstehender Meldungen auf dem Tab
- Admin/Moderator kann Meldung prüfen, Nachricht löschen oder direkt in den Chat springen

### Sonstiges
- Dark / Light Mode
- Spenden-Popup (Ko-fi / PayPal) — erscheint max. 1× pro Woche, nicht für Kinder

---

## Projektstruktur

```
guardian_app/
├── lib/
│   ├── core/
│   │   ├── models/          # Datenmodelle (AppUser, Organization, Conversation, Message, Poll, …)
│   │   ├── router/          # GoRouter-Konfiguration
│   │   └── services/        # Firebase-Dienste (Auth, Chat, Organization, Notification)
│   └── features/
│       ├── auth/            # Login-Screen, Provider
│       ├── chat/            # Chat-Screen, Provider
│       └── organizations/   # Org-Liste, Org-Detail, Provider
├── android/
└── windows/

firestore.rules              # Firestore Security Rules
storage.rules                # Firebase Storage Security Rules
firebase.json                # Firebase-Konfiguration
functions/
└── index.js                 # Firebase Cloud Functions (Benachrichtigungen, Keyword-Check)
```

---

## Firebase-Struktur (Firestore)

```
users/{uid}
  memberships[]
  isChild

organizations/{orgId}
  members/{uid}

conversations/{convId}
  messages/{msgId}
  polls/{pollId}

invitations/{inviteId}
reports/{reportId}
```

---

## Setup

1. Firebase-Projekt erstellen und `google-services.json` (Android) / `GoogleService-Info.plist` (iOS) einbinden
2. `lib/firebase_options.dart` über FlutterFire CLI generieren
3. `flutter pub get`
4. `firebase deploy --only firestore:rules,storage` — Sicherheitsregeln deployen
