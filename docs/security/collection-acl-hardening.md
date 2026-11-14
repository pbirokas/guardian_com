# Härtung der Collection-Level-Berechtigungen (Appwrite-DB `guardian`)

Stand: 2026-11-14 · Branch `security/collection-acls` · **Nichts davon ist live** — jede Server-Änderung braucht das OK des Owners.

## 1. Problem

Appwrite wertet Rechte **additiv** aus: Collection-read **oder** Dokument-read genügt.
Live (geprüft 2026-11-14 per `fix-permissions.js` Dry-Run):

| Collection | Collection-Rechte live | Folge |
|---|---|---|
| conversations, chat_messages, polls, scheduled_messages, reports, claim_requests, announcements, organizations, org_invite_consents | `read/create/update/delete("users")` | jeder eingeloggte Nutzer liest/ändert/löscht **alle** Dokumente |
| invitations, audit_log | `read/create/delete("users")` (audit_log zusätzlich `documentSecurity=false`) | alle Einladungen (E-Mails!) und Audit-Logs lesbar |
| users, members | `read/create("users")` | alle Profile inkl. E-Mail, `isChild`, Eltern-Links, `fcmToken` lesbar |
| read_receipts | `read("users")` | Lesezeiten aller Nutzer lesbar |

Selbstregistrierung per E-Mail-OTP ist offen → praktisch „öffentlich“. Die Team-ACLs auf Dokument-Ebene (2026-07) sind dadurch wirkungslos.

Die Behauptung in der alten `fix-permissions.js`, Collection-read sei für Realtime nötig, ist falsch: Appwrite liefert ein Realtime-Event an jeden Subscriber mit Leserecht auf das **Dokument** (bei `documentSecurity=true` zählt die Dokument-ACL). Das Abonnieren eines Kanals selbst ist nicht rechtegeprüft. → wird in Stufe 1 trotzdem live verifiziert (§5).

## 2. Ist-Zustand der Dokument-ACLs (Dry-Run `harden-permissions.js`, 2026-11-14)

| Collection | Dokumente | breite Doc-Rechte | Abweichung vom Soll |
|---|---|---|---|
| conversations | 33 | 0 | 0 (Teams: 2 fehlende Mitgliedschaften eines Nutzers) |
| chat_messages | 1262 | 0 | 2 |
| polls | 8 | 0 | 1 |
| scheduled_messages | 1 | 0 | 0 |
| reports | 0 | – | – |
| read_receipts | 127 | 0 | 0 |
| claim_requests | 8 | 0 | 7 (6 ohne read-Recht → alte Anfragen) |

→ Die Dokument-Ebene der Chat-Daten ist bereits fast vollständig gehärtet; Hauptproblem ist allein die Collection-Ebene.

## 3. Audit: Client-Pfade je Collection

Legende: ✅ durch Doc-ACL abgedeckt · 🔧 auf diesem Branch geschlossen · ⏳ Phase 2/3

### Phase 1 – Chat-Daten (auf diesem Branch umgesetzt)

| Collection | Pfad (Datei) | Wer | Abdeckung ohne Collection-Rechte |
|---|---|---|---|
| conversations | alle `watch*Conversations`, `watchConversation`, Duplikat-Check in `requestConversation` (chat_service) | Teilnehmer, Guardians, Admin/Mod | ✅ `read team(convId)`; Aufsicht ist im Conv-Team |
| | `request/createApproved/createGroupChat` | jeder | ✅ Collection `create`; Doc `user(self)` bis `sync-conversation-permissions` |
| | `approve/archive/rename/updateGroupInfo/pin/unpin/setPersonalName/_updateLastMessage/add-/removeMember…` | Teilnehmer bzw. Admin/Mod | ✅ `update team(convId)` (siehe Zusatzbefund B) |
| | `rejectConversation` (delete) | Admin/Mod/Guardian | ✅ `delete team(convId)` |
| | `deleteConversation` | Admin/Mod | 🔧 löschte fremde Nachrichten direkt → jetzt `admin-member-action/deleteConversation` (inkl. Polls, Receipts, Medien) |
| chat_messages | `watchMessages`, Desktop-Toasts | Conv-Team | ✅ `read team(convId)` |
| | senden, eigene bearbeiten/soft-löschen/wiederherstellen | Autor | ✅ `user(self)` |
| | Reaktionen auf **fremde** Nachrichten (`setReaction`) | Teilnehmer | 🔧 lief über Collection-update → neue Function `set-reaction` |
| | Report-Ansicht „Nachricht löschen“ (`softDeleteMessage` auf fremde Nachricht) | Admin/Mod | 🔧 → `moderate-message` mit `action: softDelete` |
| | Moderation (Archivieren) | Admin/Mod | ✅ `moderate-message` (schon vorher) |
| polls | `watchPoll`, `castVote`, `closePoll`, `createPoll` | Conv-Team | ✅ `read/update team(convId)` |
| scheduled_messages | watch/anlegen/löschen | Autor | ✅ `user(self)` |
| reports | `reportMessage` (create) | jeder | ✅ Collection `create`; `on-new-report` setzt ACL |
| | `watchReports`, `markReportReviewed` | Admin/Mod | ✅ `read/update user(Aufsicht)` |
| | Zähler `organizations.pendingReportsCount` dekrementieren | Admin/Mod | 🔧 schrieb Org-Doc direkt → `on-new-report` zählt bei create **und** update serverseitig neu (Recount, idempotent) |
| read_receipts | `watchMyReadReceipts`, Desktop-Badge | Eigentümer | ✅ `read user(uid)`; schreiben nur `mark-as-read` |
| claim_requests | anlegen / ausgehende / eingehende / bestätigen / ablehnen / abbrechen | Eltern bzw. Kind | ✅ Collection `create`; `on-claim-request` setzt from/to-Rechte |

