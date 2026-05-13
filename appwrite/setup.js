/**
 * Appwrite Setup Script — Guardian App
 *
 * Erstellt alle Collections, Attribute und Indexes für die Guardian App.
 *
 * Voraussetzungen:
 *   npm install node-appwrite
 *
 * Konfiguration via Umgebungsvariablen (oder .env):
 *   APPWRITE_ENDPOINT   z.B. https://appwrite.deine-domain.de/v1
 *   APPWRITE_PROJECT_ID Projekt-ID aus der Appwrite-Konsole
 *   APPWRITE_API_KEY    Server-API-Key mit allen Scopes
 *
 * Ausführen:
 *   node setup.js
 *   node setup.js --dry-run   (zeigt nur was erstellt würde)
 */

import { config } from 'dotenv';
import { Client, Databases, ID, Permission, Role } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);

// ─── Datenbank ────────────────────────────────────────────────────────────────

export const DB_ID = 'guardian';

// ─── Collection-IDs ───────────────────────────────────────────────────────────
// Identisch mit Firestore-Collection-Namen für einfachere Migration.

export const COL = {
  USERS:              'users',
  ORGANIZATIONS:      'organizations',
  MEMBERS:            'members',           // + orgId-Feld (war Subcollection)
  CONVERSATIONS:      'conversations',     // + orgId-Feld
  MESSAGES:           'messages',          // + convId + orgId-Felder
  POLLS:              'polls',             // + convId + orgId-Felder
  CLAIM_REQUESTS:     'claim_requests',
  SCHEDULED_MESSAGES: 'scheduled_messages',
  ANNOUNCEMENTS:      'announcements',     // + orgId-Feld
};

// ─── Hilfsfunktionen ──────────────────────────────────────────────────────────

async function createCollection(id, name, permissions = []) {
  if (DRY_RUN) { console.log(`[DRY] createCollection: ${id}`); return; }
  try {
    await db.createCollection(DB_ID, id, name, permissions, true);
    console.log(`✓ Collection: ${id}`);
  } catch (e) {
    if (e.code === 409) console.log(`~ Collection exists: ${id}`);
    else throw e;
  }
}

async function str(col, key, size, required = false, defaultValue = null, array = false) {
  if (DRY_RUN) { console.log(`  [DRY] str ${col}.${key}`); return; }
  try {
    await db.createStringAttribute(DB_ID, col, key, size, required, defaultValue, array);
  } catch (e) {
    if (e.code !== 409) throw e;
  }
}

async function bool(col, key, required = false, defaultValue = null, array = false) {
  if (DRY_RUN) { console.log(`  [DRY] bool ${col}.${key}`); return; }
  try {
    await db.createBooleanAttribute(DB_ID, col, key, required, defaultValue, array);
  } catch (e) {
    if (e.code !== 409) throw e;
  }
}

async function int(col, key, required = false, defaultValue = null, min = null, max = null) {
  if (DRY_RUN) { console.log(`  [DRY] int ${col}.${key}`); return; }
  try {
    await db.createIntegerAttribute(DB_ID, col, key, required, min, max, defaultValue);
  } catch (e) {
    if (e.code !== 409) throw e;
  }
}

async function dt(col, key, required = false, defaultValue = null) {
  if (DRY_RUN) { console.log(`  [DRY] datetime ${col}.${key}`); return; }
  try {
    await db.createDatetimeAttribute(DB_ID, col, key, required, defaultValue);
  } catch (e) {
    if (e.code !== 409) throw e;
  }
}

async function idx(col, key, type, attributes, orders = []) {
  if (DRY_RUN) { console.log(`  [DRY] index ${col}.${key}`); return; }
  try {
    await db.createIndex(DB_ID, col, key, type, attributes, orders);
    console.log(`  ✓ Index: ${col}.${key}`);
  } catch (e) {
    if (e.code === 409 || (e.code === 400 && e.type === 'index_invalid')) return;
    throw e;
  }
}

// ─── Schema-Definitionen ──────────────────────────────────────────────────────

async function setupUsers() {
  await createCollection(COL.USERS, 'Users');
  // Felder
  await str(COL.USERS,  'email',              255, true);
  await str(COL.USERS,  'displayName',        100, true);
  await str(COL.USERS,  'photoUrl',           512);
  await bool(COL.USERS, 'isChild',                  false, false);
  await bool(COL.USERS, 'hideEmail',                false, false);
  await dt(COL.USERS,   'createdAt',          true);
  // Arrays
  await str(COL.USERS,  'verifiedParentUids', 36,  false, null, true);
  await str(COL.USERS,  'verifiedChildUids',  36,  false, null, true);
  // memberships: Array von OrgMembership-Objekten → als JSON-String gespeichert
  // (orgId, role, supervisorId — zu komplex für flat attributes)
  await str(COL.USERS,  'membershipsJson',         65535);
  await str(COL.USERS,  'notificationSettingsJson', 1024);
  await str(COL.USERS,  'fcmToken',                 512);
  // Indexes
  await idx(COL.USERS, 'email_idx',      'key',      ['email']);
  await idx(COL.USERS, 'isChild_idx',    'key',      ['isChild']);
}

