# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Guardian Com is a Flutter app for supervised communication between children, guardians, and organizations. It targets Android, Windows and Web (PWA at `app.guardian-com.de`, primarily for iPhone/iPad users). The backend is a **self-hosted Appwrite** server (`appwrite.guardian-com.de`, Hetzner DE): auth (e-mail OTP), database `guardian`, storage, realtime and Functions. The Flutter app lives in `guardian_app/`; Appwrite schema/maintenance scripts and Functions live in `appwrite/` (`appwrite/functions/<id>/src/main.js`). **Firebase is only used for FCM push and Crashlytics on Android** — no Firestore, Firebase Auth or Firebase Storage.

## Common Commands

All Flutter commands run from `guardian_app/`:

```bash
# Run on connected device
flutter run

# Build Android debug APK
flutter build apk --debug

# Build Android release APK
flutter build apk --release

# Run unit tests (e.g. test/realtime_broadcaster_test.dart)
flutter test

# Regenerate localizations (after editing any .arb file)
flutter gen-l10n
# Note: l10n.yaml is present, so gen-l10n uses it automatically.
# The generated files land in lib/l10n/ — commit them.

# Analyze code
flutter analyze
```

Appwrite (run from `appwrite/`, CLI is logged in against `appwrite.guardian-com.de`):

```bash
npm install                                        # deps for the maintenance scripts
node setup.js                                      # create/extend collections, attributes, indexes (idempotent)
appwrite push function --function-id <id>          # deploy one Function (e.g. on-new-message)
node set-function-vars.js                          # set APPWRITE_API_KEY etc. on Functions (redeploy afterwards)
```

## Architecture

### Flutter App (`guardian_app/lib/`)

**State management:** Riverpod 3.x with hand-written providers (`Provider`, `StreamProvider`, `AsyncNotifierProvider` …) — no code generation, no `riverpod_generator`/`build_runner`. `flutter_riverpod` must stay ≥ 3.3.2 (fix for the unpause assertion `pausedActiveSubscriptionCount`); `riverpod` ≥ 3.3.2 needs `uuid` ^4.5, hence the `dependency_overrides: uuid` in `pubspec.yaml` for `system_tray` 2.0.3 (it only uses `const Uuid().v1()`).

**Navigation:** GoRouter via `routerProvider` in `core/router/app_router.dart`. Routes: `/login`, `/organizations`, `/org/:orgId`, `/chat/:chatId`, `/profile`, `/relationships`.

**Feature structure** (`features/`):
- `auth/` — Login screen (e-mail OTP), `authStateProvider` (`AuthNotifier`, wraps the Appwrite account/session)
- `organizations/` — Org list, org detail with member list + chat tabs
- `chat/` — Full chat screen (messages, polls, scheduled messages, file/image/voice)
- `profile/` — Settings, notification preferences, privacy
- `relationships/` — Cross-account parent-child claim flow
- `share/` — Share-Target: `SharePickerSheet` (bottom sheet, shown via `_ShareListener` in `main.dart`)

**Core layer** (`core/`):
- `models/` — Plain Dart classes with `fromAppwrite`/`toAppwrite`. No logic beyond serialization.
- `services/` — All Appwrite (Databases/Storage/Functions/Realtime) and FCM calls. Key services: `OrganizationService`, `ChatService`, `NotificationService`, `ParentClaimService`, `ShareService`.
- `providers/` — UI-state providers (theme, locale, font size, connectivity, `pendingShareProvider`).
- `widgets/` — Shared widgets used across features.

**Localization:** Two ARB files — `lib/l10n/app_de.arb` (template) and `app_en.arb`. Always add strings to **both** files. Run `flutter gen-l10n` after every ARB change. The generated `app_localizations*.dart` files are committed.

### Key domain concepts

**OrgRole:** `admin > moderator > member > child`. Defined in `core/models/org_member.dart`. A `child` account (`isChild: true` on the user doc) can never hold any role other than `child`.

**ChatMode:** `guardian` (request + approval flow) or `sheltered` (admin pre-assigns connections, group chats allowed). Set at org creation, immutable after.

