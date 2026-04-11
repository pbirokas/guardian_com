# Guardian Com

A Flutter app for supervised, GDPR-compliant communication within organizations — designed for youth groups, schools, clubs, and similar communities where children and guardians participate alongside adult members.

## Features

### Organization management
- Create and manage multiple organizations
- Role-based access: **Admin**, **Moderator**, **Member**, **Child**
- Invite members by email (individual or bulk CSV import)
- Guardian–child relationship with approval workflow
- Suggest new members (regular members can propose, admin/mod approves)
- Archive and restore organizations

### Chat
- Direct and group chats with approval workflow (admin/moderator must approve chat requests)
- **Read receipts** — see who has read each message
- **Replies** — quote and reply to individual messages
- **Search** — full-text search within a chat
- **Scheduled messages** — queue a message to be sent at a specific time
- **Polls** — create single- and multiple-choice polls, close manually
- Send images, files (max. 5 MB), and voice messages
- Report messages; admin/moderators can moderate and delete
- Guardian supervision: guardians see their child's chats and receive keyword alerts
- Archive chats (read-only)

### Pinboard (announcements)
- Admin and moderators can post, edit, and delete announcements visible to all org members

### Keyword monitoring
- Admins define per-organization keyword lists
- Guardians and moderators are notified when a monitored word appears in chat
- Import and export keyword lists as CSV files

### Notifications
- Push notifications via Firebase Cloud Messaging (FCM)
- Configurable per-organization and per-notification-type (messages, invitations, org changes)
- Configurable alert interval (every message / hourly / daily / never)

### Profile & privacy
- Display name and profile photo
- Light / dark / system theme
- Language: German, English
- Show/hide online status, last-seen, profile photo
- Delete account (removes all data immediately)

### Platforms
| Platform | Status |
|---|---|
| Android | Supported |
| iOS | Supported |
| Windows | Supported (system-tray icon, local notifications) |

---

## Tech stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3 / Dart |
| State management | Riverpod (with code generation) |
| Navigation | go_router |
| Backend | Firebase (Auth, Firestore, Storage, Messaging, Crashlytics, App Check) |
| Auth | Google Sign-In, passwordless email link |
| Localization | Flutter ARB (`intl`, `flutter_localizations`) |
| Network status | `connectivity_plus` |
| Audio | `record`, `audioplayers` |
| File I/O | `file_picker`, `open_filex`, `path_provider` |
| Desktop | `window_manager`, `system_tray`, `local_notifier`, `windows_taskbar` |

---

## Project structure

```
guardian_app/
  lib/
    core/
      models/          # Data models (AppUser, Organization, Message, …)
      services/        # Firestore/Storage service classes
      providers/       # Shared Riverpod providers (auth, connectivity, locale)
    features/
      auth/            # Login screen
      chat/            # Chat screen, providers
      organizations/   # Org list, org detail (members, chats, reports, pinboard)
      profile/         # Profile, privacy, notifications screens
    l10n/              # ARB localization files (app_de.arb, app_en.arb)
    main.dart
  assets/
    icon/              # App icons
    bulk_import_example.csv
firestore.rules        # Firestore security rules
functions/             # Firebase Cloud Functions (Node.js)
privacy_policy.html    # GDPR privacy policy (hosted externally)
```

---

## Getting started

### Prerequisites

- Flutter SDK ≥ 3.11
- A Firebase project with Firestore, Auth, Storage, and Messaging enabled
- `firebase-tools` CLI (`npm install -g firebase-tools`)

### Setup

1. Clone the repository.
2. Place your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) into the respective platform folders.
3. For Windows, add `firebase_app_id_file.json` to `windows/`.
4. Install dependencies:
   ```bash
   flutter pub get
   ```
5. Generate Riverpod code:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

### Run

```bash
flutter run
```

### Build (release)

```bash
# Android APK
flutter build apk --release --build-name=1.0.2 --build-number=1

# Windows
flutter build windows --release --build-name=1.0.2 --build-number=1
```

### Deploy Firestore security rules

```bash
firebase deploy --only firestore:rules
```

---

## Localization

ARB files are in `lib/l10n/`. After editing, regenerate:

```bash
flutter gen-l10n
```

---

## Privacy policy

See [privacy_policy.html](../privacy_policy.html) — hosted at the URL configured in the app's privacy screen.

---

## License

Private project — not published to pub.dev.
