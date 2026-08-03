# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.

---

## 2026-08-03

- **Google-Anmeldung entfernt.** Die Anmeldung läuft jetzt ausschließlich über E-Mail (Einmal-Code). Der „Mit Google anmelden"-Knopf und die Google-Verknüpfung im Profil sind entfallen; bestehende Konten melden sich mit derselben E-Mail-Adresse per Code an.
- **Weniger Google-Abhängigkeiten (Datenschutz).** Die App-Check-Komponente von Firebase wurde entfernt (wurde nicht erzwungen und ist mit dem Appwrite-Backend überflüssig).
- **Interne Aufräumarbeiten.** Doppelter Bild-Upload-Code zusammengeführt sowie wiederkehrende Bausteine (Avatar-Initialen, „im Browser öffnen") in gemeinsame Helfer ausgelagert. Keine sichtbare Änderung.

---

## 2026-08-02

- **Moderatoren können jetzt Gruppen-Chats erstellen.** Die Schaltfläche „Gruppe erstellen" stand bisher nur Administratoren zur Verfügung.
- **Beim Erstellen einer Gruppe kann man sich selbst hinzufügen.** Der eigene Account erscheint jetzt in der Personenauswahl und ist standardmäßig vorausgewählt — man muss sich nicht mehr nachträglich selbst zur Gruppe hinzufügen.
- **Mehrere Bilder auf einmal senden.** Beim Teilen von Bildern im Chat lassen sich jetzt mehrere Bilder gleichzeitig auswählen; sie werden nacheinander als einzelne Nachrichten gesendet.
- **Kein ungewolltes Abmelden mehr bei fehlender Verbindung.** Startet die App ohne Internet oder ist der Server nicht erreichbar, erscheint jetzt ein Hinweis „Keine Verbindung" statt der Anmeldemaske. Die Anmeldung bleibt erhalten und die App macht automatisch weiter, sobald wieder eine Verbindung besteht.
- **Löschen von Organisationen repariert.** Das Löschen einer Organisation brach mit einem internen Fehler ab; es funktioniert jetzt wieder zuverlässig.

---

## 2026-07-23

- **Weitere Abschottung: Meldungen und Abstimmungen.** Gemeldete Nachrichten sind jetzt ausschließlich für die Aufsicht (Admin/Moderatoren) der jeweiligen Organisation einsehbar (bisher technisch für jedes angemeldete Konto lesbar) — die Umstellung greift serverseitig sofort, ohne App-Update. Abstimmungen (Umfragen) sind nur noch für die Chat-Beteiligten zugänglich.

---

## 2026-07-22

- **Datenschutz: Chats und Nachrichten sind jetzt strikt abgeschottet.** Bisher waren Chat- und Nachrichten-Einträge technisch für jedes angemeldete Konto lesbar (die App zeigte zwar nur die eigenen Chats an, die Absicherung lag aber nur in der Anzeige). Jetzt kann jeden Chat und jede Nachricht ausschließlich lesen, wer wirklich beteiligt ist: die Chat-Teilnehmer, die Guardians der beteiligten Kinder sowie die Aufsicht (Admin/Moderatoren) der jeweiligen Organisation. Beim Beitritt zu einem Gruppenchat und bei einer späteren Beförderung zum Moderator wirkt der Zugriff auch rückwirkend auf die bestehende Historie.
- **Nachbesserung zur Chat-Abschottung:** Im ersten Wurf war die Aufsicht technisch falsch eingebunden, wodurch normale Mitglieder keine Nachrichten mehr senden oder Bilder hochladen konnten. Behoben — die Absicherung greift jetzt korrekt für alle Rollen, und die Moderation fremder Nachrichten durch Admins/Moderatoren bleibt erhalten.
- **Ungelesen-Zähler auf dem Chats-Tab korrigiert:** Der Zähler bezog fremde Chats mit ein, an denen man gar nicht beteiligt war, und zeigte dadurch zu hohe Werte (die sich nicht auf null zurücksetzen ließen). Er zählt jetzt nur noch die eigenen Chats mit ungelesenen Nachrichten. Offene Beitritts-/Chat-Anfragen (für Admins/Moderatoren) werden getrennt als eigenes rotes Zeichen dargestellt statt mit den Ungelesenen vermischt.

---

## 2026-07-20

- **Sehen, wer wie reagiert hat:** Ein Tipp auf eine Reaktion unter einer Nachricht öffnet jetzt eine Übersicht, die zeigt, welche Person mit welchem Emoji reagiert hat — mit Filter nach einzelnen Reaktionen. Zum Reagieren selbst weiterhin lange auf die Nachricht drücken (das kurze Antippen einer Reaktion setzt sie nicht mehr direkt).
- **Abgelaufene Ankündigungen und Termine werden wieder zuverlässig entfernt:** Die nächtliche Aufräum-Funktion brach bei einem internen Datenbankfehler komplett ab — abgelaufene Einträge blieben dadurch stehen. Sie räumt jetzt auch dann auf, wenn ein Teilschritt scheitert, und wiederholt kurzzeitige Serverfehler automatisch.
- **Wartungsläufe im Hintergrund laufen stabiler:** Mehrere fehlende Datenbank-Indexe ergänzt. Das nächtliche Aufräumen alter Nachrichten sowie das Löschen von Organisationen sind dadurch deutlich schneller und laufen nicht mehr in Zeitüberschreitungen.

---

## 2026-07-15

- **Update-Hinweis beim App-Start:** Die App prüft jetzt beim Start, ob eine neuere Version verfügbar ist. Ist eine neuere Version da, erscheint ein Hinweis („Update verfügbar"); liegt die installierte Version unter der Mindestversion, wird zum Update aufgefordert, bevor es weitergeht. Der Button führt Play-Store-Nutzer zum Store und Nutzer der direkt geladenen APK zur GitHub-Releases-Seite. Schlägt die Prüfung fehl (z. B. offline), läuft die App normal weiter.
- **Wartung: Löschen alter Nachrichten repariert:** Die tägliche Aufräum-Funktion brach mit einem internen Fehler ab; sie läuft jetzt wieder zuverlässig durch.

---

## 2026-07-10

- **Ungelesen-Status in Chats wieder zuverlässig:** In sehr aktiven Chats konnte der „Gelesen"-Status hängen bleiben (das Ungelesen-Zeichen verschwand nicht). Ursache war eine Rückkopplung zwischen App und Server, die sich bei einzelnen Chats aufschaukelte. Der Serverablauf wurde verschlankt und die App wiederholt fehlgeschlagene Versuche jetzt mit wachsendem Abstand statt im Dauerfeuer.

---

## 2026-06-27

- **App stürzt nicht mehr ab, wenn ein Profil- oder Gruppenbild nicht geladen werden kann:** Bisher konnte ein nicht erreichbares Bild (z. B. nach Ablauf des kostenlosen Firebase-Speicherzeitraums) die App zum Absturz bringen. Jetzt erscheinen in dem Fall überall einfach die Initialen bzw. das Gruppen-Symbol.
- **Profilbild-Upload migriert:** Profilbilder werden jetzt auf dem eigenen (EU-gehosteten) Speicher abgelegt statt bei Firebase. Bestehende alte Bilder werden zurückgesetzt — Nutzer können ihr Profilbild einfach neu hochladen.
- **Schlankere App:** Nicht mehr benötigte Firebase-Komponenten (Datenbank, Auth, Functions) wurden entfernt; die App ist dadurch kleiner und startet mit weniger Hintergrund-Diensten.

---

## 2026-06-24

- **Gelesen-Status (Mark-as-read) wieder zuverlässig:** Trotz der vorherigen Optimierung warf die Server-Funktion weiterhin täglich dutzende Timeout-Fehler. Sie sucht den vorhandenen Lese-Eintrag jetzt nicht mehr per Datenbankabfrage, sondern greift direkt darauf zu — das beseitigt die Timeouts vollständig und verhindert nebenbei doppelte Einträge.
- **Reaktions-Symbole auf schmalen Bildschirmen erreichbar:** Beim Reagieren auf eine Nachricht wurden auf manchen Smartphones nicht alle Emojis angezeigt (das letzte war abgeschnitten). Die Symbolleiste lässt sich jetzt horizontal scrollen, sodass alle Reaktionen erreichbar sind.

---

## 2026-06-19

- **Organisation löschen funktioniert wieder:** Admins konnten ihre Organisation nicht löschen (401-Fehler). Das Löschen läuft jetzt vollständig auf dem Server ab und bereinigt alle Mitglieder, Mitgliedschaften und die Organisation selbst — ohne Timeout-Fehler auch bei großen Orgs.
- **Gelöschte Organisation verschwindet sofort auf allen Geräten:** Nach dem Löschen einer Organisation wurde diese auf anderen Geräten weiterhin angezeigt bis zur App-Neustart. Die Echtzeit-Aktualisierung greift jetzt auch für Org-Deletes.
- **Mitgliederliste aktualisiert sich automatisch:** Neu beigetretene Mitglieder wurden in der Mitgliederliste und in Chats als „Unbekannt" angezeigt bis zur App-Neustart. Die Liste wird jetzt regelmäßig aktualisiert.
- **Teilen-Dialog erscheint sofort beim Kaltstart:** Wurde die App über die Android-Teilen-Funktion gestartet, erschien der Auswahl-Dialog erst nach Minimieren und Wiederherstellen der App. Der Dialog erscheint jetzt unmittelbar nach dem App-Start.
- **Mark-as-read zuverlässiger:** Die Cloud-Funktion zum Setzen des Gelesen-Status warf täglich bis zu 137 Fehlermeldungen (Timeouts und 500-Fehler). Lesevorgänge laufen jetzt parallel, und bei vorübergehenden Serverfehlern wird automatisch ein erneuter Versuch gestartet.
- **Datenschutz: Org-Daten werden bei Löschung vollständig entfernt:** Nachrichten, Umfragen, Ankündigungen, Einladungen und alle weiteren Inhalte einer Organisation waren nach deren Löschung noch für alle angemeldeten Nutzer lesbar. Beim Löschen einer Organisation werden jetzt alle zugehörigen Daten (Conversations, Nachrichten, Umfragen, Read-Receipts, Ankündigungen, Einladungen, Audit-Log, Berichte) und alle hochgeladenen Dateien (Bilder, Audio, Anhänge) serverseitig vollständig gelöscht.
- **Datenschutz: Einmalig-Bereinigung alter Daten möglich:** Ein neues Wartungs-Script (`appwrite/cleanup-orphaned-data.js`) findet und löscht Dokumente in der Datenbank, deren Organisation bereits gelöscht wurde — für alle Orgs die vor diesem Fix gelöscht wurden.

---

## 2026-06-13

- **Sicherheit: Rollenänderungen nur noch über Server möglich:** Alle privilegierten Mitglieder-Operationen (Rolle ändern, Mitglied entfernen, Kind bestätigen, Admin übertragen) laufen jetzt über eine gesicherte Cloud-Funktion. Dadurch können Nutzer ihre eigene Rolle nicht mehr direkt in der Datenbank manipulieren.
- **Sicherheit: Eigenständiges Verlassen einer Organisation datenkonsistent:** Das Verlassen einer Organisation wird jetzt ebenfalls serverseitig abgewickelt, sodass alle Verweise (Mitgliederliste, Mitgliedschafts-Cache) korrekt bereinigt werden.
- **Datenschutz: E-Mail-Adresse von Kinder-Accounts geschützt:** Die E-Mail-Adresse minderjähriger Nutzer wird nicht mehr in der Mitgliederliste gespeichert, die für alle Organisationsmitglieder lesbar ist.
- **Einladung bestehender Mitglieder repariert:** Ein Fehler verhinderte, dass ein Admin einen Nutzer erneut einladen konnte, nachdem dieser die Organisation verlassen hatte. Die Berechtigungsstruktur wurde grundlegend korrigiert.

---

## 2026-06-01

- **Uhrzeit-Anzeige in Nachrichten korrekt:** Nachrichten wurden in der falschen Zeitzone angezeigt (z. B. 21:28 statt 23:28 für Nutzer in UTC+2). Alle Zeitstempel werden jetzt korrekt in der lokalen Gerätezeit dargestellt.
- **App-Absturz beim Öffnen von Chats behoben:** Ein seltener Crash trat auf, wenn der Chat-Bildschirm noch geöffnet war während der Nutzer gleichzeitig ausgeloggt wurde. Die App bleibt in diesem Fall nun stabil.
- **Zeitstempel konsistent in UTC gespeichert:** Alle Datum-/Zeitangaben werden beim Speichern einheitlich in UTC mit Zeitzonenkennung abgelegt, um stille Fehler bei gemischten Schreibpfaden zu verhindern.

---

## 2026-05-31 (2)

- **Sicherheit: Ungelesen-Status manipulationssicher:** Das Setzen des eigenen „Gelesen"-Zeitstempels läuft jetzt über eine gesicherte Server-Funktion statt direkt in die Datenbank. Andere Nutzer können den eigenen Lesestatus nicht mehr von außen verändern.
- **Hilfsskript für Deployments robuster:** Das Script zum Setzen der Serverkonfiguration schlägt nicht mehr zufällig fehl wenn viele Funktionen gleichzeitig aktualisiert werden.

---

## 2026-05-31

- **Ungelesen-Badge zuverlässig:** Eigene Nachrichten wurden fälschlicherweise als ungelesen angezeigt; beim Öffnen eines Chats wurde der Badge manchmal erst nach mehreren Versuchen zurückgesetzt. Beides ist nun behoben.
- **Nachrichten erscheinen sofort nach dem Senden:** Eine Race Condition konnte dazu führen, dass eine gesendete Nachricht im Chat-Fenster nicht angezeigt wurde, obwohl sie erfolgreich übertragen wurde.
- **Nachrichtenreihenfolge bei verschiedenen Zeitzonen:** Nachrichten von Geräten in anderen Zeitzonen wurden falsch sortiert. Alle Zeitstempel werden nun einheitlich in UTC gespeichert.
- **Schaltflächen in der Organisations-Ansicht vollständig sichtbar:** Aktions-Schaltflächen am unteren Bildschirmrand (z. B. „Mitglieder vorschlagen") wurden auf Geräten mit Navigationsleiste abgeschnitten.

---

## 2026-05-26 (2)

- **Stabilere Echtzeit-Verbindung:** Ein Fehler führte dazu, dass die WebSocket-Verbindung für Echtzeit-Updates regelmäßig mit einem Verbindungsfehler abbricht. Alle Dienste teilen sich nun eine gemeinsame Verbindung, was Verbindungsabbrüche deutlich reduziert.

---

## 2026-05-26

- **Geplante Backend-Funktionen laufen wieder zuverlässig:** Zeitgesteuerte Aufgaben (z. B. Aufräumen abgelaufener Inhalte) schlugen bei automatischer Ausführung mit einem Verbindungsfehler fehl. Der Endpunkt wird nun korrekt konfiguriert.
- **Vergangene Events werden automatisch gelöscht:** Events auf der Organisations-Pinnwand, deren Datum abgelaufen ist, werden jetzt täglich automatisch entfernt — auch wenn kein explizites Ablaufdatum gesetzt wurde.

---

## 2026-05-22 (2)

- **Google Play Store Freigabe:** Nicht erforderliche Medien-Berechtigungen (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`) wurden entfernt. Die App nutzt den systemnativen Android Photo Picker, der keine expliziten Berechtigungen benötigt.

---

## 2026-05-22

- **Täglicher Fehler-Report per E-Mail:** Administratoren erhalten täglich um 07:00 Uhr eine automatische E-Mail mit einer Übersicht aller fehlgeschlagenen Backend-Funktionen der letzten 24 Stunden — inklusive Fehleranzahl und Fehlerauszug je Funktion.

---

## 2026-05-18 (3)

- **Passwort-Login entfernt:** Der "Mit Passwort anmelden"-Button wurde vom Login-Screen entfernt. Die Anmeldung erfolgt ausschließlich über Google oder E-Mail-Code.
- **Automatische Datenaktualisierung nach Verbindungsunterbrechung:** Wenn die App aus dem Hintergrund zurückkehrt oder das Netz nach einer Unterbrechung wiederhergestellt wird, werden alle Chats und Organisationen automatisch neu geladen.

---

## 2026-05-18 (2)

- **Eltern-Kind-Verknüpfung funktioniert wieder:** Die Bestätigung einer Verknüpfungsanfrage wurde durch einen internen Verbindungsfehler blockiert. Dieser Fehler wurde in allen Backend-Funktionen behoben.
- **"Meine Verknüpfungen" aktualisiert sich automatisch:** Nach einer bestätigten Verknüpfungsanfrage wurde die Ansicht erst nach einem Neustart der App aktualisiert. Die Seite lädt sich jetzt selbst neu.
- **Kontenzusammenführung berücksichtigt jetzt alle Verknüpfungen:** Beim Zusammenführen eines bestehenden Kontos mit dem Google-Login wurden bestehende Eltern-Kind-Verknüpfungen in anderen Konten nicht immer aktualisiert. Dieser Fehler wurde behoben.

---

## 2026-05-18

- **Google-Anmeldung:** Nutzer können sich jetzt direkt mit ihrem Google-Konto anmelden. Der Login erkennt automatisch, ob bereits ein Konto mit dieser E-Mail existiert, und verbindet beide Konten.
- **E-Mail-Code-Anmeldung:** Statt einem Anmeldelink wird jetzt ein 6-stelliger Code per E-Mail gesendet, der direkt in der App eingegeben werden kann — kein Wechsel in den Browser nötig.
- **Google-Konto verknüpfen:** Im Profil kann ein bestehendes Konto nachträglich mit Google verknüpft werden, um künftig per Google-Login einzusteigen.
- **Anmeldebildschirm überarbeitet:** Google, E-Mail-Code und Passwort sind jetzt als drei klare Optionen strukturiert.
- **Fehlerbehebung:** Ungültige OTP-Codes (unter 6 Stellen) zeigen jetzt eine verständliche Fehlermeldung statt stillschweigend abgebrochen zu werden.

---

## 2026-05-17

- **Chat zeigt neueste Nachrichten sofort:** Neue Nachrichten in einer Gruppe wurden in der Chat-Übersicht angezeigt, im Chat selbst jedoch erst nach manuellem Scrollen. Dieser Fehler wurde behoben.
- **App friert nicht mehr ein beim Schließen von Dialogen:** Das Bearbeiten einer Ankündigung, eines Termins oder eines Chat-Namens und anschließendes Wegtippen führte zu einem kompletten App-Freeze. Dieser Fehler wurde behoben.
- **Aktivitätszusammenfassung lädt zuverlässig:** Die Kindübersicht für Eltern schlug gelegentlich fehl (Timeout). Abfragen wurden optimiert und Ergebnisse werden 5 Minuten zwischengespeichert. Ein Refresh-Button ermöglicht manuelles Neu-Laden.
- **Server-Migration:** Appwrite läuft jetzt auf einem leistungsstärkeren Server (8 GB RAM, Helsinki) für stabileren Betrieb.

---

## 2026-05-12

- **Bilder werden nicht mehr unnötig komprimiert:** Bilder unter 2 MB werden jetzt unverändert hochgeladen. Nur größere Dateien werden schrittweise komprimiert, wobei erst die Qualität reduziert wird, bevor die Auflösung verringert wird.
- **RSVP-Rückmeldungen werden sofort angezeigt:** Die Stimmabgabe in der Termin-Detailansicht aktualisiert sich jetzt in Echtzeit, ohne das Modal schließen zu müssen.
- **RSVP-Berechtigung korrigiert:** Mitglieder konnten in bestimmten Fällen keine Rückmeldung abgeben (Fehler: fehlende Berechtigungen). Dieser Fehler wurde behoben.

---

## 2026-05-08 (4)

- **Termin-Ort öffnet jetzt Google Maps:** Der „In Maps öffnen"-Button verwendet auf allen Geräten die Google Maps-Website und funktioniert damit zuverlässig, auch ohne installierte Karten-App.
- **RSVP-Sichtbarkeit steuerbar:** Beim Erstellen oder Bearbeiten eines Termins können Admins/Moderatoren festlegen, ob die Teilnehmernamen für alle Mitglieder sichtbar sind oder nur für Admins/Moderatoren.
- **Sicherheit:** RSVP-Antworten können jetzt serverseitig nur noch für die eigene Benutzer-ID geschrieben werden – kein Überschreiben fremder Antworten mehr möglich.

---

## 2026-05-08 (3)

- **Gruppen-Events / Termine auf der Pinnwand:** Admins und Moderatoren können neben Ankündigungen jetzt auch Termine erstellen. Der neue Speed-Dial-FAB ("+") bietet die Auswahl zwischen „Ankündigung" und „Termin".
- Ein Termin enthält Datum, Uhrzeit, optionale Endzeit, Ort und optionale Beschreibung. Der Ort lässt sich direkt in der Maps-App öffnen.
- Alle Mitglieder (auch Kinder) können auf Termine mit „Zusagen", „Vorbehalt" oder „Absagen" antworten.
- Die Detailansicht zeigt RSVP-Zähler für alle; Admins/Moderatoren sehen auch Namen. Erziehungsberechtigte sehen die Antwort ihrer verknüpften Kinder.
- Termine können mit einem Klick in den Geräte-Kalender exportiert werden (Android: nativer Intent, Windows: ICS-Export).
- Vergangene Termine bleiben auf der Pinnwand archiviert und werden visuell als „Vergangener Termin" markiert.

---

## 2026-05-08 (2)

- Gruppen können jetzt ein eigenes Bild erhalten: Admins und Moderatoren finden im Menü „Gruppe bearbeiten" und können dort Name und Bild (aus der Galerie) in einem Dialog anpassen
- Das Gruppenbild erscheint als Avatar in der Chat-Übersicht und im Chat-Header
- Bild kann auch wieder entfernt werden

---

## 2026-05-08

- Aktivitätszusammenfassung für Kinder funktioniert jetzt korrekt: Nachrichten werden angezeigt und die Zeitstempel der letzten Aktivität stimmen

---

## 2026-05-07 (4)

- Eltern können in „Meine Verknüpfungen" für jedes verknüpfte Kind eine Aktivitätszusammenfassung abrufen (letzten 24 Stunden oder 7 Tage): Anzahl gesendeter und empfangener Nachrichten pro Organisation und Chat, jeweils mit Zeitstempel der letzten Aktivität

---

## 2026-05-07 (3)

- Geführte Tour für Organisations-Ansicht: Beim ersten Betreten einer Organisation blinkt das (?) auf — ein Tipp startet eine rollenbasierte Tour durch alle Tabs und Funktionen (Admins/Moderatoren sehen mehr Schritte als normale Mitglieder oder Guardians)
- Guardians erhalten in der Tour eine eigene Erklärung zum Tab "Kind-Aktivität"

---

## 2026-05-07 (2)

- Automatischer Löschzeitraum für Chat-Nachrichten: Admins können pro Organisation festlegen, wie lange Nachrichten aufbewahrt werden (30 bis 365 Tage, Standard 90 Tage) — ältere Nachrichten, Umfragen und Anhänge werden automatisch täglich bereinigt
- Der Aufbewahrungszeitraum ist für alle Mitglieder einer Organisation sichtbar (im Kopfbereich der Org-Ansicht)

---

## 2026-05-07

- Fix: Nach einem Admin-Rollenwechsel sieht der neue Admin nun alle Chats der Organisation — zuvor waren diese nach dem Rollenwechsel nicht mehr sichtbar
- Fix: Ausstehende Chat-Anfragen sind für den neuen Admin nach einem Rollenwechsel ebenfalls wieder sichtbar
- Fix: Chats als gelesen markieren funktioniert jetzt zuverlässig

---

## 2026-05-06 (2)

- Nachrichten können jetzt gelöscht werden: Jeder Nutzer kann eigene Nachrichten löschen — für alle anderen erscheint ein grauer Platzhalter
- Löschen rückgängig machen: Wer eine eigene Nachricht gelöscht hat, kann das jederzeit über langes Drücken auf die Nachricht rückgängig machen
- Admins und Moderatoren sehen den Inhalt gelöschter Nachrichten weiterhin (markiert mit einem roten Rahmen und Badge) — können sie aber nicht mehr bearbeiten, solange sie gelöscht sind
- Fix: Nachrichten in Einzel-Chats konnten nicht versendet werden (falscher Feldname in der Zugriffsregel)

---

## 2026-05-06

- Sicherheit: Absturz behoben, der auftreten konnte wenn man den Chat-Bildschirm in einem ungünstigen Moment verlässt
- Sicherheit: Token-Verifizierung bei der Desktop-Anmeldung per E-Mail-Link abgesichert — gefälschte Tokens werden jetzt korrekt abgewiesen
- Sicherheit: Zugriffsregeln für Chats, Nachrichten, Einladungen und Nutzerdaten präzisiert — nur noch erlaubte Feldänderungen werden akzeptiert
- Sicherheit: Dateiübertragung bricht jetzt sauber ab wenn eine Datei die 50-MB-Grenze überschreitet (statt Speicherfehler)
- Sicherheit: Moderatoren, deren Rolle entzogen wurde, können Konversationsstatus nicht mehr über einen veralteten Eintrag ändern
- Sicherheit: Einladungs-Lookup-Dokumente können nur noch von berechtigten Admins/Moderatoren der jeweiligen Organisation geschrieben werden

---

## 2026-05-05 (2)

- GIFs, die über die Tastatur eingefügt werden, werden jetzt animiert angezeigt (vorher: statisches Bild)
- GIF-Links (z. B. von Tenor) werden ebenfalls animiert dargestellt

---

## 2026-05-05

- Chatliste zeigt Gruppen und Einzel-Chats jetzt in getrennten Abschnitten mit Überschriften
- Hilfe-Symbol direkt in der AppBar sichtbar (statt im 3-Punkte-Menü) — für alle Rollen erreichbar
- 3-Punkte-Menü in der Org-Übersicht wird nur noch für Admins und Moderatoren angezeigt
- Überwachte Chats (Guardian-Ansicht) werden jetzt effizienter geladen — weniger Datenbankabfragen

---

### 2026-05-04 — Einheitlicher Org-Modus, Adressbuch & E-Mail-Datenschutz

#### Neue Funktionen

**Einheitlicher Org-Modus (Guardian + Sheltered vereint)**
- Jede Organisation unterstützt jetzt beide Chat-Typen: Mitglieder können Chat-Anfragen stellen (wie im früheren Guardian-Modus) *und* Admins können Gruppen anlegen (wie im früheren Sheltered-Modus)
- Der bisherige `ChatMode`-Schalter (Guardian / Sheltered) entfällt bei der Org-Erstellung und im Bearbeiten-Dialog vollständig
- Abstimmungen (Polls) sind in allen Gruppenkonversationen verfügbar — nicht mehr auf Sheltered-Gruppen beschränkt
- Bestehende Orgs in Firestore sind ohne Migration lauffähig; das `chatMode`-Feld wird ignoriert

**Adressbuch beim Einladen**
- Mitglieder einladen öffnet jetzt zwei Tabs: „E-Mail" (wie bisher) und „Adressbuch"
- Das Adressbuch aggregiert aktive Mitglieder aus allen anderen Orgs des Admins/Moderators, dedupliziert nach UID und schließt aktuelle Org-Mitglieder sowie das eigene Konto aus
- Pro Person kann direkt eine Rolle und (bei Kind-Konten) ein Guardian ausgewählt werden — ohne erneute E-Mail-Eingabe

**E-Mail-Datenschutz**
- Neues Schalter „E-Mail-Adresse verbergen" in den Datenschutz-Einstellungen (Profil → Datenschutz)
- Ist der Schalter aktiv, wird die E-Mail-Adresse in der Mitgliederliste durch ein Datenschutz-Icon ersetzt
- Die Einstellung wird auf alle Mitglieds-Dokumente des Nutzers synchron übertragen (`hideEmail`-Feld in `users` und `members`)
- Neuer Menüpunkt „Datenschutz" in der Profil-Übersicht

#### Fehlerbehebungen

| Bereich | Änderung |
|---|---|
| **PERMISSION_DENIED: Moderator-Konversationen** | `watchShelteredModeratorConversations` filterte bisher nur nach `orgAdminUid` — orgsübergreifende Ergebnisse verursachten Firestore-PERMISSION_DENIED. Filter um `orgId` ergänzt; neuer Composite-Index `(orgId, orgAdminUid)` in `firestore.indexes.json` |
| **PERMISSION_DENIED: Adressbuch** | Veraltete Mitgliedschafts-Einträge im User-Dokument konnten auf Orgs zeigen, in denen kein Mitglieds-Dokument mehr existiert. Per-Org-Abfrage ist jetzt in try/catch gekapselt, fehlerhafte Orgs werden übersprungen |

---

### 2026-05-01 — Share-Target: Org-Gruppierung, Chat-Direktsenden & Tastatur-GIF

#### Neue Funktionen

**GIF-Einfügen über die Tastatur**
- Das Chat-Textfeld deklariert jetzt via `ContentInsertionConfiguration` die unterstützten MIME-Typen (`image/gif`, `image/png`, `image/jpeg`, `image/webp`) gegenüber Android
- Gboard und andere Tastaturen können GIFs direkt in den Chat einfügen, ohne den Share-Dialog zu öffnen
- Die Bytes kommen entweder direkt aus dem Tastatur-Callback oder werden via `ShareService.readUri()` nachgeladen

#### Fehlerbehebungen & Verbesserungen

**Share-Target: Direktsenden bei offenem Chat**
- Wird ein Inhalt geteilt (z. B. GIF per Tastatur) während ein Chat bereits geöffnet ist, wird er direkt in diesen Chat gesendet — der Picker erscheint nicht
- Implementiert via `router.routeInformationProvider.value.uri.path`-Prüfung in `_ShareListener`

**Share-Picker: Chats nach Organisation gruppiert**
- Konversationen werden jetzt nach Org unterteilt: ein farbiger Org-Header (Icon + Name) gefolgt von den zugehörigen Chats mit leichtem Einzug
- Orgs ohne genehmigte Chats erscheinen nicht in der Liste

---

### 2026-05-01 — Emoji-Picker, GIF-Rendering, AppBar-Vereinfachung & Share-Target

#### Neue Funktionen

**Emoji-Picker im Chat**
- Neuer 😊-Button in der Chat-Eingabeleiste öffnet einen Emoji-Picker direkt unterhalb der Eingabe
- Wechselt automatisch zwischen System-Tastatur (⌨️) und Emoji-Picker
- Schließt sich beim Tippen in das Textfeld automatisch

**GIF-Rendering**
- Geteilte oder eingefügte GIF-URLs werden im Chat direkt als animiertes Bild angezeigt (via `CachedNetworkImage`)
- Fehlerhafte oder nicht ladbare URLs fallen auf anklickbaren Linktext zurück

**AppBar-Vereinfachung im Chat**
- Alle Chat-Aktionen (Suche, Umbenennen, Mitglieder, Mitglied hinzufügen) wurden in ein einziges `⋮`-Menü zusammengefasst
- Die AppBar zeigt nun nur noch `?` (Hilfe) und `⋮` (Aktionen) statt mehrerer Einzelicons

**Share-Target (Android)**
- Die App registriert sich als Share-Ziel für Text, Bilder und Dateien
- Beim Teilen aus einer anderen App öffnet sich ein Bottom Sheet mit der Liste aller eigenen genehmigten Chats
- Direktchats zeigen den Display-Namen des Gesprächspartners (Firestore-Lookup, gecacht)
- Nach dem Senden wird direkt in den Ziel-Chat navigiert
- Unterstützte Typen: `text/plain`, `image/*`, `*/*` (Einzel- und Mehrfachauswahl)
- Nur Chats aus Organisationen, in denen der Nutzer aktuell Mitglied ist, werden angezeigt

#### Technische Details
- Neues `MethodChannel com.guardianapp.guardian_app/share` in `MainActivity.kt`: `getSharedData()` und `readUri()` für nativen Datei-Zugriff
- `ShareService`, `pendingShareProvider`, `SharePickerSheet` als neue Flutter-Schicht
- `_ShareListener`-Widget innerhalb des `MaterialApp.router`-Builders löst Navigator-Kontext-Fehler
- `userDisplayNameProvider` (FutureProvider.family) für gecachte UID→Name-Auflösung

---

### 2026-04-30 — Abstimmungs-Verbesserungen & Benachrichtigungen aufräumen

#### Neue Funktionen

**Abstimmungs-Details für alle sichtbar**
- Der „Abstimmungs-Details"-Button wird jetzt für alle Teilnehmer angezeigt, unabhängig davon ob sie bereits abgestimmt haben
- Zuvor war der Button nur nach eigener Stimmabgabe sichtbar

**Einfachauswahl: Stimme wieder entfernbar**
- Bei Umfragen mit Einfachauswahl kann die eigene Stimme durch erneutes Antippen der gewählten Option wieder zurückgezogen werden — gleiches Verhalten wie bei Mehrfachauswahl

**Benachrichtigungen beim App-Start automatisch schließen (Android)**
- Wechselt der Nutzer in die App, werden alle noch offenen Push-Benachrichtigungen der App automatisch aus der Statusleiste entfernt
- Technisch: `WidgetsBindingObserver` in `main.dart` ruft bei `AppLifecycleState.resumed` eine neue `NotificationService.clearAll()`-Methode auf, die per Method-Channel `NotificationManager.cancelAll()` auf Android aufruft

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