**Conversation model** (`core/models/conversation.dart`):
- `isGroup` — group chat vs. 1-on-1
- `status` — `pending | approved | rejected | archived`
- `participantUids` — actual chat members
- `guardianUids` — guardians of child participants (propagated by the Function `on-member-guardians-changed`)
- `canApproveUids` — snapshot of admin/mod UIDs at creation (may be stale; supervisors get access via the conversation team, see conventions)
- `personalNames` — per-user display names for direct chats (`Map<uid, name>`)

**Guardian propagation:** When `members/{memberId}.guardianUids` changes, the Function `on-member-guardians-changed` propagates `guardianUids` into all affected conversations with the API key (not client-side — clients may only write documents their ACL allows).

### Appwrite Functions (`appwrite/functions/`)

Node.js Functions, deployed with the Appwrite CLI (`appwrite push function --function-id <id>`), configured in `appwrite/appwrite.config.json`. They use the project API key from `APPWRITE_API_KEY` (set via `set-function-vars.js`) and must rewrite `APPWRITE_FUNCTION_API_ENDPOINT` from `http://` to `https://` (Traefik redirect breaks node-fetch otherwise). Key Functions:
- `on-new-message` (event: chat_messages.create) — FCM push respecting per-user alert intervals, guardian alerts, keyword alerts
- `on-member-guardians-changed` (event: members.update) — propagates guardian changes to conversations
- `sync-conversation-permissions` / `sync-supervisor-team` — conversation team membership (see conventions)
- `on-new-invitation` (event: invitations.create) — invitation e-mail via Gmail SMTP (`GMAIL_APP_PASSWORD`) + FCM
- `mark-as-read`, `moderate-message`, `admin-member-action`, `get-child-summary`, `revoke-connection` — callables (from the app only via `executeRaw`)
- `delete-account` — account deletion: `check` (blocks) and `start` (sync, re-checks, then enqueues an **async** `run` of itself); idempotent, 10-min budget per run, re-enqueues itself, schedule `*/15` resumes stale runs (`users.deletionStatus='deleting'`). `startForChild { childUid }`: a mutually verified parent deletes the child's account (one parent suffices, co-parents get an FCM push; `users.deletionRequestedBy` lifts the `childHasParents` block for the run). Needs `FCM_SERVICE_ACCOUNT_B64`/`FCM_PROJECT_ID` on the Function for that push (without them it only logs)
- `cleanup-expired-polls` / `cleanup-expired-announcements` / `cleanup-old-messages` (schedules), `daily-error-report` (07:00 e-mail of failed executions)

FCM is called via the HTTP v1 API with a service account (`FCM_SERVICE_ACCOUNT_B64`, `FCM_PROJECT_ID`). FCM messages always set `android.priority: 'high'` at the message level to bypass Doze mode.

### Share-Target (Android)