### Phase 2 – Org-Daten (⏳ geplant, Client-Teile schon auf diesem Branch)

| Collection | Problem ohne Collection-Rechte | Lösung |
|---|---|---|
| organizations | Doc-ACL `read users` (zu breit); `update/delete` nur Ersteller → neuer Admin nach `transferAdmin` kann Einstellungen/Keywords/Archiv nicht mehr ändern | neues Org-Team `org_<orgId>` (alle Mitglieder) → `read team(org_…)`; `update user(aktueller Admin)` — gepflegt von einer erweiterten `sync-supervisor-team` (Trigger members) |
| members | Doc-ACL `read users` → E-Mails aller Mitglieder weltweit lesbar | `read team(org_…)` + `read/update/delete user(self)`; Ersteller (`createOrganization`, `admin-member-action`, `process-my-invitations`, `on-parent-consent`) setzen das, Sync-Function korrigiert |
| | `rejectChildInvite` löschte fremden (Kind-)Member-Doc | 🔧 schon jetzt `admin-member-action/rejectChild` (Guardian oder Admin/Mod) |
| announcements | Doc-ACL nur `read users`; Bearbeiten/Löschen/Reaktion/RSVP liefen komplett über Collection-Rechte | Client legt mit `read team(org_…)` + `update/delete team(sup_…)` an (Ersteller ist Supervisor → darf das granten); 🔧 Reaktion/RSVP schon jetzt über `set-reaction`; Migration für Bestand |
| audit_log | `documentSecurity=false` → alle Logs aller Orgs lesbar | `documentSecurity=true`, Client legt mit `read team(sup_…)` an |
| invitations | Client legt ohne ACL an; Admin-Liste + Guardian-Liste lesen über Collection-read | `on-new-invitation` setzt `read/update team(sup_…)` + `read user(guardianUids)` |
| org_invite_consents | Eltern lesen/genehmigen über Collection-Rechte | `on-child-org-invite` setzt `read/update user(parentUids)` + `read team(sup_…)` |

Voraussetzung Phase 2: `sup_<orgId>` wird **ACL-Team** (heute nur Cache). Es ist bereits für alle 11 Orgs vorhanden und synchron (Dry-Run Phase 1: 0 fehlend); CLAUDE.md muss dann angepasst werden.

### Phase 3 – users (⏳ geplant)

Fremde users-Docs liest der Client heute für: E-Mail-Lookup in `inviteMember` und `sendClaimRequest`; `getUserDisplayName` (Direktchat-Titel, Familienbaum); `_watchRelatives` (verifizierte Eltern/Kinder); `updateMemberRole` (isChild-Check — 🔧 jetzt serverseitig in `admin-member-action/updateRole`, Client-Read entfernt).
Lösung: Callable für E-Mail-Lookup bzw. Einladen/Claim-Anlegen komplett serverseitig; Anzeigenamen aus Member-Docs; `on-claim-confirmed` gibt Eltern/Kind gegenseitig `read` auf ihr users-Doc. Danach users-Doc nur `user(self)`.

## 4. Kritische Zusatzbefunde (Dokument-Ebene, nicht durch Collection-Rechte verursacht)

Diese Lücken bleiben auch nach Phase 1–3 bestehen und sollten **zeitnah separat** behoben werden:

- **A – Selbst-Eskalation über eigene Docs.** `members/{orgId}_{uid}` trägt `update user(uid)`, `users/{uid}` trägt `update user(uid)`. Appwrite kennt keine Feld-Rechte → jedes Mitglied kann per API `role: "admin"` in sein eigenes Member-Doc schreiben. `admin-member-action`, `moderate-message` und `sync-supervisor-team` vertrauen genau diesem Feld → der Nutzer wird Aufsicht, landet in **allen** Conv-Teams der Org und liest alle Chats. Ein Kind kann außerdem `guardianUids` aus dem eigenen Member-Doc entfernen bzw. `isChild`/`verifiedParentUids` im users-Doc ändern. Fix: diese Docs nicht mehr client-schreibbar machen; selbst-editierbare Felder (Anzeigename, Foto, `hideEmail`, Benachrichtigungs-Intervalle) über eine Callable-Function.
- **B – Conversation-Felder.** `update team(convId)` erlaubt jedem Teilnehmer (auch Kindern), `status` (Selbst-Genehmigung), `participantUids` und `guardianUids` zu ändern; `sync-conversation-permissions` übernimmt das ins Team → ein Kind kann Guardians aus dem Chat entfernen. `delete team(convId)` erlaubt jedem Teilnehmer, den Chat zu löschen. Fix: Status-/Mitglieder-Änderungen über eine Function mit Rollenprüfung; Team-ACL nur noch für unkritische Felder bzw. Sync-Function validiert und setzt geschützte Felder zurück.
- **C – Polls.** `update team(convId)` erlaubt Teilnehmern, Frage/Optionen/Stimmen anderer zu ändern (geringeres Risiko; gleiche Lösung wie Reaktionen).

## 5. Rollout (Phase 1)

Grundsatz: Collection-Rechte erst entziehen, wenn **alle** Clients, die einen Pfad noch über Collection-Rechte nutzen, ersetzt sind. Nur `chat_messages` braucht die neue App — alle anderen Phase-1-Collections funktionieren auch mit der aktuellen App.

| Stufe | Aktion | App nötig? |
|---|---|---|
| 0 | Functions deployen: `set-reaction` (neu, Var `APPWRITE_API_KEY`/`APPWRITE_ENDPOINT` via `set-function-vars.js`), `moderate-message`, `admin-member-action`, `on-new-report` (**neues Event `reports.*.update`**). Index `reports.orgId_status_idx` per `node setup.js` anlegen, Status „available“ prüfen. Dann `node harden-permissions.js` (Dry-Run) → `--confirm=<projectId>` | nein |
| 1 | **Kanarienvogel:** `node fix-permissions.js --only=read_receipts,polls --confirm=<projectId>` → Tests T1–T3 | nein |
| 2 | `--only=scheduled_messages,claim_requests,reports,conversations` → Tests T4–T7 | nein |
| 3 | App-Release N (Android **und** Windows; Web-Branch rebasen) mit diesen Client-Änderungen; `app_config/android` erst `latestVersionCode=N`, nach Verfügbarkeit im Store + Adoptionsphase `minVersionCode=N` | – |
| 4 | `--only=chat_messages` → Tests T8–T10 | ja (N) |

Windows hat keine Update-Pflicht: Alt-Clients verlieren nach Stufe 4 nur Reaktionen auf fremde Nachrichten, Chat-Löschen durch Admin/Mod und das Löschen aus der Report-Ansicht (diese Aktionen schlagen fehl) — kein Datenverlust, kein Lesezugriff betroffen.

### Live-Stand

| Datum | Stufe | Was |
|---|---|---|
| 2026-11-14 | 0 | Deployed (vom Branch `security/collection-acls`, 6cba376): `on-new-report` (+ Event `reports.*.update`), `moderate-message`, `admin-member-action`, `set-reaction` (neu, Vars gesetzt; Smoke-Test ohne User → 401 ✓). Index `reports.orgId_status_idx` available. `harden-permissions.js --confirm`: 2 Nachrichten, 1 Poll, 7 Claims korrigiert (2 Team-Adds für gelöschtes Konto `JGOzfxaYo9bWgz52cknakL2ZPKm2` → 404, harmlos). |
| 2026-11-14 | 1 | `read_receipts` → `[]`, `polls` → `[create("users")]`. T1 + T2 (Realtime live, auch nach Resume) vom Owner auf zwei Geräten bestätigt ✓. T3 mit Wegwerf-Konto ohne Org (danach gelöscht): list polls/read_receipts → 0 Treffer, get → 404, update → 401 ✓. Kontrolle: dasselbe Konto las in der noch offenen `conversations` alle 33 Chats → Stufe 2 dringend. |
| 2026-11-14 | 2 | Vorab-Dry-Run: alle Doc-ACLs im Soll (0 Abweichungen). `scheduled_messages`, `claim_requests`, `reports`, `conversations` → `[create("users")]`. Negativtest mit Wegwerf-Konto (danach gelöscht): list → 0, get → 404, update → 401 ✓. Kontrolle: `chat_messages` (Stufe 4) noch für jedes Konto lesbar (1265). T4–T7 auf Geräten offen. |

