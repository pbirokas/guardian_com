# Release-Review 141 → 182 — Notfall-Fix (Server)

Erstes `/release-review` (2026-11-26) über Build 141 → 182 (13 PRs). Dieses Dokument beschreibt den **reinen Server-Fix** für die kritischen, live ausnutzbaren Befunde. Kein App-Release nötig.

## Ursache

Die Phase-2-Collections hatten live noch breite Collection-Rechte:

| Collection | vorher | nachher |
|---|---|---|
| `organizations` | read/create/update/delete `users` | read/update `users` (Phase 2: update fällt mit App-Release) |
| `invitations` | read/create/delete `users` | keine |
| `org_invite_consents` | read/create/update/delete `users` | keine |

Mehrere Functions werteten Felder aus diesen **client-beschreibbaren** Docs als Berechtigung.

## Befunde und Fix

| # | Befund | Fix |
|---|---|---|
| K1 | `process-my-invitations` vertraute `invitedByUid`/`role` aus dem Einladungs-Doc → selbst angelegte Einladung = Admin einer fremden Org | Einladender = alleiniger `user:`-Eintrag der ACL **und** `invitedByUid`, live aktiver Admin/Mod. Rollen: `member`/`child`, `moderator` nur bei Admin als Einladendem, nie `admin`. Kind-Rolle nur für nach der Einladung angelegte Konten ohne verifizierte Eltern; Kind-Konten nie Nicht-Kind-Rolle. Guardians geprüft. Fehler pro Einladung isoliert. |
| K2 | `on-parent-consent` vertraute `status/childUid/orgId/proposedGuardianUids`; Einladender hatte `update` auf das Consent-Doc | Prüfung gegen Live-Daten: Kind-Konto, `parentUids` = verifizierte Eltern, jedes Elternteil hat `update` in der ACL und **nur** Eltern haben `update`, `approvedBy` ∈ Eltern, Einladender live Admin/Mod, nicht abgelaufen, Guardians gültig. Member-Doc ohne Kind-E-Mail, nur lesbar. `inviteByEmail` gibt dem Einladenden kein `update` mehr. |
| K3 | `org.adminUid` (client-beschreibbar) galt als Admin-Nachweis: `deleteOrg`-Fallback, `process-my-invitations`, Keyword-Alarm, `canApproveUids` | Rollen nur noch aus aktiven Member-Docs (`admin-member-action`, `process-my-invitations`, `on-new-message`, `conversation-action`, `sync-conversation-permissions`). Collection `organizations` ohne create/delete. |
| H1 | Moderator konnte die eigene Einladung auf `admin` umschreiben bzw. Kind-Einladungen an bestehende Konten richten | siehe K1 |
| H2 | `updateGuardians` prüfte nicht, ob das Ziel ein Kind ist | nur für `role: child`; `transferAdmin` nie an Kind/inaktive Mitglieder |
| H3 | `teams.listMemberships` ohne Pagination (25) → entfernte Mitglieder großer Chats behielten Zugriff | paginiert in beiden `sync-*`-Functions |
| H4 (teilweise) | Vorschau/Push für Nachrichten in nicht genehmigten Chats | `on-new-message`: keine Vorschau, kein Push bei `status != approved`; `sentAt` auf `$createdAt` begrenzt; `orgId` aus der Conversation |
| H7 | `fix-permissions.js` ohne Flags hätte Rechte wieder geöffnet | Live-Stand ist Standard; ohne `--rollback` fügt das Skript nie Rechte hinzu (`--allow-widen`) |

**Noch offen** (siehe Review-Bericht): Teilnehmer nicht genehmigter Chats sind weiter im Conv-Team (können per API Nachrichten lesen/schreiben — H4 vollständig); `organizations.update` (Keywords, Name, `memberUids`, `adminUid` änderbar — mit Phase 2 + App-Release); FCM-Token beim Logout; Web-Ressourcen von gstatic; mittlere/niedrige Befunde.

## Audit vor dem Fix (nur lesend, 2026-11-26)