`AndroidManifest.xml` registers `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent filters for `text/plain`, `image/*`, `*/*`. `MainActivity.kt` exposes a `com.guardianapp.guardian_app/share` MethodChannel with two methods:
- `getSharedData()` — returns type/text/uris/fileNames/mimeType from the pending intent (cold-start or `onNewIntent`), then clears it
- `readUri(uri)` — reads a content URI as raw bytes (ByteArray → Uint8List)

Flutter side: `ShareService` wraps the channel; `pendingShareProvider` (Notifier) holds the pending share; `_ShareListener` (ConsumerWidget inside `MaterialApp.router`'s builder) listens and opens `SharePickerSheet`. The sheet uses `router.routerDelegate.navigatorKey.currentContext` for `showModalBottomSheet` to avoid the "no Navigator" error that occurs when showing from above `MaterialApp`.

Conversations in the picker are filtered to the user's current orgs (`myOrganizationsProvider`). Direct-chat titles resolve via `memberDisplayNameProvider((orgId:, uid:))` (FutureProvider.family on the partner's member doc — foreign users docs are not readable).

### Realtime / WebSocket

All Appwrite Realtime subscriptions go through a single shared `RealtimeBroadcaster` instance provided by `appwriteRealtimeBroadcasterProvider` (in `core/appwrite_client.dart`). The broadcaster owns the `Realtime` instance and ref-counts subscriptions per channel: multiple services listening to the same collection share one subscription; when the last listener leaves, the channel is `unsubscribe()`d in the SDK (never `close()` — that sets the SDK's `_reconnect=false`). Services receive a `RealtimeBroadcaster` via constructor injection and call `broadcaster.stream(channel)` instead of creating their own `Realtime` instance. **Since Appwrite SDK v24 one WebSocket stays open permanently** (subscriptions are sent as messages, not encoded in the URL), so a socket opened with a stale/absent session never heals by itself. To refresh the connection (app resume, back online, login/user switch) call `broadcaster.reconnect()` — it swaps in a fresh `Realtime` instance, re-subscribes all active channels and emits an empty `RealtimeMessage` so listeners reload missed data. Do **not** `ref.invalidate` services for this: rebuilding them tears down every stream (and before riverpod 3.3.2 tripped the `pausedActiveSubscriptionCount` assertion), and rebuilding `authStateProvider` bounces the router to `/organizations`. Only logout invalidates `appwriteRealtimeBroadcasterProvider` (its `onDispose` disconnects the old socket). `AuthService` must not depend on the broadcaster (pass it as a parameter instead), because `authStateProvider` depends on `AuthService`. Listeners must tolerate the empty resync event (`events` empty). The Realtime cookie workaround `createPatchedRealtime` relies on SDK internals (`getWebSocket`, `getFallbackCookie`, `cookieJar`) — re-check on every SDK upgrade.

### Web (PWA)

Flutter-Web-Build, gehostet als Appwrite Site unter `app.guardian-com.de`; Auslieferung per `npm run deploy-web` in `appwrite/` (`deploy-web.js`: Build-Nummer = `git rev-list --count HEAD` wie der Android-versionCode, Upload über die Sites-API mit `APPWRITE_DEPLOY_KEY`, explizites Aktivieren), zusammen mit jedem Android-Release. Nie `flutter build web` ohne `--build-number` ausliefern — sonst zeigt „Über die App“ Build 1. Regeln:
- **Kein `dart:io` in gemeinsam genutztem Code.** Plattform per `kIsWeb` / `defaultTargetPlatform` prüfen — im Browser meldet `defaultTargetPlatform` das Betriebssystem (iOS auf dem iPhone, windows am PC), deshalb **immer zuerst `kIsWeb` ausschließen**. Natives in `*_io.dart`/`*_web.dart` (bzw. `*_stub.dart`) per Conditional Import: `realtime_patch_*` (Realtime-Cookie-Workaround nur nativ), `core/utils/export_file*` (Temp-Datei+OpenFilex vs. Browser-Download), `core/utils/pwa_env*` (iOS-Browser-/PWA-Erkennung).
- Im Web werden Firebase, Crashlytics und FCM **nicht** initialisiert (Web Push kommt in Stufe 2; dann Web-`firebase_options`, Service Worker, VAPID-Key). Ausgeblendet: Share-Target, Akku-Optimierung, Update-Prüfung, Sprachaufnahme.
- Bildkomprimierung im Web über `flutter_image_compress` + **selbst gehostetes** `web/pica.min.js` (kein CDN — keine Nutzer-IPs an Dritte).
- **Caching:** Appwrite Sites sendet kein `Cache-Control` → Browser behalten alten `main.dart.js` tagelang (Version in „Über die App“ kommt live aus `version.json` und täuscht). Traefik setzt dafür `Cache-Control: no-cache` für `app.guardian-com.de` (Labels in `~/appwrite/docker-compose.override.yml`, Anleitung/Prüfung `docs/ops/web-cache-headers.md`). Nach Appwrite-Upgrades prüfen. Bei „neuer Code wirkt nicht“ zuerst `curl -sI https://app.guardian-com.de/main.dart.js` und die Function-Executions ansehen.
- Session = Browser-Cookie von `appwrite.guardian-com.de` (gleiche Hauptdomain wie die App → first-party). Kein Cookie-Jar im Web (`_clearCookieJar` ist dort No-op).

