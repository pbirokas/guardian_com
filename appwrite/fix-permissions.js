/**
 * One-time script: enable documentSecurity on all existing Appwrite collections
 * and apply correct permissions to the media storage bucket.
 *
 * Run ONCE against the live instance after updating setup.js.
 * Safe to re-run (idempotent).
 *
 * Usage:
 *   node fix-permissions.js
 *
 * Required env vars (same as setup.js):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Storage, Permission, Role } from 'node-appwrite';

config();

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const storage = new Storage(client);
const DB_ID = 'guardian';
const BUCKET_MEDIA = '6a02e524000954c9f1de'; // Live-Bucket-ID (manuell erstellt)

const collections = [
  { id: 'users',              name: 'Users' },
  { id: 'organizations',      name: 'Organizations' },
  { id: 'members',            name: 'Members' },
  { id: 'conversations',      name: 'Conversations' },
  { id: 'chat_messages',      name: 'ChatMessages' },
  { id: 'polls',              name: 'Polls' },
  { id: 'claim_requests',     name: 'ClaimRequests' },
  { id: 'scheduled_messages', name: 'ScheduledMessages' },
  { id: 'announcements',      name: 'Announcements' },
  { id: 'invitations',        name: 'Invitations' },
  { id: 'org_invite_consents', name: 'OrgInviteConsents' },
  { id: 'reports',            name: 'Reports' },
];

// Collection-Level Permissions:
// - read: nötig damit Appwrite Realtime den WebSocket-Channel öffnen kann
// - create/update/delete: auf Collection-Ebene nötig da Appwrite kein per-Doc create kennt
// Die eigentliche Zugriffsfilterung (wer darf was) passiert per Query und App-Logik.
const R   = [Permission.read(Role.users())];
const RCD = [Permission.read(Role.users()), Permission.create(Role.users()), Permission.delete(Role.users())];
const RCUD = [Permission.read(Role.users()), Permission.create(Role.users()), Permission.update(Role.users()), Permission.delete(Role.users())];

const collectionPermissionOverrides = {
  users:               R,      // schreiben nur per Document-Permission (auth_service)
  organizations:       RCUD,   // Client erstellt/updated Orgs (memberUids-Array, approveChild)
  members:             RCUD,   // Mitgliedschaft wird vom Client aktualisiert (z.B. guardianUids)
  conversations:       RCUD,   // neue Chats anlegen, Status aktualisieren
  chat_messages:       RCD,    // Nachrichten senden und löschen
  polls:               RCUD,   // Polls anlegen und abstimmen
  announcements:       RCUD,   // Admins erstellen Announcements
  scheduled_messages:  RCUD,   // geplante Nachrichten anlegen/löschen
  invitations:         RCUD,   // Einladungen erstellen
  org_invite_consents: RCUD,   // Eltern-Zustimmungen
  claim_requests:      RCUD,   // Eltern-Kind-Verknüpfung
  reports:             RCD,    // Meldungen erstellen
};

async function fixCollections() {
  console.log('Enabling documentSecurity on all collections...\n');
  for (const col of collections) {
    try {
      const current = await db.getCollection(DB_ID, col.id);
      const permissions = collectionPermissionOverrides[col.id] ?? current.$permissions;
      await db.updateCollection(DB_ID, col.id, col.name, permissions, true);
      console.log(`✓ ${col.id}${collectionPermissionOverrides[col.id] ? ' (permissions updated)' : ''}`);
    } catch (e) {
      if (e.code === 404) {
        console.log(`~ ${col.id}: not found, skipping`);
      } else {
        console.error(`✗ ${col.id}: ${e.message}`);
      }
    }
  }
  console.log('\nDone. All existing documents without explicit permissions are now inaccessible');
  console.log('to clients (Cloud Functions with API key are unaffected).');
}

// Vuln 6: media-Bucket braucht explizite Permissions, damit authentifizierte Nutzer
// Dateien lesen und hochladen können. Löschen bleibt per File-Permission (beim Upload gesetzt).
async function fixMediaBucket() {
  console.log('\nFixing media bucket permissions...');
  const permissions = [
    Permission.read(Role.any()),     // CachedNetworkImage braucht keine Auth-Header
    Permission.create(Role.users()),
  ];
  try {
    await storage.updateBucket(BUCKET_MEDIA, 'Media', permissions, true);
    console.log('✓ media bucket: permissions updated, documentSecurity enabled');
  } catch (e) {
    if (e.code === 404) {
      console.log('~ media bucket: not found — create it manually or run setup.js');
    } else {
      console.error(`✗ media bucket: ${e.message}`);
    }
  }
}

async function main() {
  await fixCollections();
  await fixMediaBucket();
}

main().catch(console.error);