async function setupOrganizations() {
  await createCollection(COL.ORGANIZATIONS, 'Organizations');
  await str(COL.ORGANIZATIONS,  'name',                 100,  true);
  await str(COL.ORGANIZATIONS,  'adminUid',             36,   true);
  await str(COL.ORGANIZATIONS,  'tag',                  20,   true);   // enum: familie|freunde|schule|vereine|sonstiges
  await str(COL.ORGANIZATIONS,  'memberUids',           36,   false, null, true);
  await dt(COL.ORGANIZATIONS,   'createdAt',            true);
  await bool(COL.ORGANIZATIONS, 'isArchived',                 false, false);
  await int(COL.ORGANIZATIONS,  'messageRetentionDays', false, 90, 30, 365);
  await str(COL.ORGANIZATIONS,  'keywords',             100,  false, null, true);
  // Indexes
  await idx(COL.ORGANIZATIONS, 'adminUid_idx',    'key',      ['adminUid']);
  await idx(COL.ORGANIZATIONS, 'isArchived_idx',  'key',      ['isArchived']);
  // memberUids: Array-Attribut — Appwrite unterstützt keine Indexes darauf
}

async function setupMembers() {
  // War: organizations/{orgId}/members/{uid}
  // Jetzt: flat collection mit orgId-Feld; $id = "{orgId}_{uid}" empfohlen
  await createCollection(COL.MEMBERS, 'Members');
  await str(COL.MEMBERS,  'orgId',               36,   true);
  await str(COL.MEMBERS,  'uid',                 36,   true);   // User-UID
  await str(COL.MEMBERS,  'displayName',         100,  true);
  await str(COL.MEMBERS,  'email',               255,  true);
  await str(COL.MEMBERS,  'photoUrl',            512);
  await str(COL.MEMBERS,  'role',                20,   true);   // admin|moderator|member|child
  await str(COL.MEMBERS,  'status',              20,   false, 'active');
  await dt(COL.MEMBERS,   'joinedAt',            true);
  await str(COL.MEMBERS,  'guardianUids',        36,   false, null, true);
  await str(COL.MEMBERS,  'childAlertInterval',  20,   false, 'hourly');
  await str(COL.MEMBERS,  'messageAlertInterval', 20,  false, 'always');
  await bool(COL.MEMBERS, 'notificationsEnabled',       false, true);
  await bool(COL.MEMBERS, 'hideEmail',                  false, false);
  // lastChildAlertAt: Map<childUid, DateTime> → JSON
  await str(COL.MEMBERS,  'lastChildAlertAtJson',   4096);
  // lastMessageAlertAt: Map<convId, DateTime> → JSON (Cooldown für Nachrichten)
  await str(COL.MEMBERS,  'lastMessageAlertAtJson', 4096);
  // Indexes
  await idx(COL.MEMBERS, 'orgId_idx',        'key',      ['orgId']);
  await idx(COL.MEMBERS, 'uid_idx',          'key',      ['uid']);
  await idx(COL.MEMBERS, 'orgId_uid_idx',    'unique',   ['orgId', 'uid']);
  await idx(COL.MEMBERS, 'orgId_role_idx',   'key',      ['orgId', 'role']);
  // guardianUids: Array-Attribut — kein Index möglich
}

