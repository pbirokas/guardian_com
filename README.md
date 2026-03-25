# Guardian App

Eine Flutter-App für sichere, überwachte Kommunikation zwischen Kindern, Erziehungsberechtigten und Organisationen.

## Technologie

- **Frontend:** Flutter 3.x (Dart)
- **Backend:** Firebase (Auth, Firestore, Cloud Functions, FCM)
- **State Management:** Riverpod
- **Navigation:** GoRouter

---

## Funktionsübersicht

### Authentifizierung
- E-Mail/Passwort Registrierung und Login
- Automatische Benutzerprofil-Erstellung bei der ersten Anmeldung

### Organisationen
- Organisationen erstellen mit Name, Kategorie (Familie, Freunde, Schule, Vereine, Sonstiges) und Chat-Modus
- Mitglieder per E-Mail einladen mit Rollenzuweisung
- Organisation bearbeiten (Name, Kategorie, Chat-Modus)
- Organisation archivieren (read-only) oder dauerhaft löschen

#### Rollen
| Rolle | Beschreibung |
|---|---|
| **Admin** | Volle Kontrolle über die Organisation |
| **Moderator** | Kann Chats einsehen, genehmigen und verwalten |
| **Mitglied** | Normales Mitglied, kann Chats anfordern |
| **Kind** | Eingeschränktes Mitglied, benötigt einen Guardian |
| **Guardian** | Erziehungsberechtigter eines Kindes |

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

### Guardian-Kind-Beziehung
- Kind-Mitglieder werden einem Guardian zugewiesen
- Guardian muss die Einladung seines Kindes bestätigen
- Guardian-Kind-Beziehung wird in der Mitgliederliste mit Symbol angezeigt
- Guardian hat Lesezugriff auf die Chats seines Kindes

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
- Foreground: SnackBar mit „Öffnen"-Button
- Background/Beendet: native System-Benachrichtigung
- Tap auf Benachrichtigung öffnet direkt den Chat

### Keyword-Monitoring
- Admin kann pro Organisation eine Liste von Schlüsselwörtern pflegen
- Bei Auftreten eines Keywords in einem Chat werden Guardians, Moderatoren und der Admin per Push-Benachrichtigung informiert
- Verwaltung über das 🔍-Icon in der AppBar der Organisation

### Guardian-Aktivitäts-Benachrichtigungen
- Guardian wird benachrichtigt, wenn sein Kind eine Nachricht sendet oder empfängt
- Benachrichtigungsintervall einstellbar (pro Guardian, pro Organisation):
  - Jede Nachricht
  - Max. 1x pro Stunde *(Standard)*
  - Max. 1x pro Tag
  - Nie
- Einstellung durch Antippen der eigenen Mitgliedskachel

### Nachrichten melden
- Mitglieder können fremde Nachrichten per Langer Druck melden
- Admin und Moderatoren erhalten eine Push-Benachrichtigung
- Meldungen sind im **Meldungen-Tab** der Organisation einsehbar
- Badge mit Anzahl ausstehender Meldungen auf dem Tab
- Admin/Moderator kann:
  - Meldung als geprüft markieren
  - Die gemeldete Nachricht direkt löschen
  - Direkt in den betreffenden Chat springen

---

## Projektstruktur

```
guardian_app/
├── lib/
│   ├── core/
│   │   ├── models/          # Datenmodelle (User, Organization, Conversation, ...)
│   │   └── services/        # Firebase-Dienste (Auth, Chat, Organization, Notification)
│   └── features/
│       ├── chat/            # Chat-Screen, Provider
│       ├── organizations/   # Org-Liste, Org-Detail, Provider
│       └── auth/            # Login, Registrierung
├── android/
└── windows/

functions/
└── index.js                 # Firebase Cloud Functions (Benachrichtigungen, Keyword-Check)
```

---

## Firebase-Struktur

```
users/{uid}
organizations/{orgId}
  members/{uid}
conversations/{convId}
  messages/{msgId}
reports/{reportId}
```
