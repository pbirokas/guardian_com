# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.

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
