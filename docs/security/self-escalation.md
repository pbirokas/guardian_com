# Selbst-Eskalation auf Dokument-Ebene schließen

Stand: 2026-11-15 · Branch `claude/happy-cohen-c97eb1`, rebased auf `main` (a5811af, nach PR #3/#4) · **Nichts davon ist live** — jeder Server-Schritt braucht das OK des Owners.

Behebt die Zusatzbefunde **A** und **B** aus [`collection-acl-hardening.md`](collection-acl-hardening.md) §4 sowie zwei dabei gefundene, gleichwertige Lücken (**D**, **E**).

## 1. Befunde

Appwrite kennt keine Feld-Rechte: wer `update` auf ein Dokument hat, darf **jedes** Feld ändern (auch `$permissions` innerhalb der eigenen Rollen).

| # | Lücke | Folge |
|---|---|---|
| A1 | `members/{orgId}_{uid}` trägt `update/delete user(uid)` | jedes Mitglied schreibt `role: "admin"` ins eigene Member-Doc → `admin-member-action`, `moderate-message`, `sync-supervisor-team` vertrauen dem Feld → Aufsicht, Mitglied in **allen** Conv-Teams der Org, liest alle Chats. Ein Kind entfernt `guardianUids`. |
| A2 | `users/{uid}` trägt `update/delete user(uid)` | Kind setzt `isChild=false` (→ `revoke-connection` trennt Eltern) oder entfernt `verifiedParentUids` (→ `get-child-summary` verweigert Eltern). |
| D | Collection `members` hat `create("users")` | jeder legt `members/{fremdeOrg}_{self}` mit `role: "admin"` an → Admin einer fremden Org (Doc-ID ist genau das, was die Functions nachschlagen). |
| B1 | Conversation-ACL `update team(convId)` | jeder Teilnehmer (auch Kinder) ändert `status` (Selbst-Genehmigung), `participantUids`, `guardianUids`; `sync-conversation-permissions` übernimmt das ins Team → Kind wirft Guardian raus. Alte App legt Chats sogar direkt `approved` an (`createApprovedConversation` ohne Serverprüfung). |
| B2 | Conversation-ACL `delete team(convId)` | jeder Teilnehmer löscht den Chat. |
| E | `claim_requests`: Anfragender hat `update` | Elternteil setzt seine eigene Anfrage auf `confirmed` → `on-claim-confirmed` trägt ihn als verifizierten Elternteil eines **beliebigen** Kontos (per E-Mail gefunden) ein → `get-child-summary` liefert dessen Aktivität. Zusätzlich konnte die Anfrage schon mit `status: confirmed` angelegt werden. |
| – | `admin-member-action/addMember` übernahm `memberData` vom Client | Moderator legte Mitglieder direkt als `moderator`/`admin` an. `updateRole`: Moderator konnte den Admin herabstufen. `updateGuardians`: beliebige UIDs als Guardian. |

## 2. Inventar: Client-Schreibpfade (vor dieser Änderung)

`guardian_app/lib/core/services/*.dart` — jeder Pfad und was er jetzt nutzt.

### users

| Pfad | Felder | neu |
|---|---|---|
| `AuthService._getOrCreateUserDoc` (create) | ganzes Doc inkl. `isChild`, `verifiedParentUids`, ACL `rud user(self)` | `self-service/ensureUserDoc` (Server setzt Felder, ACL `read user(self)`) |
| `AuthService.updateProfile` | `displayName`, `photoUrl` | `self-service/updateProfile` (+ alle eigenen Member-Docs) |
| `AuthService.saveNotificationSettings` | `notificationSettingsJson` | `self-service/setNotificationSettings` |
| `NotificationService._saveToken` | `fcmToken` | `self-service/setFcmToken` (async) |
| `OrganizationService.setHideEmail` | `hideEmail` (+ Member-Docs) | `self-service/setHideEmail` |
| `OrganizationService._updateMembershipsJson` (nur `createOrganization`) | `membershipsJson` | entfällt — `self-service/createOrganization` |

### members

| Pfad | Felder | neu |
|---|---|---|
| `OrganizationService.createOrganization` (create) | eigenes Admin-Member-Doc | `self-service/createOrganization` |
| `updateMyMemberProfile` (war ungenutzt) | `displayName`, `photoUrl` | entfernt; `self-service/updateProfile` schreibt alle eigenen Member-Docs |
| `setHideEmail` | `hideEmail` | `self-service/setHideEmail` |
| `updateChildAlertInterval` | `childAlertInterval` | `self-service/setChildAlertInterval` |
| `setOrgMessageInterval` | `messageAlertInterval`, `notificationsEnabled` | `self-service/setMessageInterval` |
| alles andere (`addMember`, Rollen, Guardians, Entfernen, Verlassen, Kind ablehnen) | – | schon vorher `admin-member-action` |

### conversations

| Pfad | neu (`conversation-action`) | Regel (live aus Member-Doc) |
|---|---|---|
| `requestConversation` (create pending) | `request` | Aufrufer + Ziel aktive Mitglieder, kein offener Direktchat |
| `createApprovedConversation` (create approved) | `createDirect` | Admin/Mod oder Guardian des Ziels |
| `createGroupChat` | `createGroup` | Admin/Mod; alle Mitglieder aktiv |
| `approveConversation` | `approve` | pending: Admin/Mod oder Guardian eines Teilnehmers (nicht der Anfragende selbst); archived→approved: Admin/Mod |
| `rejectConversation` (delete) | `reject` | wie approve, nur pending |
| `archiveConversation` | `archive` | Admin/Mod |
| `renameConversation`, `updateGroupInfo` | `updateGroupInfo` | Admin/Mod, nur Gruppen; `imageUrl` nur Storage-View-URL |
| `setPersonalName` | `setPersonalName` | Teilnehmer, nur Direktchat; nur eigener Map-Eintrag |
| `pinMessage`/`unpinMessage` | `pin`/`unpin` | Admin/Mod; Pin-Text aus der Nachricht (nicht vom Client) |
| `addMembersToConversation`, `removeMemberFromConversation` | `addMembers`/`removeMember` | Admin/Mod, nur Gruppen; `guardianUids` serverseitig neu berechnet |
| `_updateLastMessage` (bei jedem Senden) | entfällt — `on-new-message` setzt `lastMessage`/`lastMessageAt` | Absender muss laut Nachrichten-ACL im Conv-Team sein |
| `deleteConversation` | schon vorher `admin-member-action/deleteConversation` | Admin/Mod |

`guardianUids`, `canApproveUids`, `orgAdminUid`, `requestedBy` setzt nur noch der Server.

### claim_requests (Befund E)

`confirmClaimRequest`/`rejectClaimRequest` (Kind) und `cancelClaimRequest` (Elternteil) → `self-service/respondClaim`. Anlegen bleibt beim Client (`create`), `on-claim-request` erzwingt `status: pending`, prüft `fromUid` = Ersteller und setzt `read/delete user(from)`, `read/update user(to)` (das `update` fürs Kind bleibt nur für alte Apps; es kann nur über sich selbst entscheiden). `on-claim-confirmed` verarbeitet eine Bestätigung nur, wenn der Anfragende laut ACL **kein** `update` hat und die Anfrage nicht abgelaufen ist.

## 3. Soll-Zustand

| Collection | Collection-Rechte | Doc-ACL | geschrieben von |
|---|---|---|---|
| users | `read("users")` (Phase 3 entzieht read) | `read user(uid)` | `self-service`, `on-claim-confirmed`, `revoke-connection`, `admin-member-action`, … |
| members | `read("users")` (Phase 2 engt read ein) | `read("users")` | `self-service`, `admin-member-action`, `process-my-invitations`, `on-parent-consent`, `on-new-message` (Alert-Zeitstempel) |
| conversations | – | `read team(convId)` | `conversation-action`, `admin-member-action`, `sync-*`, `on-member-guardians-changed`, `on-new-message` |
| claim_requests | `create("users")` | `read/delete user(from)`, `read/update user(to)` | Client (create), `self-service/respondClaim` |

### Übergangs-Schutz (wirkt sofort nach dem Function-Deploy, auch gegen alte Apps)

- **`sync-supervisor-team`-Guard (D):** Member-Docs legen Server-Functions jetzt ohne `update("user:…")` an. Taucht beim create-Event ein Doc **mit** dieser Rolle auf, stammt es von einem Client → gelöscht, außer es ist das Admin-Doc einer gerade selbst gegründeten Org (alte App: `org.adminUid == uid`, einziges Mitglied) — dann werden Rechte entzogen. Restfenster: die Sekunden bis zur Function-Ausführung. Endgültig zu erst mit Stufe 4.
- **`sync-conversation-permissions` (B):** berechnet `guardianUids` bei **jedem** create/update aus den Member-Docs neu (ein Kind kann Guardians auch über eine Alt-ACL nicht entfernen). Client-angelegte Chats (alte App, erkennbar an `update("user:…")`) werden wie in `conversation-action` geprüft: Ersteller muss aktiver Teilnehmer sein, Gruppen nur Aufsicht (sonst gelöscht), `approved` nur Aufsicht bzw. Guardian des Gegenübers (sonst → `pending`), `requestedBy`/`canApproveUids`/`orgAdminUid` werden korrigiert.
- **`on-new-message`:** ignoriert Nachrichten, deren ACL nicht `read team(convId)` + Autor = `senderUid` belegt (keine fremde Chatvorschau / Push-Spam per fremder convId).

## 4. Rollout

Reihenfolge so gewählt, dass die kritischen Lücken (A1, D, E) **vor** dem App-Release zu sind; was alte Apps bricht, kommt erst nach `minVersionCode`. Kann parallel zu Phase 1 der Collection-Härtung laufen; Voraussetzung für Stufe 4 ist deren Stufe 0 (`harden-permissions.js`: Conv-Teams vollständig).

| Stufe | Aktion | Alte App (< N) danach |
|---|---|---|
| 0 | Functions deployen: **neu** `self-service`, `conversation-action` (per `node deploy-functions.js`, Reihenfolge §4a; Execute `users`, Vars via `node set-function-vars.js`; API-Key braucht zusätzlich Scope `users.read` für `ensureUserDoc`), **geändert** `admin-member-action`, `sync-supervisor-team`, `sync-conversation-permissions`, `on-new-message`, `on-claim-request`, `on-claim-confirmed`, `process-my-invitations`. Auf `sync-conversation-permissions` Variable **`CONV_LEGACY_TEAM_WRITE=true`** setzen (sonst sind auch neu angelegte Chats sofort nur-lesbar und alte Apps zeigen darin beim Senden Fehler). Smoke-Test S1–S3 (§5). | fast unverändert (Details §4a); Selbst-Genehmigung/Guardian-Entfernen/fremdes Member-Doc werden schon serverseitig zurückgedreht |
| 1 | `cd appwrite && node lock-own-docs.js` (Dry-Run, **Audit-Liste prüfen**) → `node lock-own-docs.js --only=members,claims --confirm=<projectId>` | verliert: Benachrichtigungs-Intervalle je Org ändern (Fehlermeldung), Anzeigename/„E-Mail verbergen“ in Member-Docs (still), Eltern-Anfrage zurückziehen (Fehlermeldung). **Bewusst vor dem Release** — A1/E sind kritisch. |
| 2 | App-Release N (Android **und** Windows; `feature/web-app` rebasen) | – |
| 3 | `app_config/android`: erst `latestVersionCode=N`; nach Verfügbarkeit + Adoptionsphase `minVersionCode=N` | – |
| 4 | **Zuerst** `CONV_LEGACY_TEAM_WRITE` von `sync-conversation-permissions` entfernen (+ Redeploy/Restart), dann `node lock-own-docs.js --only=users,conversations --confirm=<projectId>` und `node fix-permissions.js --after-app-n --only=conversations,members,users --confirm=<projectId>` | Android: gesperrt (Update-Pflicht). Windows-Alt-Clients: Profil, Push-Einstellungen, alle Chat-Aktionen außer Senden/Lesen schlagen fehl, Senden zeigt eine Fehlermeldung (Nachricht kommt trotzdem an), neue Konten/Orgs anlegen geht nicht → Windows-Nutzer vorher informieren |

**Rollback:** Functions per Appwrite-Console auf die vorige Deployment aktivieren. Collection-Rechte: `node fix-permissions.js --after-app-n --only=<col> --rollback --confirm=<projectId>`. Doc-ACLs haben kein automatisches Rollback (bewusst — sie wieder zu öffnen hieße, die Lücke zu öffnen); einzelne Docs notfalls per Console.

**Achtung:** `harden-permissions.js` akzeptiert ab jetzt bei Conversations beide Stände (rw-Team und read-only) und öffnet gehärtete Chats nie wieder; den Schritt auf read-only macht nur `lock-own-docs.js`.

### 4a. Runbook Stufe 0 + 1 (ohne App-Release)

Ziel: A1 (Rolle selbst setzen), D (fremdes Member-Doc) und E (Eltern-Selbstbestätigung) schließen, **solange** das eingereichte Release (Stand `main` a5811af, kennt `self-service`/`conversation-action` noch nicht) im Umlauf ist. Alle Befehle aus `appwrite/` mit der `.env` von `setup.js`.

**Live-Ist (Dry-Runs vom 2026-11-15, nur lesend):**

- `node deploy-functions.js --only=<9 Functions>`: `self-service`, `conversation-action` fehlen → werden angelegt (Runtime `node-16.0`, Spezifikation `s-8vcpu-8gb` wie `sync-conversation-permissions`, Execute `users`, Timeout 15). Die 7 bestehenden: Events/Execute/Timeout = `appwrite.config.json`, `APPWRITE_API_KEY`/`APPWRITE_ENDPOINT` vorhanden. Aktive Deployments (= Rollback-Ziele):

  | Function | aktives Deployment vor Stufe 0 |
  |---|---|
  | admin-member-action | `6af8717d8dd485a420e0` |
  | process-my-invitations | `6a61cdb219cc37b3d732` |
  | on-claim-request | `6a61cdb3176862c35e59` |
  | on-claim-confirmed | `6a61cdb1844c7ba94310` |
  | on-new-message | `6af855e78d8591139392` |
  | sync-conversation-permissions | `6a61cdb0b84e21fcf33d` |
  | sync-supervisor-team | `6a61cdb20fafa2a41d70` |

- `node lock-own-docs.js`: members 32/32, users 27/27, conversations 34/34, claims 9/9 würden geändert (überall nur `update`/`delete` entzogen; alle 32 Member-Docs tragen heute `read("users") update/delete user(uid)`). Claims: 8 `confirmed`, 1 `cancelled`, **keine offene** → die neue Prüfung in `on-claim-confirmed` betrifft keine laufende Anfrage. Audit: 1 Auffälligkeit — `members/oQoj3jVVvJQfK18YYMfg_tskOdibk2EemgspU48j5g7eoXE72` ist ein **aktives Kind ohne Guardians** (keine Spur von Eskalation, aber Datenfehler: in der App Guardians setzen). Keine fremden/zweiten Admins, keine Kind-Konten mit Erwachsenen-Rolle, kein `isChild=false` mit Eltern-Links.
- `node lock-own-docs.js --only=members,claims --rollback`: 0 Änderungen — der Rollback stellt also exakt den heutigen Stand her.

**Stufe 0 — Functions (Reihenfolge wichtig):**

1. `node deploy-functions.js --only=admin-member-action,process-my-invitations --confirm=<projectId>` — **zuerst**: ab jetzt legen Server-Functions Member-Docs ohne `update("user:…")` an. Würde der neue Guard vorher laufen, löschte er Member-Docs, die die alte Function-Version noch mit dieser Rolle anlegt.
2. Build-Status beider in der Console „ready“ prüfen.
3. `node deploy-functions.js --only=on-claim-request,on-claim-confirmed,on-new-message,sync-supervisor-team --confirm=<projectId>`
4. Auf `sync-conversation-permissions` die Variable `CONV_LEGACY_TEAM_WRITE=true` anlegen (Console → Function → Settings → Variables), **dann** `node deploy-functions.js --only=sync-conversation-permissions --confirm=<projectId>`. Ohne die Variable würden neue Chats sofort nur-lesbar und die eingereichte App zeigt darin beim Senden einen Fehler.
5. `node deploy-functions.js --only=self-service,conversation-action --confirm=<projectId>` (legt sie an), dann `node set-function-vars.js --dry-run` → `node set-function-vars.js`. Dem API-Key Scope `users.read` geben (für `ensureUserDoc`; wird erst von App N genutzt).
6. Tests S1–S3 (§5), Functions-Logs von `sync-*` und `on-new-message` 15 min beobachten.

**Stufe 1 — Doc-ACLs members + claims:** `node lock-own-docs.js --only=members,claims` (Dry-Run, Zahlen wie oben?) → `node lock-own-docs.js --only=members,claims --confirm=<projectId>` → Tests S4–S6.

**Was das eingereichte Release danach nicht mehr kann** (alles andere geprüft unverändert: Login, Chats lesen/senden/anfragen/genehmigen, Gruppen, Pin, Mitglieder verwalten, Einladungen, Claims bestätigen/ablehnen, Reaktionen):

| ab | Funktion (alte App) | Verhalten |
|---|---|---|
| 0 | Eltern-Anfrage zurückziehen | Fehlermeldung (Anfragender hat kein `update` mehr) |
| 0 | Moderator lädt jemanden als **Moderator** ein (bereits registriert) | Fehlermeldung „Only admin can grant…“ (als Mitglied/Kind geht weiter) |
| 0 | Moderator ändert Rolle eines Admins/Moderators | Fehlermeldung |
| 0 | Guardians eines Kindes auf Nicht-Mitglieder/Kinder setzen | Fehlermeldung (UI bietet das ohnehin nicht an) |
| 0 | Nach dem Gründen einer **neuen** Org: Push-/Kind-Alarm-Intervall dieser Org ändern | Fehlermeldung (Guard entzieht dem Gründer-Doc die Schreibrechte — wie Stufe 1, nur früher) |
| 1 | Push-Intervall je Org, Kind-Alarm-Intervall | Fehlermeldung |
| 1 | „E-Mail verbergen“, Profilname/-foto | users-Doc wird gespeichert, Member-Docs still nicht (Mitgliederliste zeigt alten Stand) |

Windows-Alt-Clients verhalten sich genauso; die Web-App kann nach Stufe 2 sofort neu ausgerollt werden (kein Store).

**Rollback Stufe 0:** in der Console je Function das Deployment aus der Tabelle oben aktivieren; `self-service`/`conversation-action` deaktivieren (werden von der alten App nicht genutzt). `CONV_LEGACY_TEAM_WRITE` kann bleiben.
**Rollback Stufe 1 (öffnet die Lücke wieder!):** `node lock-own-docs.js --only=members,claims --rollback --confirm=<projectId>`.

## 5. Testanleitung

Vorab offline: `cd appwrite && node test-functions-mock.cjs` (In-Memory-Mock, prüft Rollenregeln von `conversation-action`, `self-service`, `sync-*`-Guards, `addMember`) — muss „… OK“ für alle fünf Blöcke ausgeben.

Konten wie in `collection-acl-hardening.md` §6: A (Admin), M (Moderator), P (Elternteil/Guardian), C (Kind von P), F (Mitglied), X (andere Org). Negativ-Tests per API mit der Session des jeweiligen Kontos (Web-App-DevTools oder `curl` + Cookie).

| # | Stufe | Test | Erwartung |
|---|---|---|---|
| S1 | 0 | Alte App: C fragt Chat mit F an; C ändert per API `status: approved` | `sync-conversation-permissions` lässt Status (Alt-ACL) stehen, aber `guardianUids` = [P] bleibt; nach Stufe 4: PATCH → 401 |
| S2 | 0 | X legt per API `members/{orgA}_{X}` mit `role: admin` an | Doc ist nach wenigen Sekunden gelöscht (Functions-Log „Guard: deleted“); X sieht keine Chats von orgA |
| S3 | 0 | P legt Claim an C mit `status: confirmed` an bzw. setzt ihn per API auf confirmed | Status wird `pending`, kein Eintrag in `users/C.verifiedParentUids` |
| S4 | 1 | F: `PATCH members/{org}_F {role: admin}` und `PATCH users/F {isChild: true}` | 401 |
| S5 | 1 | C: Guardians im eigenen Member-Doc leeren | 401 |
| S6 | 1 | C bestätigt Eltern-Anfrage von P in der neuen App | Verknüpfung erscheint bei beiden live |
| S7 | 2 | Neue App: Profilname + Foto ändern, „E-Mail verbergen“, Push-Intervall je Org, Kind-Alarm-Intervall, Benachrichtigungs-Einstellungen | gespeichert, in Mitgliederliste der Org sichtbar |
| S8 | 2 | Neues Konto per OTP registrieren | users-Doc entsteht (ACL `read user(self)`), Login klappt |
| S9 | 2 | F gründet eine Org | F ist Admin, Org erscheint sofort |
| S10 | 2 | F fragt Chat mit C an; M genehmigt; zweite Anfrage C→F | Chat erscheint live bei beiden; zweite Anfrage → „existiert bereits“ |
| S11 | 2 | C fragt Chat mit F an; P lehnt ab | Anfrage verschwindet live |
| S12 | 2 | P startet Direktchat mit C | sofort genehmigt |
| S13 | 2 | M: Gruppe anlegen, Mitglied hinzufügen/entfernen (System-Nachricht), Gruppenbild/-name, Nachricht anpinnen/lösen, archivieren, wiederherstellen | alles live bei allen Teilnehmern; Guardians eines hinzugefügten Kindes sind im Team |
| S14 | 2 | F: persönlicher Chatname im Direktchat | nur bei F sichtbar |
| S15 | 2 | Nachricht/Bild/Sprachnachricht/Datei/Umfrage senden | Chatvorschau + Sortierung in der Liste aktualisieren sich (jetzt über `on-new-message`, ~1 s Verzögerung) |
| S16 | 4 | C: `PATCH conversations/<id> {status: approved}` bzw. `DELETE` | 401 |
| S17 | 4 | X: `POST members` / `POST conversations` | 401 |
| S18 | 4 | Moderator: `addMember` mit `memberData.role = moderator` per API | 403 |

## 6. Offen / Folgearbeiten

- `org_invite_consents`: Einladender (Admin/Mod) legt die Zustimmungsanfrage selbst an und bestimmt `parentUids` → kann sich selbst als „Elternteil“ eintragen und zustimmen. Gehört zu Phase 2 (Consent serverseitig anlegen).
- Polls (Befund C): `update team(convId)` erlaubt fremde Stimmen/Fragen zu ändern.
- System-Nachrichten (`senderUid: system`) legt weiterhin der Client an → fälschbar (nur Anzeige).
- `members`/`users` read: Phase 2/3 der Collection-Härtung.
