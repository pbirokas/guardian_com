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
| | `watchConversationReadReceipts` (Lesestatus-Häkchen, 2026-11-25) | andere Teilnehmer | 🔧 `read team(convId)` — nur auf Receipts von **Teilnehmern** (§7) |
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

### Phase 3 – users (✅ live seit 2026-11-26, siehe §8)

Fremde users-Docs las der Client für: E-Mail-Lookup in `inviteMember` und `sendClaimRequest`; `getUserDisplayName` (Direktchat-Titel im Share-Picker, Mit-Eltern im Familienbaum); `_watchRelatives` (verifizierte Eltern/Kinder); `updateMemberRole` (isChild-Check — schon serverseitig in `admin-member-action/updateRole`). Alle Pfade laufen jetzt über Functions bzw. Member-Docs; danach users-Collection **ohne** Rechte, Doc-ACL nur `read user(self)`.

## 4. Kritische Zusatzbefunde (Dokument-Ebene, nicht durch Collection-Rechte verursacht)

Diese Lücken bleiben auch nach Phase 1–3 bestehen und sollten **zeitnah separat** behoben werden. **A und B (plus Eltern-Anfragen und fremde Member-Docs): Fix vorbereitet, siehe [`self-escalation.md`](self-escalation.md).**

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
| 2026-11-14 | 2 | Vorab-Dry-Run: alle Doc-ACLs im Soll (0 Abweichungen). `scheduled_messages`, `claim_requests`, `reports`, `conversations` → `[create("users")]`. Negativtest mit Wegwerf-Konto (danach gelöscht): list → 0, get → 404, update → 401 ✓. Kontrolle: `chat_messages` (Stufe 4) noch für jedes Konto lesbar (1265). T4–T7 vom Owner auf Geräten bestätigt ✓. |
| 2026-11-17 | 3 | App 2.0.0 (versionCode 151, aus `main` inkl. PR #3/#5) im Play Store; `app_config/android`: `latestVersionCode=151`, `minVersionCode=151` (vom Owner gesetzt). |
| 2026-11-25 | 4 | Vorab-Dry-Run: alle 1172 Nachrichten im Soll, 0 breite Doc-Rechte. `chat_messages` → `[create("users")]`. Negativtest mit Wegwerf-Konto (danach gelöscht): list → 0, get → 404, update → 401 ✓. **Phase 1 damit komplett live** (`fix-permissions.js` Dry-Run: 0 Abweichungen). T8–T10 auf Geräten ✓ (User, 2026-11-25). |

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

## 7. Lesestatus-Häkchen: Receipts im Chat-Team lesbar (2026-11-25, Server live)

**Problem:** `_readStatus` (Chat-Screen) las `conv.lastReadAt`, das seit dem Entfernen von `lastReadAtJson` immer leer war → immer „gesendet“. Die echten Lesezeiten liegen in `read_receipts`, die seit Stufe 1 nur der Eigentümer lesen darf.

**Entscheidung (Owner, 2026-11-25):**
- Als „Leser“ zählen nur **Teilnehmer** (`participantUids`). Receipts von Guardians und Aufsicht (im Conv-Team, aber keine Teilnehmer) bleiben `read user(uid)` — ein Kind sieht nicht, wann Eltern/Admins mitlesen; sie zählen auch nicht für die Häkchen.
- **Kinder wie alle anderen:** Ein Kind sieht die Häkchen der anderen Teilnehmer, und die anderen sehen die Lesezeit des Kindes.

**Umsetzung:**
- `mark-as-read` setzt bei **jedem** Upsert die ACL `read user(uid)` + (nur Teilnehmer) `read team(convId)`. Kein `update`/`delete` mehr für den Client: sobald Receipts team-lesbar sind, könnte ein Teilnehmer sonst über das `uid`-Feld seines eigenen Receipts einen fremden Lesezeitpunkt vortäuschen. Die App schreibt Receipts nie direkt.
- Gewählt statt einer Callable-Function, weil Appwrite-Realtime das Event dann von selbst an alle mit Doc-read zustellt (gleicher Weg wie Nachrichten) — kein Polling. Konten außerhalb des Chats sind nicht im Conv-Team → kein Zugriff.
- Client: `ChatService.watchConversationReadReceipts(convId)` (List `convId`, Index `convId_uid_idx`; Realtime-Payload direkt übernommen, leeres Resync-Event lädt neu) → `conversationReadReceiptsProvider`. `watchMyReadReceipts` und der Desktop-Badge ignorieren jetzt fremde Receipt-Events.
- Wechsel der Teilnehmer: die ACL heilt sich beim nächsten Gelesen-Markieren des Betroffenen; wer den Chat verlässt, verliert mit dem Conv-Team auch den Lesezugriff.
- `harden-permissions.js` Phase 7 akzeptiert das neue Modell und dreht es nicht zurück.

**Rollout:**

| Schritt | Aktion | App nötig? |
|---|---|---|
| 1 | `node deploy-functions.js --only=mark-as-read` (Dry-Run) → mit Bestätigung | nein |
| 2 | `node share-read-receipts.js` (Dry-Run, zählt Teilnehmer/privat/verwaist) → `--confirm=<projectId>` | nein |
| 3 | App-Release mit `watchConversationReadReceipts` (Android, Windows, Web) | ja |

**Live-Stand:** 2026-11-25 Schritt 1 (`mark-as-read` deployt, Owner) und Schritt 2 erledigt: 126 Receipts, 94 Teilnehmer → team-lesbar, 26 Guardian/Aufsicht → privat, 6 ohne Conversation ignoriert; 120 ACLs geändert, Kontroll-Dry-Run 0 Abweichungen. Schritt 3 (App-Release) und Tests T11–T15 offen.

Alte Apps sind unbetroffen (sie lesen nur eigene Receipts). Rollback: `mark-as-read` auf den Vorstand deployen, dann `node share-read-receipts.js --rollback --confirm=<projectId>`.

**Tests:**

| # | Test | Erwartung |
|---|---|---|
| T11 | A schreibt B im Direktchat; B öffnet den Chat (Gerät 2) | bei A springt das Häkchen **live** von „gesendet“ auf „alle haben gelesen“ |
| T12 | Gruppenchat A, B, C: A schreibt, nur B liest, dann C | A sieht „einer hat gelesen“, danach „alle“ |
| T13 | M (Aufsicht, kein Teilnehmer) bzw. Guardian öffnet den Chat | Häkchen bei A ändern sich **nicht**; M sieht in List `read_receipts` (`convId`) die Teilnehmer-Receipts, A/B sehen das Receipt von M nicht |
| T14 | X (andere Org): List `read_receipts` mit `convId`, Get per bekannter Receipt-ID | leer bzw. 404 |
| T15 | B: `PATCH` auf eigenes Receipt (`uid` ändern) | 401 (kein `update` mehr) |

## 8. Phase 3 – users: nur noch das eigene Profil lesbar (live seit 2026-11-26)

**Problem:** Collection `users` hat live `read("users")` (+ `create("users")`). Jedes Konto — Selbstregistrierung per E-Mail-OTP ist offen — liest damit die users-Docs **aller** Nutzer: E-Mail (auch bei `hideEmail`), `isChild`, `verifiedParentUids`/`verifiedChildUids`, `membershipsJson` (welche Orgs, welche Rolle), `notificationSettingsJson`, `fcmToken`. Die Doc-ACL ist schon eng (Dry-Run 2026-11-25: 27 Docs, **0** mit fremdem read; alle 27 tragen noch `update/delete user(self)` → Selbst-Eskalations-Stufe 4).

**Entscheidung (Abweichung vom ursprünglichen Plan):** Statt Eltern/Kind über `on-claim-confirmed` gegenseitig `read` auf das users-Doc zu geben, liefert eine Callable einen **Whitelist-Auszug**. Gründe: ein Doc-read gäbe auch `fcmToken`, `membershipsJson` und Einstellungen preis (Appwrite kennt keine Feld-Rechte); Mit-Eltern (Elternteil sieht den anderen Elternteil seines Kindes) wären damit nicht abgedeckt; jede Verknüpfungs-Änderung (`revoke-connection`) müsste ACLs nachziehen. Invariante jetzt schlicht: **users-Doc = `read user(uid)`, sonst nichts.** `on-claim-confirmed` bleibt unverändert.

### Client-Pfade (alt → neu)

| Pfad | vorher | jetzt |
|---|---|---|
| `OrganizationService.inviteMember` (Einladen-Dialog, Adressbuch, CSV-Import) | List `users` per E-Mail, dann Einladung/Consent/`addMember` vom Client | **`admin-member-action/inviteByEmail`** {email, role, guardianUids} — nur Admin/Mod. Ergebnis `invited` (invitations-Doc, ACL wie bisher `rud user(Einladender)`), `consentRequested` (org_invite_consents-Doc mit `read/update user(parentUids)` + `rud user(Einladender)`) oder `added` (wie `addMember`; liefert nur `targetUid`/`targetName` fürs Audit-Log). Fehler: `already_member`, `invitation_exists`, `consent_pending`, `child_account_role_locked`, `invalid_guardians…`, `invalid_email` |
| `ParentClaimService.sendClaimRequest` | List `users` per E-Mail, Claim vom Client anlegen | **`self-service/sendClaim`** {email} — legt den Claim mit der finalen ACL an (`on-claim-request` läuft weiter für den Push und setzt dieselbe ACL). Fehler wie bisher: `user_not_found`, `cannot_claim_self`, `already_exists`. Antwort nur `requestId` |
| `ParentClaimService.watchMyChildren/-Parents` | eigenes users-Doc + `getDocument` je Verwandtem | **`self-service/listRelatives`** → `{children: [{uid, displayName, email, photoUrl, coParents: [{uid, displayName}]}], parents: […]}`; nur **gegenseitig** bestätigte Links (sonst könnte man bis Stufe 4 fremde UIDs in die eigenen `verified*Uids` schreiben und deren Profil abfragen). Neu geladen per Realtime auf das **eigene** users-Doc — nur, wenn sich das jeweilige Feld ändert — und beim Resync |
| Familienbaum: Mit-Eltern | `getUserDisplayName(uid)` je Mit-Elternteil | `coParents` aus `listRelatives` |
| Share-Picker: Direktchat-Titel | `userDisplayNameProvider(uid)` → users-Doc | `memberDisplayNameProvider((orgId:, uid:))` → Member-Doc `{orgId}_{uid}` (der Partner ist immer Mitglied der Chat-Org) |
| eigenes users-Doc (Login, Profil, Einstellungen, Adressbuch, Realtime) | `read user(self)` | unverändert |

Server-Functions lesen users-Docs weiter mit API-Key (unberührt). Kein `dart:io`, alles über `callJson`/`executeRaw` → Android, Windows und Web identisch.

**Bleibt offen:** Member-Docs enthalten weiter `email` (außer bei Kindern), `displayName`, `photoUrl` und sind bis Phase 2 für alle Konten lesbar. `sendClaim` verrät weiterhin, ob eine E-Mail registriert ist (`user_not_found`) — wie bisher, aber ohne weitere Daten; bei Bedarf später ein Rate-Limit.

### Rollout (gemeinsam mit Selbst-Eskalation Stufe 2–4 → ein erzwungenes Update)

| Stufe | Aktion | App nötig? |
|---|---|---|
| P3-0 | Functions deployen: `self-service` (neu: `sendClaim`, `listRelatives`), `admin-member-action` (neu: `inviteByEmail`) per `node deploy-functions.js --only=self-service,admin-member-action` (Dry-Run → `--confirm`). Rein additiv — alte Apps rufen die neuen Aktionen nicht auf. Smoke-Test U0. Jederzeit vor dem Release | nein |
| P3-1 | App-Release N (Android + Windows + Web via `npm run deploy-web`) — derselbe Release wie Selbst-Eskalation Stufe 2 | – |
| P3-2 | Nach `minVersionCode=N` (Selbst-Eskalation Stufe 3), **zusammen mit** Selbst-Eskalation Stufe 4: `node harden-users.js` (Dry-Run, Audit prüfen) → `--confirm=<projectId>` (sichert die alten ACLs nach `appwrite/backups/`; deckungsgleich mit `lock-own-docs.js --only=users` — eins von beiden genügt) | ja (N) |
| P3-3 | `node fix-permissions.js --after-app-n --phase3 --only=users` (Dry-Run: `[R, C]` → `[]`) → `--confirm=<projectId>` → Tests U1–U8, U1–U3 mit Wegwerf-Konto | ja (N) |

**Live-Stand**

| Datum | Stufe | Was |
|---|---|---|
| 2026-11-25 | P3-0 | Deployed (Branch `security/users-acl-phase3`): `self-service` → `6b071619ac8c01c76e6b` (vorher `6af965dee9c083b96c69`), `admin-member-action` → `6b07161a3ff9005c30a0` (vorher `6af965aab7fe9d504de1`). `activate` beim Upload griff nicht (Builds `ready`, alte Version blieb aktiv) → per `PATCH /functions/{id}/deployment` aktiviert; `deploy-functions.js` aktiviert seitdem selbst nach dem Build. U0 ✓ (beide 401 ohne User, auf den neuen Deployments). Kontrolle: alle übrigen Functions laufen auf ihrem neuesten `ready`-Deployment. |
| 2026-11-26 | P3-1 | App 2.0.0 Build 167 (aus `main` 30e5a94) im Play Store, Web-App und Windows aktualisiert (Owner); `app_config/android`: `latestVersionCode=167`, `minVersionCode=167`. |
| 2026-11-26 | P3-2 | `harden-users.js --confirm`: 27/27 users-Docs → nur `read user(uid)` (vorher alle mit `update/delete user(self)`, keins mit fremdem read). Backup `appwrite/backups/users-acl-2026-11-26T07-44-49-017Z.json` (gitignored, Haupt-Checkout). Kontroll-Dry-Run: 0 Abweichungen. |
| 2026-11-26 | P3-3 | Zusammen mit Selbst-Eskalation Stufe 4: `fix-permissions.js --after-app-n --phase3 --only=conversations,members,users --confirm` → conversations `[]`, members `[read]`, users `[]`. Gesamt-Dry-Run aller Collections: 0 Abweichungen. Negativtest mit Wegwerf-Konto ohne Org (danach gelöscht): users list → 0, fremdes users-Doc → 404, E-Mail-Query → 0, users create → 401; conversations list → 0, get → 404, update/create → 401; Member-Doc als Admin einer fremden Org anlegen → 401. Gegenprobe eigenes users-Doc: list → 1, get ✓, update mit echter Änderung (`isChild`, `displayName`, `verifiedChildUids`) und delete → 401. Kontrolle: members weiter für jedes Konto lesbar (33, Phase 2 offen). U3 (Realtime) nicht separat getestet; U4–U8 auf Geräten: Owner. |
| 2026-11-26 | Fix | U4 (Owner): Einladung einer unregistrierten Adresse → `document_invalid_structure: Unknown attribute "invitedByUid"`. Attribut fehlte in `invitations` seit jeher (auch die alte App schickte es → solche Einladungen schlugen schon vorher fehl; `process-my-invitations` braucht es für die Rollenprüfung). `invitations.invitedByUid` (string 36, optional) live angelegt + in `setup.js`; Schema-Abgleich aller von `inviteByEmail`/`sendClaim`/`addMemberCore` geschriebenen Felder: vollständig. |
| 2026-11-26 | Web | Befund: Browser lief trotz Build 167 noch mit altem `main.dart.js` (keine `admin-member-action`-Aufrufe, Einladungen vom Alt-Client-Pfad), weil die Site kein `Cache-Control` sendet → Anleitung `docs/ops/web-cache-headers.md` (Traefik, Owner). Web-App Build 171 (Branch `docs/stage4-phase3-live`, inkl. Fix „Einladung zurückziehen“) deployed, Deployment `6b07e929cc5a1ec22970`. |
| 2026-11-26 | Tests | Owner: alle Geräte-Tests auf Build 167 bestanden. Befunde: (1) Kind-Konto sah „Organisation erstellen“ — `isChild` wurde während der Sitzung true (Claim bestätigt), App kannte nur den Login-Snapshot → jetzt `ownUserDocProvider` (Realtime auf eigenes users-Doc) in `currentAppUserProvider`; Server lehnte korrekt ab (403). (2) 08:32: 9× `self-service` „Execution timed out“ (4–5 parallele synchrone Executions, API-Worker-Blockade wie mark-as-read 2026-11-13); vermutlich `listRelatives` doppelt (Kinder+Eltern) → ein gemeinsamer In-flight-Aufruf. `on-new-invitation` → `6b07f06944a18d1a620a` (Mail, wenn kein users-Doc; vorher `6af862b55f651470ac56`). |

**Windows-Alt-Clients nach P3-3** (keine Update-Pflicht): Einladen eines **registrierten** Kontos legt stattdessen eine Einladung an (übernimmt `process-my-invitations` beim nächsten Login des Eingeladenen); Eltern-Anfrage meldet „nicht gefunden“; Familienbaum leer bzw. Mit-Eltern als UID. Kein Datenverlust.

**Rollback:** Collection `node fix-permissions.js --phase3 --only=users --rollback --confirm=<projectId>` (→ `[R, C]`, Stand 2026-11-14). Doc-ACLs `node harden-users.js --rollback=backups/users-acl-<ts>.json --confirm=<projectId>` (öffnet `update/delete` wieder — nur im Notfall). Functions: vorige Deployments in der Console aktivieren (die neue App braucht die neuen Aktionen — deshalb erst nach erfolgreichem P3-0-Smoke-Test releasen).

### Dry-Run (2026-11-25, nur lesend)

- `harden-users.js`: 27 users-Docs, 27 abweichend — **alle nur** wegen `update/delete user(self)`; 0 mit fremdem read; 0 ohne eigenes read. Audit: 0 Auffälligkeiten (keine doppelten/fehlenden/nicht normalisierten E-Mails, keine einseitigen Eltern-Kind-Links).
- `fix-permissions.js --after-app-n --phase3 --only=users`: ist `[read("users"), create("users")]` → soll `[]`.
- Mock-Test `node test-functions-mock.cjs`: `inviteByEmail` (nur Admin/Mod, Moderator darf keinen Moderator einladen, Einladung/Consent/Direkt, Duplikate, Kind-Sperre) und `sendClaim`/`listRelatives` (kein `fcmToken`/`membershipsJson` im Ergebnis, einseitige Links unsichtbar, Claim-ACL ohne `update` für den Anfragenden) ✓.

Hinweis Negativtest: Ein `update` **ohne echte Änderung** (gleiche Werte) beantwortet Appwrite mit 200, ohne Rechte zu prüfen — Rechteprüfung nur mit tatsächlich geänderten Werten testen.

### Testanleitung

Konten wie §6: A (Admin), M (Moderator), B (registriert, noch nicht in der Org), Elternteil P mit verifiziertem Kind C und Mit-Elternteil P2, **X = Wegwerf-Konto ohne Org** (nach dem Test löschen). Android, Windows und Web.

| # | Stufe | Test | Erwartung |
|---|---|---|---|
| U0 | P3-0 | `self-service` mit `{action:"listRelatives"}` ohne Session (Console → Execute ohne User) | 401 |
| U1 | P3-3 | X per API: `GET …/collections/users/documents` | **nur das eigene Doc** (total 1) |
| U2 | P3-3 | X: `GET …/collections/users/documents/<uid von A>`; List mit `equal("email", <A>)` | 404 bzw. leer |
| U3 | P3-3 | X abonniert Realtime `databases.guardian.collections.users.documents`, A ändert sein Profil | kein Event bei X |
| U4 | P3-0+N | A lädt B ein / eine unregistrierte Adresse / Kind C (mit Guardian) | B sofort Mitglied (Audit-Log mit Namen); Einladungs-Mail; Zustimmungsanfrage bei P und P2 (Push), nach Zustimmung ist C Mitglied |
| U5 | P3-0+N | M lädt jemanden als Moderator ein; A lädt C als Mitglied ein; dieselbe unregistrierte Adresse zweimal | „Only admin…“; „child_account_role_locked“-Meldung; „bereits ausstehende Einladung“ |
| U6 | P3-0+N | P sendet Anfrage an unbekannte Adresse / eigene Adresse / zweimal an dieselbe; C bestätigt | „nicht gefunden“ / Fehler / „existiert bereits“; nach Bestätigung erscheinen C bei P und P bei C **live** (Familienbaum + Verknüpfungen) |
| U7 | P3-0+N | Familienbaum bei P: Kind C mit Mit-Elternteil P2; dann Verknüpfung lösen | Name von P2 sichtbar; nach dem Lösen verschwindet C live |
| U8 | N | Android: Bild in einen Direktchat teilen | Share-Picker zeigt den Namen des Gegenübers (nicht die UID) |

Schlagen U4–U8 nach P3-3 fehl: sofort Collection-Rollback (oben), dann Function-Logs prüfen.