async function setupConversations() {
  // War: organizations/{orgId}/conversations/{convId}
  await createCollection(COL.CONVERSATIONS, 'Conversations');
  await str(COL.CONVERSATIONS,  'orgId',               36,   true);
  await str(COL.CONVERSATIONS,  'orgAdminUid',         36,   false, '');
  await str(COL.CONVERSATIONS,  'participantUids',     36,   false, null, true);
  await str(COL.CONVERSATIONS,  'requestedBy',         36,   true);
  await str(COL.CONVERSATIONS,  'status',              20,   false, 'pending');  // pending|approved|rejected|archived
  await dt(COL.CONVERSATIONS,   'createdAt',           true);
  await str(COL.CONVERSATIONS,  'approvedBy',          36);
  await dt(COL.CONVERSATIONS,   'approvedAt');
  await str(COL.CONVERSATIONS,  'lastMessage',         500);
  await dt(COL.CONVERSATIONS,   'lastMessageAt');
  await str(COL.CONVERSATIONS,  'name',                100);
  await str(COL.CONVERSATIONS,  'imageUrl',            512);
  await bool(COL.CONVERSATIONS, 'isGroup',                   false, false);
  await str(COL.CONVERSATIONS,  'requestorGuardianUid', 36);
  await str(COL.CONVERSATIONS,  'canApproveUids',      36,   false, null, true);
  await str(COL.CONVERSATIONS,  'guardianUids',        36,   false, null, true);
  await str(COL.CONVERSATIONS,  'pinnedMessageId',     36);
  await str(COL.CONVERSATIONS,  'pinnedMessageText',   500);
  // Maps → JSON
  await str(COL.CONVERSATIONS,  'lastReadAtJson',      8192);   // Map<uid, DateTime>
  await str(COL.CONVERSATIONS,  'personalNamesJson',   4096);   // Map<uid, name>
  // typingUsers wird nicht persistent gespeichert (Echtzeit-only)
  // Indexes
  await idx(COL.CONVERSATIONS, 'orgId_idx',          'key',  ['orgId']);
  // participantUids, guardianUids, canApproveUids: Array-Attribute — kein Index möglich
  await idx(COL.CONVERSATIONS, 'status_idx',          'key', ['status']);
  await idx(COL.CONVERSATIONS, 'lastMessageAt_idx',   'key', ['lastMessageAt'], ['DESC']);
  await idx(COL.CONVERSATIONS, 'orgId_status_idx',    'key', ['orgId', 'status']);
}

async function setupMessages() {
  // War: organizations/{orgId}/conversations/{convId}/messages/{msgId}
  await createCollection(COL.MESSAGES, 'Messages');
  await str(COL.MESSAGES,  'convId',              36,   true);
  await str(COL.MESSAGES,  'orgId',               36,   true);
  await str(COL.MESSAGES,  'senderUid',           36,   true);
  await str(COL.MESSAGES,  'senderName',          100,  false, '');
  await str(COL.MESSAGES,  'text',                4096, false, '');
  await dt(COL.MESSAGES,   'sentAt',              true);
  await str(COL.MESSAGES,  'imageUrl',            512);
  await str(COL.MESSAGES,  'audioUrl',            512);
  await int(COL.MESSAGES,  'audioDurationMs');
  await str(COL.MESSAGES,  'pollId',              36);
  await str(COL.MESSAGES,  'fileUrl',             512);
  await str(COL.MESSAGES,  'fileName',            255);
  await int(COL.MESSAGES,  'fileSizeBytes');
  await dt(COL.MESSAGES,   'editedAt');
  await bool(COL.MESSAGES, 'isArchived',                false, false);
  await str(COL.MESSAGES,  'archivedByUid',       36);
  await str(COL.MESSAGES,  'archivedByName',      100);
  await str(COL.MESSAGES,  'replyToId',           36);
  await str(COL.MESSAGES,  'replyToSenderName',   100);
  await str(COL.MESSAGES,  'replyToText',         500);
  await str(COL.MESSAGES,  'type',                20,   false, 'user');   // user|system
  await str(COL.MESSAGES,  'systemEvent',         50);
  await str(COL.MESSAGES,  'systemActorName',     100);
  await str(COL.MESSAGES,  'systemTargetName',    100);
  await bool(COL.MESSAGES, 'isGif',                     false, false);
  await dt(COL.MESSAGES,   'deletedAt');
  await str(COL.MESSAGES,  'deletedBy',          36);
  // reactions: Map<uid, emoji> → JSON
  await str(COL.MESSAGES,  'reactionsJson',       4096);
  // Indexes
  await idx(COL.MESSAGES, 'convId_idx',        'key',  ['convId']);
  await idx(COL.MESSAGES, 'convId_sentAt_idx', 'key',  ['convId', 'sentAt'], ['ASC']);
  await idx(COL.MESSAGES, 'senderUid_idx',     'key',  ['senderUid']);
}

