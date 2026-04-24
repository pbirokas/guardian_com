# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.

---

### 2026-04-24 — Chat umbenennen, Chat-Start-Logik, Mitglieder-Aktionen & Rollensperre

#### Neue Funktionen

**Gruppen umbenennen (Admin & Moderator)**
- „Umbenennen"-Option im `⋮`-Menü der Chat-Kachel für Gruppenkonversationen
- Edit-Icon (✏️) in der AppBar des Chat-Screens — nur für Admin und Moderatoren sichtbar
- Der neue Name wird in Echtzeit in Kachel und AppBar übernommen

**Persönlicher Chatname für Direktnachrichten**
- Jeder Teilnehmer kann für sich einen eigenen Anzeigenamen für einen 1-zu-1-Chat vergeben
- Erreichbar über das Edit-Icon in der AppBar oder über „Eigener Chatname" im `⋮`-Menü
- Nutzer ohne `⋮`-Zugang (Nicht-Admin/Mod) können per Long-Press auf die Chat-Kachel umbenennen
- Name ist nur für den jeweiligen Nutzer sichtbar — gespeichert im Feld `personalNames` der Konversation
- Kein persönlicher Name gesetzt → Originalname des Gesprächspartners wird angezeigt

#### Fehlerbehebungen

| Bereich | Änderung |
|---|---|
| **TextEditingController disposed zu früh** | `controller.dispose()` in Rename-Dialogen entfernt — lokal erstellte Controller dürfen während der Dialog-Schließ-Animation nicht manuell disposed werden |

---

### 2026-04-24 — Chat-Start-Logik, Mitglieder-Aktionen & Rollensperre

#### Neue Funktionen

**Typ-Indikator in überwachten Chats**
- Jede Kachel in der „Überwachte Chats"-Liste zeigt ein kleines „Gruppe" oder „Direktnachricht"-Label mit passendem Icon, damit Gruppen- und 1-zu-1-Chats klar unterscheidbar sind

#### Fehlerbehebungen

| Bereich | Änderung |
|---|---|
| **Chat Starten navigiert in Gruppenkonversation** | `createApprovedConversation` ignoriert jetzt bestehende Gruppenkonversationen beim Suchen nach einem vorhandenen Chat — ein neuer 1-zu-1-Chat wird immer separat angelegt |
| **„No action available" bei Mitgliedern** | `⋮`-Button wird nur noch angezeigt wenn tatsächlich Aktionen verfügbar sind; reguläre Mitglieder ohne Aktionen sehen den Button gar nicht mehr |
| **Rolle ändern für Kinder (Exception)** | „Rolle ändern" und „Admin übertragen" werden für Kind-Mitglieder komplett ausgeblendet |
| **Rolle ändern blendet „Kind" für Guardians aus** | Mitglieder, die Guardian eines Kindes sind, dürfen ihre Rolle ändern (z. B. zu Moderator), erhalten aber „Kind" nicht als Zieloption angeboten |

---

### 2026-04-23 — FCM-Zuverlässigkeit, Chat-Info & Überwachungs-Korrekturen

#### Neue Funktionen

**Chat-Info-Blatt für überwachte Chats (ⓘ)**
- Guardians, Eltern, Admins und Moderatoren sehen in der Liste der überwachten Chats ein ⓘ-Icon
- Antippen öffnet ein `DraggableScrollableSheet` mit zwei Sektionen: „Teilnehmer" und „Supervisoren"
- Teilnehmer werden aus `conv.participantUids` gelesen; Supervisoren aus `guardianUids` plus aktiven Admin-/Mod-Mitgliedern ohne direkten Chat-Zugriff

#### Fehlerbehebungen

| Bereich | Änderung |
|---|---|
| **FCM-Benachrichtigungen (Doze-Modus)** | `android.priority: 'high'` auf Nachrichten-Ebene gesetzt — Android ignorierte Benachrichtigungen nach einigen Stunden, weil der Doze-Modus die FCM-Verbindung unterbrach |
| **FCM-Token beim Kaltstart** | `ref.listen` auf `authStateProvider` in `main.dart` erneuert den FCM-Token nach dem Login, sodass bereits angemeldete Nutzer nach App-Neustart zuverlässig Benachrichtigungen erhalten |
| **Falsche Namen in überwachten Chats** | Für Supervisoren wird jetzt das Kind in `participantUids` per `OrgRole.child`-Filter gesucht — vorher wurde gelegentlich der Name des zweiten Guardians statt des Kindes angezeigt |
| **PERMISSION_DENIED beim Öffnen überwachter Chats** | Firestore-Regel für Conversations erweitert: neue Hilfsfunktion `canAccessConv()` prüft zusätzlich `guardianUids` und `isAdminOrMod(orgId)` (dynamisch) — `canApproveUids` war veraltet |
| **PERMISSION_DENIED für Supervisor im Chat** | `ChatScreen` prüft `_isParticipant`; Supervisoren (nicht in `participantUids`) dürfen lesen, aber nicht schreiben — schützt `_markRead()` und `_onTextChanged()` |
| **Admin sieht eigene Chats unter „Überwachte Chats"** | `approved`- und `archivedConvs`-Listen filtern jetzt auf `participantUids.contains(currentUid)` — Chats ohne eigene Teilnahme fließen korrekt in `allSupervisorConvs` |
| **Nachträglich hinzugefügter Guardian sieht keine Kinder-Chats** | Neue Cloud Function `onMemberGuardiansChanged` reagiert auf Änderungen an `members/{memberId}.guardianUids` und propagiert Ergänzungen/Entfernungen per `FieldValue.arrayUnion/arrayRemove` in alle betroffenen Conversations — serverseitig via Admin SDK, ohne Firestore-Regeln |
| **PERMISSION_DENIED bei Moderator entfernt Guardian** | Clientseitige Conversation-Abfrage in `updateGuardians()` entfernt; Propagation erfolgt ausschließlich über die Cloud Function — Moderatoren dürfen keine org-weiten Queries ausführen |