Deploy-Hinweis: `appwrite push functions` (CLI 20.1) würde `buildSpecification`/`runtimeSpecification` (live `s-8vcpu-8gb`) und `deploymentRetention` auf Default zurücksetzen und fragt interaktiv nach. Deshalb per SDK deployed (`functions.createDeployment` mit tar.gz des Function-Ordners; Settings nur bei Event-Änderung per `functions.update` mit allen Live-Werten).

Übergangseffekt bis zum App-Release: Alte Clients dekrementieren `pendingReportsCount` beim „geprüft“-Markieren weiterhin selbst, zusätzlich zählt `on-new-report` neu → der Zähler kann kurz um 1 zu niedrig sein und heilt beim nächsten Report-Ereignis.

**Rollback** je Collection sofort möglich: `node fix-permissions.js --only=<col> --rollback --confirm=<projectId>` (setzt den Live-Stand von 2026-11-14 zurück).

Achtung: `appwrite.config.json` enthält bei `tables` leere `$permissions` — **nie** `appwrite push tables` ausführen; Collection-Rechte nur über `fix-permissions.js` pflegen.

## 6. Testanleitung

Zwei Testkonten A und B (`appwrite/create-test-users.js`), beide in derselben Test-Org, ein Direktchat A↔B; zusätzlich Konto M (Moderator) und Konto X (Mitglied einer **anderen** Org). Jeweils zwei Geräte/Instanzen gleichzeitig offen (z. B. Android + Windows). Vor jedem Test: App frisch gestartet **und** ein Test nach Resume aus dem Hintergrund (Realtime-Reconnect).

Negativ-Test per API (für jede umgestellte Collection): mit Session von X `GET /v1/databases/guardian/collections/<col>/documents` → darf **nichts** aus A/Bs Org liefern; `PATCH`/`DELETE` auf eine bekannte Dokument-ID → 401/404. Am einfachsten im Browser-DevTools der Web-App oder mit `curl` + Session-Cookie.

| # | Stufe | Test | Erwartung |
|---|---|---|---|
| T1 | 1 | A öffnet Chat mit ungelesener Nachricht von B; auf Gerät 2 von A (Desktop) | Ungelesen-Badge verschwindet **live** (Realtime über `read user(uid)`) |
| T2 | 1 | B erstellt Poll, A stimmt ab | B sieht Stimme **live** (Realtime über `read team(convId)`) |
| T3 | 1 | X: List `read_receipts`, `polls` | leer |
| T4 | 2 | A fragt neuen Chat mit B an (Guardian-Modus); M genehmigt | M sieht Anfrage live; nach Genehmigung erscheint Chat bei A und B live |
| T5 | 2 | B meldet Nachricht von A; M markiert als geprüft | M bekommt Push + Report live; Zähler-Badge der Org geht auf 0 |
| T6 | 2 | Eltern-Kind-Claim senden/bestätigen | beide Seiten sehen Status live |
| T7 | 2 | geplante Nachricht anlegen/löschen | nur Autor sieht sie |
| T8 | 4 | B reagiert auf Nachricht von A | A sieht Reaktion live (`set-reaction`) |
| T9 | 4 | M löscht in der Report-Ansicht die Nachricht | Nachricht als gelöscht markiert; Report geprüft |
| T10 | 4 | M löscht einen Chat mit Nachrichten/Bildern von A und B | Chat verschwindet bei allen live; Nachrichten + Dateien weg (Functions-Log) |
| T11 | 4 | Guardian lehnt Kind-Einladung ab; Reaktion/RSVP auf Ankündigung | funktioniert (Phase-2-Collections sind noch offen, Pfade laufen aber schon über Functions) |

Wenn T1/T2 fehlschlagen (kein Live-Update, erst nach Neuladen): sofort Rollback der beiden Collections und prüfen, ob Realtime die Team-Mitgliedschaft erst nach Reconnect kennt (dann `broadcaster.reconnect()` nach Chat-Erstellung).