async function setupPolls() {
  // War: organizations/{orgId}/conversations/{convId}/polls/{pollId}
  await createCollection(COL.POLLS, 'Polls');
  await str(COL.POLLS,  'convId',         36,   true);
  await str(COL.POLLS,  'orgId',          36,   true);
  await str(COL.POLLS,  'question',       500,  true);
  await str(COL.POLLS,  'createdBy',      36,   true);
  await str(COL.POLLS,  'createdByName',  100,  false, '');
  await dt(COL.POLLS,   'createdAt',      true);
  await bool(COL.POLLS, 'multipleChoice',       false, false);
  await bool(COL.POLLS, 'isClosed',             false, false);
  await bool(COL.POLLS, 'isAnonymous',          false, false);
  await dt(COL.POLLS,   'expiresAt');
  // options: List<PollOption> → JSON  [{id, text}, ...]
  await str(COL.POLLS,  'optionsJson',    8192,  true);
  // votes: Map<optionId, List<uid>> → JSON
  await str(COL.POLLS,  'votesJson',      65535);
  await int(COL.POLLS,  'lastNotifiedVoterCount', false, 0);
  // Indexes
  await idx(COL.POLLS, 'convId_idx',   'key', ['convId']);
  await idx(COL.POLLS, 'isClosed_idx', 'key', ['isClosed']);
  await idx(COL.POLLS, 'expiresAt_idx', 'key', ['expiresAt']);
}

async function setupClaimRequests() {
  await createCollection(COL.CLAIM_REQUESTS, 'ClaimRequests');
  await str(COL.CLAIM_REQUESTS,  'fromUid',   36,   true);
  await str(COL.CLAIM_REQUESTS,  'fromName',  100,  false, '');
  await str(COL.CLAIM_REQUESTS,  'fromEmail', 255,  false, '');
  await str(COL.CLAIM_REQUESTS,  'toUid',     36,   true);
  await str(COL.CLAIM_REQUESTS,  'toEmail',   255,  false, '');
  await str(COL.CLAIM_REQUESTS,  'status',    20,   false, 'pending');  // pending|confirmed|rejected|cancelled|expired
  await dt(COL.CLAIM_REQUESTS,   'createdAt', true);
  await dt(COL.CLAIM_REQUESTS,   'expiresAt', true);
  // Indexes
  await idx(COL.CLAIM_REQUESTS, 'fromUid_idx',     'key', ['fromUid']);
  await idx(COL.CLAIM_REQUESTS, 'toUid_idx',       'key', ['toUid']);
  await idx(COL.CLAIM_REQUESTS, 'status_idx',      'key', ['status']);
  await idx(COL.CLAIM_REQUESTS, 'expiresAt_idx',   'key', ['expiresAt']);
}

async function setupScheduledMessages() {
  await createCollection(COL.SCHEDULED_MESSAGES, 'ScheduledMessages');
  await str(COL.SCHEDULED_MESSAGES, 'convId',       36,   true);
  await str(COL.SCHEDULED_MESSAGES, 'text',         4096, true);
  await str(COL.SCHEDULED_MESSAGES, 'senderUid',    36,   true);
  await str(COL.SCHEDULED_MESSAGES, 'senderName',   100,  false, '');
  await dt(COL.SCHEDULED_MESSAGES,  'scheduledFor', true);
  await dt(COL.SCHEDULED_MESSAGES,  'createdAt',    true);
  // Indexes
  await idx(COL.SCHEDULED_MESSAGES, 'convId_idx',       'key', ['convId']);
  await idx(COL.SCHEDULED_MESSAGES, 'scheduledFor_idx', 'key', ['scheduledFor'], ['ASC']);
  await idx(COL.SCHEDULED_MESSAGES, 'senderUid_idx',    'key', ['senderUid']);
}

async function setupAnnouncements() {
  // War: organizations/{orgId}/announcements/{annId}
  await createCollection(COL.ANNOUNCEMENTS, 'Announcements');
  await str(COL.ANNOUNCEMENTS,  'orgId',       36,   true);
  await str(COL.ANNOUNCEMENTS,  'title',       200,  true);
  await str(COL.ANNOUNCEMENTS,  'content',     10000, true);
  await str(COL.ANNOUNCEMENTS,  'authorUid',   36,   true);
  await str(COL.ANNOUNCEMENTS,  'authorName',  100,  false, '');
  await dt(COL.ANNOUNCEMENTS,   'createdAt',   true);
  await dt(COL.ANNOUNCEMENTS,   'updatedAt');
  await dt(COL.ANNOUNCEMENTS,   'expiresAt');
  await str(COL.ANNOUNCEMENTS,  'type',        20,   false, 'announcement');  // announcement|event
  await dt(COL.ANNOUNCEMENTS,   'eventDate');
  await dt(COL.ANNOUNCEMENTS,   'eventEndDate');
  await str(COL.ANNOUNCEMENTS,  'location',    300);
  await bool(COL.ANNOUNCEMENTS, 'rsvpPublic',         false, false);
  // reactions: Map<uid, emoji> → JSON
  await str(COL.ANNOUNCEMENTS,  'reactionsJson', 4096);
  // rsvp: Map<uid, 'yes'|'no'|'maybe'> → JSON
  await str(COL.ANNOUNCEMENTS,  'rsvpJson',    8192);
  // Indexes
  await idx(COL.ANNOUNCEMENTS, 'orgId_idx',       'key', ['orgId']);
  await idx(COL.ANNOUNCEMENTS, 'type_idx',        'key', ['type']);
  await idx(COL.ANNOUNCEMENTS, 'createdAt_idx',   'key', ['createdAt'], ['DESC']);
  await idx(COL.ANNOUNCEMENTS, 'expiresAt_idx',   'key', ['expiresAt']);
  await idx(COL.ANNOUNCEMENTS, 'eventDate_idx',   'key', ['eventDate']);
}

