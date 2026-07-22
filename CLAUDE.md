# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Guardian Com is a Flutter + Firebase app for supervised communication between children, guardians, and organizations. It targets Android and Windows. The Flutter app lives in `guardian_app/`, backend logic in `functions/` (Node.js Firebase Cloud Functions), and Firebase config at the repo root.

## Common Commands

All Flutter commands run from `guardian_app/`:

```bash
# Run on connected device
flutter run

# Build Android debug APK
flutter build apk --debug

# Build Android release APK
flutter build apk --release

# Regenerate Riverpod providers (after changing @riverpod annotations)
dart run build_runner build --delete-conflicting-outputs

# Regenerate localizations (after editing any .arb file)
flutter gen-l10n
# Note: l10n.yaml is present, so gen-l10n uses it automatically.
# The generated files land in lib/l10n/ — commit them.

# Analyze code
flutter analyze
```

Firebase deploy commands run from the repo root:

```bash
# Deploy everything
firebase deploy

# Deploy only specific targets
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only functions,firestore:rules,firestore:indexes
```

Cloud Functions (`functions/`):

```bash
cd functions && npm install
```

## Architecture

### Flutter App (`guardian_app/lib/`)

**State management:** Riverpod 3.x with code generation (`@riverpod`). After adding or changing a `@riverpod` annotation, run `build_runner` to regenerate `.g.dart` files.

**Navigation:** GoRouter via `routerProvider` in `core/router/app_router.dart`. Routes: `/login`, `/organizations`, `/org/:orgId`, `/chat/:chatId`, `/profile`, `/relationships`.

**Feature structure** (`features/`):
- `auth/` — Login screen, `authStateProvider` (wraps `FirebaseAuth.authStateChanges`)
- `organizations/` — Org list, org detail with member list + chat tabs
- `chat/` — Full chat screen (messages, polls, scheduled messages, file/image/voice)
- `profile/` — Settings, notification preferences, privacy
- `relationships/` — Cross-account parent-child claim flow
- `share/` — Share-Target: `SharePickerSheet` (bottom sheet, shown via `_ShareListener` in `main.dart`)

**Core layer** (`core/`):
- `models/` — Plain Dart classes with `fromFirestore`/`toFirestore`. No logic beyond serialization.
- `services/` — All Firestore and FCM calls. Key services: `OrganizationService`, `ChatService`, `NotificationService`, `ParentClaimService`, `ShareService`.
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
- `guardianUids` — guardians of child participants (propagated by Cloud Function on member doc change)
- `canApproveUids` — snapshot of admin/mod UIDs at creation (may be stale; rules also do a live `isAdminOrMod` check)
- `personalNames` — per-user display names for direct chats (`Map<uid, name>`)

**Guardian propagation:** When `members/{memberId}.guardianUids` changes, the Cloud Function `onMemberGuardiansChanged` propagates `guardianUids` into all affected conversations via Admin SDK (not client-side, to avoid Firestore rule issues for moderators).

### Firestore Security Rules (`firestore.rules`)

Conversations use a `canAccessConv()` helper that checks `participantUids`, `guardianUids`, `canApproveUids`, and a live `isAdminOrMod(orgId)` call. The live check is necessary because `canApproveUids` can become stale when roles change. Pinning messages has a stricter sub-rule within the update block.

### Cloud Functions (`functions/index.js`)

All functions deploy to `europe-west3` (same region as Firestore). Key functions:
- `sendMessage` (onCall) — sends FCM notifications respecting per-user alert intervals
- `onMemberGuardiansChanged` (onDocumentUpdated) — propagates guardian changes to conversations
- `sendInvitationEmail` (onCall) — sends email invitations via Gmail SMTP (secret: `GMAIL_APP_PASSWORD`)
- `cleanupExpiredPolls` (onSchedule, daily 03:05) — closes polls past their expiry date
- `processClaimRequest` (onDocumentUpdated) — handles parent-child link confirmation

FCM messages always set `android.priority: 'high'` at the message level to bypass Doze mode.

### Share-Target (Android)