- 11 Orgs: `adminUid` = einziges aktives Admin-Mitglied in allen → keine Spur einer Übernahme.
- `invitations` (2) / `org_invite_consents` (4): keine verdächtigen ACLs, keine offenen Docs.

## Rollout (Reihenfolge)

Aus `appwrite/`:

1. Functions deployen (Dry-Run, dann `--confirm`):
   ```bash
   node deploy-functions.js --only=process-my-invitations,on-parent-consent,admin-member-action,on-new-message,conversation-action,sync-conversation-permissions,sync-supervisor-team
   node deploy-functions.js --only=process-my-invitations,on-parent-consent,admin-member-action,on-new-message,conversation-action,sync-conversation-permissions,sync-supervisor-team --confirm=<projectId>
   ```
2. Doc-ACLs offener Einladungen/Zustimmungen angleichen (aktuell 0 betroffen):
   ```bash
   node harden-invites.js
   node harden-invites.js --confirm=<projectId>
   ```
3. Collection-Rechte:
   ```bash
   node fix-permissions.js --only=invitations,org_invite_consents,organizations
   node fix-permissions.js --only=invitations,org_invite_consents,organizations --confirm=<projectId>
   ```

## Live-Stand

| Datum | Schritt | Ergebnis |
|---|---|---|
| 2026-11-26 | 1 Functions | alle 7 aktiv: process-my-invitations `6b0821a53e03516e400a`, on-parent-consent `6b0821b052e7000bf67a`, admin-member-action `6b0821bb59685d942e95`, on-new-message `6b0821c132dd3ec23281`, conversation-action `6b0821cc37bb7b73ce4b`, sync-conversation-permissions `6b0821d20de84c38100d`, sync-supervisor-team `6b0821d7d7410a52c739`. Vorher (Rollback): `6af965ab49658035b9e8`, `6a61cdb01bbb4871ce6a`, `6b07161a3ff9005c30a0`, `6af965c00bff26505a80`, `6af965df83aa5cba8565`, `6b07e339454d40591d2f`, `6af965c0ab645cd52e93` |
| 2026-11-26 | 2 harden-invites | 0 Docs betroffen (Backup `backups/invites-acl-2026-11-26T12-11-17-717Z.json`) |
| 2026-11-26 | 3 Collections | `invitations` → `[]`, `org_invite_consents` → `[]`, `organizations` → `[read, update]`; `fix-permissions.js` Dry-Run danach: 0 Abweichungen |
| – | Tests R1–R8 | offen (Gerät / Wegwerf-Konto) |

## Tests nach dem Rollout (Gerät / Wegwerf-Konto)

| # | Test | erwartet |
|---|---|---|
| R1 | Admin lädt neue E-Mail als Mitglied ein, Empfänger registriert sich | wird Mitglied |
| R2 | Moderator lädt neue E-Mail als Kind mit Guardian ein; Guardian öffnet die Org | Guardian sieht die ausstehende Kind-Einladung; nach Registrierung Kind (ausstehend) |
| R3 | Admin lädt registriertes Kind mit verifizierten Eltern ein; Elternteil stimmt in der App zu | Kind wird Mitglied |
| R4 | Elternteil lehnt ab | Einladender bekommt „abgelehnt“ |
| R5 | Admin ändert Org-Einstellungen / Keywords / archiviert | funktioniert |
| R6 | Admin löscht eine Test-Org; Mitglied verlässt eine Org | funktioniert |
| R7 | Wegwerf-Konto ohne Org: `list invitations`, `list org_invite_consents`, `create invitations`, `delete organizations/<id>` per API | 0 Treffer bzw. 401 |
| R8 | Wegwerf-Konto setzt per API `adminUid` einer Test-Org auf sich und ruft `deleteOrg` auf | 403, Org bleibt |

## Rollback

- Functions: in der Console das vorherige Deployment je Function aktivieren.
- Collection-Rechte: `node fix-permissions.js --only=invitations,org_invite_consents,organizations --rollback --confirm=<projectId>` (öffnet die Lücken wieder — nur Notfall).
- Doc-ACLs: `node harden-invites.js --rollback=backups/invites-acl-<ts>.json --confirm=<projectId>`.