#### Infrastruktur

- `firestore.indexes.json`: fehlende Compound-Indizes ergänzt (`conversations` — `orgId` + `participantUids`, `orgInviteConsents`, `memberSuggestions`, `claimRequests` ×2, `scheduledMessages`)

---

### 2026-04-17 — Akku-Optimierung & Spenden-Einstellung

#### Neue Funktionen

**Akku-Optimierungs-Hinweis (Android)**
- Beim App-Start wird geprüft, ob Android die Akku-Optimierung für Guardian Com aktiv hat
- Falls ja, erscheint ein einmaliger Dialog mit Erklärung und direktem „Jetzt einrichten"-Button, der den Android-Systemdialog öffnet
- „Vielleicht später" schließt den Dialog, er erscheint beim nächsten Start erneut
- „Nicht mehr fragen" unterdrückt den Hinweis dauerhaft
- Technisch: eigener Platform-Channel (`com.guardianapp.guardian_app/battery`) in `MainActivity.kt`, kein zusätzliches Package nötig

**Spenden-Aufruf deaktivierbar**
- Neuer Button „Nicht mehr anzeigen" im wöchentlichen Spenden-Dialog
- Wird er gedrückt, erscheint der Dialog dauerhaft nicht mehr (gespeichert in SharedPreferences)

---

### 2026-04-16 — Ablaufdatum für Umfragen & Chat-Übersicht verbessert

#### Neue Funktionen

**Ablaufdatum für Umfragen (Sheltered-Gruppen)**
- Beim Erstellen einer Umfrage kann optional ein Ablaufdatum mit Uhrzeit gesetzt werden
- Abgelaufene Umfragen werden automatisch als geschlossen angezeigt (kein Abstimmen mehr möglich), ohne dass ein Admin manuell eingreifen muss
- Das Ablaufdatum wird in der Umfragekachel angezeigt, solange die Umfrage noch offen ist
- Neue Cloud Function `cleanupExpiredPolls` schließt täglich um 03:05 Uhr alle Umfragen mit überschrittenem Ablaufdatum (setzt `isClosed: true`)

**Verbesserte Chat-Übersicht (Guardian-Modus)**
- Doppelte Einträge entfernt: Chats, in denen man selbst Mitglied ist, erscheinen nicht mehr zusätzlich unter „Überwachte Chats"
- Sektion „Überwachte Chats" ist jetzt ein- und ausklappbar (Tipp auf den Abschnittstitel)

---

### 2026-04-15 — Reaktionen auf Ankündigungen, Chat-Systemnachrichten & Änderungsprotokoll

#### Neue Funktionen

**Emoji-Reaktionen auf Pinnwand-Ankündigungen**
- Mitglieder können Ankündigungen per langem Druck mit einem von 7 Emojis reagieren (👍❤️😂😮😢😡👎)
- Reaktions-Chips erscheinen unterhalb des Inhalts; eigene Reaktion ist farblich markiert
- Erneutes Antippen eines Chips entfernt die eigene Reaktion (Toggle)
- Firestore-Sicherheitsregel angepasst: Mitglieder dürfen ausschließlich das `reactions`-Feld aktualisieren

**System-Nachrichten in Sheltered-Gruppen-Chats**
- Beim Hinzufügen oder Entfernen eines Mitglieds aus einem Gruppen-Chat wird automatisch eine zentrierte, graue Info-Zeile in den Chatverlauf geschrieben
- Neues `type`-Feld im `Message`-Modell (`'user'` / `'system'`) mit `systemEvent`, `systemActorName`, `systemTargetName`
- System-Nachrichten werden in der `_MessageBubble` ohne Blase, Avatar oder Aktionsmenü gerendert