### Desktop (Windows)

Windows uses Appwrite Realtime listeners (`DesktopNotificationService`) for notifications instead of FCM; Firebase is not initialized on Windows. `TrayService` manages the system tray icon; `DesktopNotificationService` shows native toasts. Platform-specific code is behind stub files (`*_stub.dart`) to keep Android unaffected.

## Important Conventions

- **After editing `.arb` files:** always run `flutter gen-l10n` and commit the generated files.
- **After changing `RealtimeBroadcaster`:** run `flutter test` (`test/realtime_broadcaster_test.dart` covers ref-counting, unsubscribe, reconnect/resync).
- **Chat-Berechtigungen laufen über Appwrite Teams (nicht `Role.users()`):** **Ein Chat = ein Team** (Team-ID = `convId`). Mitglieder = Teilnehmer + Guardians + **Aufsicht** (Admin/Moderatoren der Org). Die ACL von Conversation, Nachricht, Poll-Nachricht etc. referenziert **nur `team(convId)`** — bewusst, denn beim Erstellen eines Dokuments erlaubt Appwrite dem Client nur Permissions für Rollen, die er selbst hat; ein normales Mitglied kann `team(convId)` setzen (es ist Mitglied), aber **kein** org-weites Aufsichts-Team. Deshalb sitzt die Aufsicht **im Conv-Team** statt in einem separaten ACL-Team. Team-Mitgliedschaft wird **ausschließlich serverseitig** gepflegt:
  - `sync-conversation-permissions` (Trigger: conversations create/update/delete) — Conv-Team = Teilnehmer + Guardians + Supervisoren; setzt die Conv-ACL auf `team(convId)`.
  - `sync-supervisor-team` (Trigger: members create/update/delete) — propagiert Rollenänderungen (Admin/Mod) in **alle** Conv-Teams der Org. `sup_<orgId>` ist dabei **kein ACL-Team**, sondern nur ein Änderungs-Detektor-Cache (spart die Conv-Iteration, wenn sich der Supervisor-Satz nicht ändert).
  - **Conversations schreibt der Client nie direkt** — Anlegen, Genehmigen/Ablehnen, Archivieren, Gruppen-Infos, Mitglieder, Pin, persönlicher Name laufen über die Callable **`conversation-action`** (Rollen live aus dem Member-Doc; `guardianUids`/`canApproveUids` berechnet der Server). Conv-ACL = nur `read team(convId)` (seit 2026-11-26 ohne Übergangs-Var `CONV_LEGACY_TEAM_WRITE` — nicht wieder setzen; kein `update`/`delete` — Appwrite kennt keine Feld-Rechte, sonst ändert jeder Teilnehmer `status`/`participantUids`/`guardianUids`). `lastMessage`/`lastMessageAt` setzt `on-new-message`. `sync-conversation-permissions` berechnet `guardianUids` bei jedem Event neu und prüft Chats, die alte Apps noch direkt anlegen. **Jede neue Nachrichten-Art muss `_msgPerms(convId)` in `chat_service.dart` verwenden** (= `read team(convId)` + `read/update/delete user(self)`; nie `Role.users()`/`Role.any()`/ein Aufsichts-Team auf client-erstellten Chat-Dokumenten).
  - **Fremd-Moderation** (Admin/Mod bearbeitet/archiviert eine fremde Nachricht) läuft über die Callable-Function **`moderate-message`** (API-Key, prüft Rolle) — die Nachrichten-ACL gibt nur dem Autor Schreibrechte. Eigene Nachrichten bearbeitet/löscht der Autor direkt.
  - **Polls** folgen demselben Team-Modell (`_pollPerms(convId)` = `read/update team(convId)`, `delete user(self)`). **Reports** sind auf die Aufsicht beschränkt: der Client legt sie mit `Role.user(self)` an, die Function `on-new-report` überschreibt die ACL auf Admin+Moderatoren (Client kann fremde Aufsichts-Rollen nicht granten).
  - Migration/Backfill: `appwrite/harden-permissions.js` (Dry-Run default, `--confirm=<projectId>`) — deckt Conversations, Nachrichten, geplante Nachrichten, Polls, Reports, Read-Receipts und Claim-Requests ab und zählt Docs mit breiten Rechten.
  - **Collection-Level-Rechte höchstens `create("users")`** — Appwrite wertet Collection- und Doc-Rechte additiv aus; ein `read/update/delete("users")` auf Collection-Ebene hebelt jede Doc-ACL aus. Realtime braucht kein Collection-read (Event geht an jeden mit Doc-read). Soll-Zustand + Rollback in `appwrite/fix-permissions.js` (Dry-Run default, `--only=…`, `--confirm=<projectId>`); Plan/Audit/Testanleitung in `docs/security/collection-acl-hardening.md` (Phase 1 Chat-Daten und Phase 3 `users` live; Phase 2 Org-Daten offen — members-Docs inkl. E-Mail noch für jedes Konto lesbar). **Jeder neue Schreibpfad auf ein fremdes Dokument braucht eine Doc-ACL oder eine Function** — nie auf Collection-Rechte verlassen. Reaktionen/Termin-Zusagen laufen deshalb über **`set-reaction`** (keine Feld-Rechte in Appwrite), Fremd-Soft-Delete über `moderate-message` (`action: softDelete`), Chat löschen über `admin-member-action/deleteConversation`, `pendingReportsCount` zählt `on-new-report` serverseitig neu. Nie `appwrite push tables` (Config hat leere `$permissions`).
  - **Read-Receipts** (`read_receipts`, ein Doc pro convId+uid) schreibt nur `mark-as-read`: ACL `read user(uid)` + **nur bei Teilnehmern** `read team(convId)` (Lesestatus-Häkchen; Guardians/Aufsicht bleiben privat und zählen nicht als Leser), kein Client-`update`/`delete`. Lesestatus im Chat über `conversationReadReceiptsProvider`, nie über Felder am Conversation-Doc. Bestand: `appwrite/share-read-receipts.js` (Dry-Run default, `--rollback`).
  - **Offen (breiter Lesezugriff, separates Audit):** Storage-Media-Dateien (`Role.any()`) — Bild/Voice/Datei/Avatar. Entschärft, da die Datei-URLs in den (jetzt team-beschränkten) Nachrichten-Dokumenten stehen und File-IDs zufällig sind; echte Härtung braucht signierte URLs/JWT (bricht sonst `CachedNetworkImage`/Audio-Anzeige).