async function setupInvitations() {
  await createCollection('invitations', 'Invitations');
  await str('invitations', 'email',        255, true);
  await str('invitations', 'orgId',        36,  true);
  await str('invitations', 'orgName',      100, false, '');
  await str('invitations', 'role',         20,  false, 'member');
  await str('invitations', 'guardianUids', 36,  false, null, true);
  await str('invitations', 'inviterName',  100);
  await str('invitations', 'status',       20,  false, 'pending');
  await dt('invitations',  'createdAt',    true);
  await idx('invitations', 'email_status_idx', 'key', ['email', 'status']);
  await idx('invitations', 'orgId_idx',        'key', ['orgId']);
}

async function setupOrgInviteConsents() {
  await createCollection('org_invite_consents', 'OrgInviteConsents');
  await str('org_invite_consents', 'childUid',             36,  true);
  await str('org_invite_consents', 'childName',            100, false, '');
  await str('org_invite_consents', 'orgId',                36,  true);
  await str('org_invite_consents', 'orgName',              100, false, '');
  await str('org_invite_consents', 'invitedByUid',         36);
  await str('org_invite_consents', 'invitedByName',        100, false, '');
  await str('org_invite_consents', 'parentUids',           36,  false, null, true);
  await str('org_invite_consents', 'proposedGuardianUids', 36,  false, null, true);
  await str('org_invite_consents', 'approvedBy',           36);
  await str('org_invite_consents', 'vetoedBy',             36);
  await str('org_invite_consents', 'status',               20,  false, 'pending');
  await dt('org_invite_consents',  'createdAt',            true);
  await dt('org_invite_consents',  'expiresAt',            false);
  await idx('org_invite_consents', 'childUid_idx',   'key', ['childUid']);
  await idx('org_invite_consents', 'status_idx',     'key', ['status']);
  await idx('org_invite_consents', 'parentUids_idx', 'key', ['parentUids']);
}

async function setupReports() {
  await createCollection('reports', 'Reports');
  await str('reports', 'orgId',             36,   true);
  await str('reports', 'orgAdminUid',       36);
  await str('reports', 'convId',            36);
  await str('reports', 'messageSenderName', 100,  false, '');
  await str('reports', 'messageText',       4096, false, '');
  await str('reports', 'reportedByUid',     36);
  await dt('reports',  'createdAt',         true);
  await idx('reports', 'orgId_idx',     'key', ['orgId']);
  await idx('reports', 'createdAt_idx', 'key', ['createdAt'], ['DESC']);
}

// ─── Hauptprogramm ────────────────────────────────────────────────────────────

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===\n');

  // Datenbank anlegen
  if (!DRY_RUN) {
    try {
      await db.create(DB_ID, 'Guardian');
      console.log('✓ Datenbank: guardian');
    } catch (e) {
      if (e.code === 409) console.log('~ Datenbank existiert bereits: guardian');
      else throw e;
    }
  }

  // Collections anlegen (reihenfolge egal, keine FK-Constraints in Appwrite)
  await setupUsers();
  await setupOrganizations();
  await setupMembers();
  await setupConversations();
  await setupMessages();
  await setupPolls();
  await setupClaimRequests();
  await setupScheduledMessages();
  await setupAnnouncements();
  await setupInvitations();
  await setupOrgInviteConsents();
  await setupReports();

  console.log('\n✅ Setup abgeschlossen.');
  console.log('\nNächste Schritte:');
  console.log('  1. FCM-Provider in Appwrite Console unter Messaging konfigurieren');
  console.log('  2. Auth-Provider (Email/Password) in Appwrite Console aktivieren');
  console.log('  3. Storage-Bucket "media" anlegen (für Bilder, Dateien, Sprachnachrichten)');
  console.log('  4. Migrations-Skript ausführen: node migrate.js');
}

main().catch(console.error);