**Änderungsprotokoll für Organisationen**
- Neuer Menüpunkt „Änderungsprotokoll" im `⋮`-Menü des Org-Details (sichtbar für Admins & Moderatoren)
- Protokolliert werden: Einladung verschickt, Mitglied bestätigt, Mitglied entfernt, Einstellungen geändert, Rolle geändert, Admin-Rolle übertragen, Schlüsselwörter aktualisiert
- Jeder Eintrag zeigt Aktion, beteiligte Person(en), Ausführer und Zeitstempel
- Einträge sind unveränderlich (keine Update/Delete-Berechtigung in den Sicherheitsregeln)
- Neue Firestore-Subcollection `auditLog` mit eigener Sicherheitsregel

**Chat-Schriftgröße einstellbar**
- Neue Einstellung im Profil: Chat-Schriftgröße (Klein / Mittel / Groß / Sehr groß)
- Einstellung wird über `chatFontSizeProvider` mit `SharedPreferences` persistiert

#### Fehlerbehebungen

| Bereich | Änderung |
|---|---|
| **Abstimmungs-Trefferzone** | Stimmenanzahl bei Umfragen als `InkWell` mit Padding — Trefferzone war zuvor zu klein |
| **Ankündigungs-Reaktionen: Permission Denied** | Firestore-Regel für `announcements` erweitert: alle Org-Mitglieder dürfen ausschließlich `reactions` schreiben |
| **Änderungsprotokoll: Permission Denied** | Neue Firestore-Regel für `auditLog`-Subcollection: Mitglieder dürfen erstellen, Admins/Mods dürfen lesen |

---

### 2026-04-13 — In-App-Hilfe, UI-Fixes & Eltern-Kind-Stabilisierung

#### Neue Funktionen

**In-App-Hilfe-System (`HelpSheet`)**
- Neues wiederverwendbares Widget `HelpSheet` / `HelpTopic` in `core/widgets/help_sheet.dart`
- Kontextsensitiver `?`-Hilfe-Button auf allen wichtigen Screens: Organisations-Übersicht, Org-Detail, Chat, Meine Verknüpfungen, Massenimport, Profil
- Schlüsselwörter-Dialog erhält inline Hilfe-Button im Titelbereich
- Alle Hilfetexte vollständig zweisprachig (Deutsch / Englisch)
- Themen passen sich der Nutzerrolle an (z. B. Admin-Tipps nur für Admins)

**Schritt-für-Schritt-Tour (Organisations-Übersicht)**
- Interaktive Tour mit `showcaseview` hebt Profil-Avatar, Verknüpfungen-Symbol, erste Org-Karte und FAB hervor
- Startet über den `?`-Button im HelpSheet; dynamisch je nach Kontostand

**Org-Detail AppBar aufgeräumt**
- Alle Aktionen (Hilfe, Schlüsselwörter, Bearbeiten) in ein `⋮`-Overflow-Menü zusammengefasst
- Nur noch Glocken-Symbol + `⋮` in der AppBar → mehr Platz für den Org-Namen

**Pinnwand-Hilfe erweitert**
- Neuer Admin/Mod-only Topic „Ankündigungen erstellen & verwalten" (inkl. Ablaufdatum)

**Mitglieder-Tab-Hilfe erweitert**
- Neuer Topic „Einladen, vorschlagen & importieren" erklärt rollenspezifische Workflows (Admin, Mitglied, Kind, Elternteil)

#### Fehlerbehebungen & Verbesserungen

| Bereich | Änderung |
|---|---|
| **Cloud Function `onClaimConfirmed`** | try/catch mit `console.error` + `throw` hinzugefügt (war bisher lautlos fehlgeschlagen); setzt `isChild: true` und stuft Kind-Rollen in allen Orgs auf `child` herab |
| **AppBar-Overflow (Org-Detail)** | `Row`-Overflow durch `Flexible` + `TextOverflow.ellipsis` auf Subtitle-Labels behoben |
| **HelpSheet-Hintergrund** | `DraggableScrollableSheet`-Inhalt in `Material`-Widget eingebettet — Sheet war transparent |
| **Kategorien-Übersetzung** | `OrgTag.localizedLabel(AppLocalizations l)` ergänzt; Labels sind jetzt vollständig übersetzt (DE/EN) |
| **Chat-Modus aus Bearbeiten-Dialog entfernt** | Chat-Modus einer Organisation kann nach Erstellung nicht mehr geändert werden |
| **Konto-Löschung blockiert** | Löschen ist gesperrt, solange verifizierte Eltern- oder Kind-Verbindungen bestehen |
| **Kind-Konto: „Meine Kinder" ausgeblendet** | Nutzer mit `isChild: true` sehen den Abschnitt nicht mehr |
| **„Meine Eltern" bedingt angezeigt** | Abschnitt erscheint nur, wenn mindestens ein verifizierter Elternteil vorhanden ist |
| **Datenschutz & Lösch-Seite** | `privacy_policy.html` und `delete_account.html` um Eltern-Kind-Verknüpfungs-Abschnitt erweitert |
| **Neuer ARB-Schlüssel `close`** | Für semantisch korrekte Schliessen-Buttons in reinen Info-Dialogen |