- **`users`- und `members`-Docs sind für Clients nur lesbar** (users: `read user(uid)`, members: `read("users")`; keine `update`/`delete`-Rechte, keine Collection-`create`; live seit 2026-11-26). Sonst Selbst-Eskalation: `role: "admin"` im eigenen Member-Doc, `isChild`/`verifiedParentUids`/`guardianUids` beim Kind. Eigene Felder ändert die App nur über die Callable **`self-service`** (feste Feld-Whitelist je Aktion: Profil, `hideEmail`, Benachrichtigungen, `fcmToken`, Intervalle, Org gründen, users-Doc anlegen, Eltern-Anfrage beantworten). **Neues selbst-editierbares Feld → neue Aktion in `self-service`, nie Doc-ACL lockern.** Server-Functions legen Member-Docs **ohne** `update("user:…")` an — daran erkennt der Guard in `sync-supervisor-team` client-angelegte Docs (fremde Org + `role: admin`) und löscht sie. Eltern-Anfragen (`claim_requests`): Status nur über `self-service/respondClaim`; der Anfragende hat kein `update` (`on-claim-confirmed` prüft das). Migration: `appwrite/lock-own-docs.js` (`--rollback` nur Notfall); Functions deployen mit `appwrite/deploy-functions.js --only=…` (Dry-Run default; nie `appwrite push functions`, setzt Spezifikation zurück); Plan/Rollout/Tests: `docs/security/self-escalation.md`; Mock-Test: `node appwrite/test-functions-mock.cjs`.
- **Nie Felder aus client-beschreibbaren Docs als Berechtigung werten** (Release-Review 182, `docs/security/release-review-182.md`): Rollen nur aus **aktiven Member-Docs**, nie aus `org.adminUid` (Org-Doc ist bis Phase 2 client-beschreibbar), nie aus `invitedByUid`/`role` eines Einladungs-Docs oder `status`/`orgId`/`childUid` eines Consent-Docs. Ersteller eines Docs = `user:`-Eintrag der ACL (ein Client kann nur sich selbst granten). `invitations` und `org_invite_consents` haben **keine** Collection-Rechte; Einladungen legt nur `admin-member-action/inviteByEmail` an (ACL: Einladender + lesend Guardians), Zustimmungen ebenfalls (ACL: Einladender read/delete, Eltern read/update — **kein** update für den Einladenden). `process-my-invitations` vergibt nie `admin`; `on-parent-consent` prüft Eltern/ACL/Einladenden live. Team-Mitgliedschaften immer paginiert lesen (`listMemberships` liefert sonst nur 25). Doc-ACL-Migration: `appwrite/harden-invites.js`.
- **Fremde `users`-Docs liest der Client nie** (Phase 3, live seit 2026-11-26: Collection `users` ohne Rechte, Doc-ACL nur `read user(uid)`). Nur das eigene Doc (Login, Profil, Einstellungen, Realtime auf `…users.documents.<eigene uid>`). Anzeigename/Foto anderer Nutzer aus deren **Member-Doc** (`{orgId}_{uid}`, `memberDisplayNameProvider`); E-Mail-Lookup nur serverseitig (`admin-member-action/inviteByEmail`, `self-service/sendClaim`); Verwandte über `self-service/listRelatives` (Whitelist uid/displayName/email/photoUrl + `coParents`, nur gegenseitige Links). **Braucht die App ein weiteres Feld eines fremden Nutzers → Whitelist-Auszug in einer Function, nie Doc-read granten** (Appwrite kennt keine Feld-Rechte; das users-Doc enthält `fcmToken`, `membershipsJson`, Einstellungen). Migration/Audit: `appwrite/harden-users.js` (Dry-Run default, `--confirm=<projectId>`, Backup + `--rollback=<backup.json>`); Collection: `fix-permissions.js --after-app-n --phase3 --only=users`.
- **Neue Function-Deployments prüfen, ob sie aktiv sind:** `activate` beim Upload greift auf Server 1.9.x nicht zuverlässig (Build `ready`, alte Version bleibt aktiv). `deploy-functions.js`/`deploy-web.js` aktivieren deshalb explizit nach dem Build — bei manuellen Deploys (Console/CLI) danach `deploymentId` der Function kontrollieren.
- **Function-Aufrufe aus der App nur über `executeRaw`** (Extension auf `Functions` in `core/appwrite_client.dart`), **nie `Functions.createExecution`**: SDK 26.x baut ein `Execution`-Model mit Pflichtfeld `resourceType`, das Server 1.9.x nicht liefert → `StateError: No element`, obwohl die Function erfolgreich lief (Fehler bleibt unsichtbar, da Server-Logs sauber sind; SDK-Bug — es fordert selbst Format 1.9.6 an). `executeRaw` muss `X-Appwrite-Project` selbst senden (SDK 26 setzt ihn nicht global; sonst 403 „Invalid Origin“). Bei jedem SDK-/Server-Upgrade prüfen, ob `createExecution` wieder funktioniert, und die Header mit `Functions.createExecution` abgleichen.
- **Häufige Function-Aufrufe ohne benötigtes Ergebnis asynchron (`executeRaw(..., xasync: true)`):** Eine synchrone Execution hält serverseitig einen API-Worker fest, bis die Function fertig ist; ruft die Function dieselbe API zurück (jede Function mit `Databases`/`Teams`), landet dieser Rückruf gelegentlich auf genau diesem Worker → beide hängen bis zum Function-Timeout (503), und Event-Functions, deren Rückrufe dort landen, hängen mit. Belegt am 2026-11-13 für `mark-as-read` (Rückruf wurde erst ~20 ms nach dem 10-s-Timeout bedient, API sonst leer). Synchron nur, wenn die App das Ergebnis wirklich braucht (z. B. `get-child-summary`, `moderate-message`) — und dort `statusCode` prüfen, `executeRaw` wirft bei Function-Fehlern nicht.
- **Appwrite-Indexe:** Jedes Attribut, auf das eine Query filtert oder sortiert, braucht einen Index in `appwrite/setup.js` (`idx(...)`) — auch Array-Felder (`Query.contains`). Ein Composite-Index deckt nur **führende** Felder ab: `(convId, sentAt)` bedient `sentAt` allein **nicht**. Fehlende Indexe fallen oft spät auf (der Collection-Scan funktioniert, bis die Collection wächst) und äußern sich dann als sporadische 500er/Timeouts in geplanten Functions. Nach dem Ergänzen `node setup.js` ausführen und den Index-Status auf „available" prüfen — Appwrite legt Indexe asynchron an.
- **Kontolöschung (`delete-account`) muss jede neue personenbezogene Datenart abdecken:** Neue Collection/neues Feld mit uid, Name oder Inhalt eines Nutzers → in `deleteEverything`/`anonymizeOrgData`/`leaveGroup` löschen oder anonymisieren (+ Mock-Test). Gelöschte Konten stehen in Inhalten anderer als `Gelöschter Nutzer` (`DELETED_NAME` = `kDeletedUserName` in `message.dart`, App zeigt `l.deletedUser`). Reihenfolge: Auth-Konto (`Users.delete`) **vor** dem users-Doc, sonst legt `ensureUserDoc` es neu an. Abgestimmte Regeln (1:1-Chats löschen, Gruppen-Platzhalter, Sperren) stehen im Kopf von `functions/delete-account/src/main.js`.
- **Chat aus Benachrichtigung öffnen nur über `openChatFromNotification`** (`core/router/chat_navigation.dart`), nie direkt `router.push('/chat/…')`: sonst stapeln sich Chat-Seiten und „Zurück" braucht mehrere Anläufe. Ob gerade ein Chat offen ist, beantwortet `chatIdFromPath`.
- **Bilder einer Nachricht:** `imageUrls` (String-Array) enthält alle Bilder einer Mehrfach-Bild-Nachricht und wird nur bei mehr als einem Bild geschrieben; `imageUrl` enthält immer das erste Bild (ältere App-Versionen kennen nur dieses Feld). In Dart `Message.allImageUrls` lesen; serverseitiger Code, der Mediendateien einer Nachricht verarbeitet (z. B. Löschen), muss beide Felder berücksichtigen. Versand immer über `ChatService.sendImages` (max. `maxImagesPerMessage` pro Nachricht).
- **New attributes:** add them to `appwrite/setup.js` (and run `node setup.js`); access is controlled by collection/document permissions, not by rules files.
- **Functions and client code must stay in sync:** if a Function writes a new field, add it to the corresponding Dart model's `fromAppwrite`.
- **`firebase_options.dart` is gitignored** (contains API keys, Android only — FCM + Crashlytics). The example file `firebase_options.example.dart` shows the required structure.
- **Changelog & README:** update both files when adding features or fixing notable bugs.
- **App-Release → Update-Manifest pflegen:** Bei jedem neuen Android-Release das Appwrite-Dokument `app_config/android` aktualisieren (`latestVersionCode`/`latestVersionName`, ggf. `minVersionCode`). Die In-App-Update-Prüfung vergleicht die Build-Nummer (`versionCode`) dagegen; `minVersionCode` erzwingt ein Update. Erst setzen, wenn der neue Build tatsächlich verfügbar ist, sonst sperrt man Nutzer ohne verfügbares Update aus.