`AndroidManifest.xml` registers `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent filters for `text/plain`, `image/*`, `*/*`. `MainActivity.kt` exposes a `com.guardianapp.guardian_app/share` MethodChannel with two methods:
- `getSharedData()` — returns type/text/uris/fileNames/mimeType from the pending intent (cold-start or `onNewIntent`), then clears it
- `readUri(uri)` — reads a content URI as raw bytes (ByteArray → Uint8List)

Flutter side: `ShareService` wraps the channel; `pendingShareProvider` (Notifier) holds the pending share; `_ShareListener` (ConsumerWidget inside `MaterialApp.router`'s builder) listens and opens `SharePickerSheet`. The sheet uses `router.routerDelegate.navigatorKey.currentContext` for `showModalBottomSheet` to avoid the "no Navigator" error that occurs when showing from above `MaterialApp`.

Conversations in the picker are filtered to the user's current orgs (`myOrganizationsProvider`). Direct-chat titles resolve via `userDisplayNameProvider(uid)` (FutureProvider.family, cached per UID).

### Realtime / WebSocket

All Appwrite Realtime subscriptions go through a single shared `RealtimeBroadcaster` instance provided by `appwriteRealtimeBroadcasterProvider` (in `core/appwrite_client.dart`). The broadcaster ref-counts subscriptions per channel: multiple services listening to the same collection share one WebSocket slot. Services receive a `RealtimeBroadcaster` via constructor injection and call `broadcaster.stream(channel)` instead of creating their own `Realtime` instance. When invalidating `appwriteRealtimeProvider` (on logout or reconnect), always also invalidate `appwriteRealtimeBroadcasterProvider`.

### Desktop (Windows)

Windows uses Firestore listeners for notifications instead of FCM. `TrayService` manages the system tray icon; `DesktopNotificationService` shows native toasts. Platform-specific code is behind stub files (`*_stub.dart`) to keep Android unaffected.

## Important Conventions

- **After editing `.arb` files:** always run `flutter gen-l10n` and commit the generated files.
- **After adding `@riverpod` annotations:** run `dart run build_runner build --delete-conflicting-outputs`.
- **Chat-Berechtigungen laufen über Appwrite Teams (nicht `Role.users()`):** Jeder Chat ist durch zwei Teams abgesichert — das **Conversation-Team** (Team-ID = `convId`, Mitglieder = Teilnehmer + Guardians) und das **Org-Supervisor-Team** (Team-ID = `sup_<orgId>`, Mitglieder = Admin + Moderatoren, org-weite Aufsicht). Die ACL von Conversation, Nachricht, Poll-Nachricht etc. referenziert nur diese Teams. Team-Mitgliedschaft wird **ausschließlich serverseitig** von den Functions `sync-conversation-permissions` (Trigger: conversations create/update/delete) und `sync-supervisor-team` (Trigger: members create/update/delete) gepflegt — Clients dürfen keine fremden Team-Mitgliedschaften setzen. Der Client legt Conversations nur mit `Role.user(self)` an; die Function setzt danach das Team-Modell. **Jede neue Nachrichten-Art muss `_msgPerms(convId, orgId)` in `chat_service.dart` verwenden** (nie `Role.users()`/`Role.any()` auf DB-Dokumente mit Chat-Inhalt). Der Team-ID-Ausdruck `sup_$orgId` muss zwischen Client (`chat_service.dart`) und Functions identisch bleiben. Migration/Backfill bestehender Daten: `appwrite/harden-permissions.js` (Dry-Run default, `--confirm=<projectId>`). **Offen (breiter Lesezugriff, separates Audit):** `polls`- und `reports`-Collection sowie Storage-Media-Dateien (`Role.any()`).
- **Appwrite-Indexe:** Jedes Attribut, auf das eine Query filtert oder sortiert, braucht einen Index in `appwrite/setup.js` (`idx(...)`) — auch Array-Felder (`Query.contains`). Ein Composite-Index deckt nur **führende** Felder ab: `(convId, sentAt)` bedient `sentAt` allein **nicht**. Fehlende Indexe fallen oft spät auf (der Collection-Scan funktioniert, bis die Collection wächst) und äußern sich dann als sporadische 500er/Timeouts in geplanten Functions. Nach dem Ergänzen `node setup.js` ausführen und den Index-Status auf „available" prüfen — Appwrite legt Indexe asynchron an.
- **Firestore rules:** when adding new fields that require write restrictions, update `firestore.rules` accordingly. The existing broad `canAccessConv()` update rule covers most conversation fields.
- **Cloud Functions and client code must stay in sync:** if a Cloud Function writes a new field, add it to the corresponding Dart model's `fromFirestore`.
- **`firebase_options.dart` is gitignored** (contains API keys). The example file `firebase_options.example.dart` shows the required structure.
- **Changelog & README:** update both files when adding features or fixing notable bugs.
- **App-Release → Update-Manifest pflegen:** Bei jedem neuen Android-Release das Appwrite-Dokument `app_config/android` aktualisieren (`latestVersionCode`/`latestVersionName`, ggf. `minVersionCode`). Die In-App-Update-Prüfung vergleicht die Build-Nummer (`versionCode`) dagegen; `minVersionCode` erzwingt ein Update. Erst setzen, wenn der neue Build tatsächlich verfügbar ist, sonst sperrt man Nutzer ohne verfügbares Update aus.
