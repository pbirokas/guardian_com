/**
 * Phase 4 — Datenmigration: Firebase/Firestore → Appwrite
 *
 * Was migriert wird:
 *   - Firebase Auth-Nutzer → Appwrite Users (gleiche UIDs, zufälliges Passwort)
 *   - Firestore-Collections (inkl. Subcollections → flache Collections)
 *   - Firebase Storage Dateien → Appwrite Storage (URLs in Dokumenten aktualisiert)
 *
 * Hinweis: Nutzer müssen sich nach der Migration einmalig neu anmelden
 * (Passwort-Reset per E-Mail). Die UIDs bleiben identisch.
 *
 * Usage:
 *   node migrate.js                  # vollständige Migration
 *   node migrate.js --dry-run        # Vorschau, keine Änderungen
 *   node migrate.js --skip-auth      # Auth-Migration überspringen
 *   node migrate.js --skip-storage   # Storage-Migration überspringen
 *   node migrate.js --only-storage   # nur Storage-Migration
 *
 * Erforderliche Umgebungsvariablen (.env):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 *   FIREBASE_SERVICE_ACCOUNT_PATH   Pfad zur Service-Account-JSON-Datei
 *   FIREBASE_STORAGE_BUCKET         z.B. mein-projekt.appspot.com
 */

import { config } from 'dotenv';
import { Client, Databases, Storage, Users, Permission, Role, ID, Query } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { readFileSync } from 'fs';
import https from 'https';
import http from 'http';
import crypto from 'crypto';

config();

// ─── Flags ───────────────────────────────────────────────────────────────────

const DRY_RUN      = process.argv.includes('--dry-run');
const SKIP_AUTH    = process.argv.includes('--skip-auth');
const SKIP_STORAGE = process.argv.includes('--skip-storage');
const ONLY_STORAGE = process.argv.includes('--only-storage');

// ─── Firebase Admin ───────────────────────────────────────────────────────────

const serviceAccount = JSON.parse(
  readFileSync(process.env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8'),
);
const firebaseApp = initializeApp({
  credential: cert(serviceAccount),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
});

const fsDb      = getFirestore(firebaseApp);
const fbAuth    = getAuth(firebaseApp);
let _fbBucket;
const fbBucket  = () => {
  if (!_fbBucket) _fbBucket = getStorage(firebaseApp).bucket();
  return _fbBucket;
};

// ─── Appwrite ─────────────────────────────────────────────────────────────────

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const awDb      = new Databases(client);
const awStorage = new Storage(client);
const awUsers   = new Users(client);

const DB_ID            = 'guardian';
const BUCKET_MEDIA     = '6a02e524000954c9f1de';
const AW_ENDPOINT      = process.env.APPWRITE_ENDPOINT;
const AW_PROJECT_ID    = process.env.APPWRITE_PROJECT_ID;
const BATCH_SIZE       = 10; // parallele Operationen gleichzeitig

// ─── Hilfsfunktionen ──────────────────────────────────────────────────────────

/** Firestore Timestamp → ISO-8601-String (oder null) */
function ts(value) {
  if (value == null) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return null;
}

/** Verarbeitet ein Array in Batches (begrenzte Parallelität) */
async function inBatches(items, fn, size = BATCH_SIZE) {
  for (let i = 0; i < items.length; i += size) {
    await Promise.all(items.slice(i, i + size).map(fn));
  }
}

/**
 * Paginiert eine Firestore-Collection-Query.
 * Gibt Dokumente als AsyncGenerator zurück.
 */
async function* paginate(ref, pageSize = 500) {
  let last = null;
  while (true) {
    let q = ref.orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) yield doc;
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
}

/**
 * Erstellt ein Appwrite-Dokument; überspringt es wenn es bereits existiert (409).
 * Gibt true zurück wenn neu erstellt, false wenn bereits vorhanden.
 */
async function upsertDoc(colId, docId, data, permissions = []) {
  if (DRY_RUN) return true;
  // Null-Werte entfernen (Appwrite lehnt null für Pflichtfelder ab)
  const cleaned = Object.fromEntries(
    Object.entries(data).filter(([, v]) => v !== null && v !== undefined),
  );
  try {
    await awDb.createDocument(DB_ID, colId, docId, cleaned, permissions);
    return true;
  } catch (e) {
    if (e.code === 409) return false; // already exists
    throw e;
  }
}

// ─── Storage-Hilfsfunktionen ──────────────────────────────────────────────────

function isFirebaseUrl(url) {
  return typeof url === 'string' && url.includes('firebasestorage.googleapis.com');
}

/** Extrahiert den Storage-Pfad aus einer Firebase-Download-URL */
function extractFbPath(url) {
  const m = url.match(/\/o\/([^?#]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}

/** Leitet Content-Type aus Dateiendung ab */
function contentTypeFromPath(path) {
  const ext = path.split('.').pop()?.toLowerCase();
  return {
    jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
    gif: 'image/gif', webp: 'image/webp',
    m4a: 'audio/m4a', webm: 'audio/webm', ogg: 'audio/ogg',
    pdf: 'application/pdf', zip: 'application/zip',
  }[ext] ?? 'application/octet-stream';
}

/**
 * Lädt eine Firebase-Storage-Datei herunter und lädt sie nach Appwrite hoch.
 * Gibt die neue Appwrite-URL zurück, oder bei Fehler die ursprüngliche URL.
 */
async function migrateFile(firebaseUrl, uploaderUid) {
  if (!isFirebaseUrl(firebaseUrl)) return firebaseUrl;
  if (DRY_RUN) return `appwrite://migrated`;

  const path = extractFbPath(firebaseUrl);
  if (!path) return firebaseUrl;

  try {
    const file = fbBucket().file(path);
    const [exists] = await file.exists();
    if (!exists) {
      console.warn(`  ~ Datei nicht gefunden: ${path}`);
      return firebaseUrl;
    }
    const [buffer] = await file.download();
    const filename = path.split('/').pop();
    const contentType = contentTypeFromPath(path);

    const awFile = await awStorage.createFile(
      BUCKET_MEDIA,
      ID.unique(),
      InputFile.fromBuffer(buffer, filename),
      [
        Permission.read(Role.users()),
        ...(uploaderUid ? [Permission.delete(Role.user(uploaderUid))] : []),
      ],
    );
    return `${AW_ENDPOINT}/storage/buckets/${BUCKET_MEDIA}/files/${awFile.$id}/view?project=${AW_PROJECT_ID}`;
  } catch (e) {
    console.warn(`  ~ Storage-Fehler für ${path}: ${e.message}`);
    return firebaseUrl; // URL unverändert lassen bei Fehler
  }
}

// ─── Phase 1: Auth ────────────────────────────────────────────────────────────

async function migrateAuth() {
  console.log('\n── Phase 1: Firebase Auth → Appwrite Users ──');
  let migrated = 0, skipped = 0, failed = 0;
  let pageToken;
  do {
    const result = await fbAuth.listUsers(1000, pageToken);
    await inBatches(result.users, async (fbUser) => {
      if (DRY_RUN) { migrated++; return; }
      try {
        await awUsers.create(
          fbUser.uid,
          fbUser.email ?? undefined,
          undefined,
          crypto.randomBytes(24).toString('base64'), // temporäres Passwort
          fbUser.displayName ?? fbUser.email ?? fbUser.uid,
        );
        migrated++;
        process.stdout.write('.');
      } catch (e) {
        if (e.code === 409) { skipped++; process.stdout.write('~'); }
        else { failed++; console.error(`\n  ✗ User ${fbUser.uid}: ${e.message}`); }
      }
    });
    pageToken = result.pageToken;
  } while (pageToken);
  console.log(`\n  ✓ ${migrated} erstellt, ${skipped} übersprungen, ${failed} Fehler`);
}

// ─── Phase 2: Firestore ───────────────────────────────────────────────────────

async function migrateUsers() {
  console.log('\n── users ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('users'))) {
    const d = doc.data();
    const uid = doc.id;
    const data = {
      email:              (d.email ?? '').toLowerCase(),
      displayName:        d.displayName ?? d.email ?? uid,
      photoUrl:           d.photoUrl ?? null,
      membershipsJson:    JSON.stringify(
        (d.memberships ?? []).map((m) => ({
          orgId: m.orgId,
          role:  m.role,
          ...(m.supervisorId ? { supervisorId: m.supervisorId } : {}),
        })),
      ),
      createdAt:          ts(d.createdAt) ?? new Date().toISOString(),
      isChild:            d.isChild ?? false,
      verifiedParentUids: d.verifiedParentUids ?? [],
      verifiedChildUids:  d.verifiedChildUids  ?? [],
      hideEmail:          d.hideEmail ?? false,
    };
    const created = await upsertDoc('users', uid, data, [
      Permission.read(Role.user(uid)),
      Permission.update(Role.user(uid)),
      Permission.delete(Role.user(uid)),
    ]);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateOrganizations() {
  console.log('\n── organizations ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('organizations'))) {
    const d = doc.data();
    const data = {
      name:                d.name,
      adminUid:            d.adminUid,
      tag:                 d.tag ?? 'sonstiges',
      memberUids:          d.memberUids ?? [],
      createdAt:           ts(d.createdAt) ?? new Date().toISOString(),
      isArchived:          d.isArchived ?? false,
      keywords:            d.keywords ?? [],
      messageRetentionDays: d.messageRetentionDays ?? 90,
    };
    const created = await upsertDoc('organizations', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateMembers() {
  console.log('\n── members (Subcollection) ──');
  let n = 0, skip = 0;
  const orgsSnap = await fsDb.collection('organizations').get();
  for (const orgDoc of orgsSnap.docs) {
    const orgId = orgDoc.id;
    for await (const memberDoc of paginate(fsDb.collection('organizations').doc(orgId).collection('members'))) {
      const d = memberDoc.data();
      const uid = memberDoc.id;
      const memberId = `${orgId}_${uid}`;
      // Unterstützt altes singular guardianUid-Feld
      const guardianUids = Array.from(new Set([
        ...(d.guardianUids ?? []),
        ...(d.guardianUid ? [d.guardianUid] : []),
      ]));
      const data = {
        uid,
        orgId,
        displayName:          d.displayName ?? d.email ?? uid,
        email:                d.email ?? '',
        photoUrl:             d.photoUrl ?? null,
        role:                 d.role,
        joinedAt:             ts(d.joinedAt) ?? new Date().toISOString(),
        guardianUids,
        status:               d.status ?? 'active',
        childAlertInterval:   d.childAlertInterval ?? 'hourly',
        notificationsEnabled: d.notificationsEnabled ?? true,
        messageAlertInterval: d.messageAlertInterval ?? 'always',
        hideEmail:            d.hideEmail ?? false,
        lastChildAlertAtJson: JSON.stringify(
          Object.fromEntries(
            Object.entries(d.lastChildAlertAt ?? {}).map(([k, v]) => [k, ts(v)]),
          ),
        ),
      };
      const created = await upsertDoc('members', memberId, data);
      created ? n++ : skip++;
      process.stdout.write(created ? '.' : '~');
    }
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateConversations() {
  console.log('\n── conversations ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('conversations'))) {
    const d = doc.data();
    let imageUrl = d.imageUrl ?? null;
    if (!SKIP_STORAGE && isFirebaseUrl(imageUrl)) {
      imageUrl = await migrateFile(imageUrl, d.adminUid ?? null);
    }
    const lastReadAt = d.lastReadAt
      ? Object.fromEntries(
          Object.entries(d.lastReadAt).map(([uid, t]) => [uid, ts(t)]),
        )
      : {};
    const data = {
      orgId:               d.orgId,
      orgAdminUid:         d.orgAdminUid ?? '',
      participantUids:     d.participantUids ?? [],
      requestedBy:         d.requestedBy,
      status:              d.status ?? 'pending',
      createdAt:           ts(d.createdAt) ?? new Date().toISOString(),
      isGroup:             d.isGroup ?? false,
      canApproveUids:      d.canApproveUids ?? [],
      guardianUids:        d.guardianUids ?? [],
      lastReadAtJson:      JSON.stringify(lastReadAt),
      personalNamesJson:   JSON.stringify(d.personalNames ?? {}),
      approvedBy:          d.approvedBy ?? null,
      approvedAt:          ts(d.approvedAt),
      lastMessage:         d.lastMessage ?? null,
      lastMessageAt:       ts(d.lastMessageAt),
      name:                d.name ?? null,
      imageUrl,
      requestorGuardianUid: d.requestorGuardianUid ?? null,
      pinnedMessageId:     d.pinnedMessageId ?? null,
      pinnedMessageText:   d.pinnedMessageText ?? null,
    };
    const created = await upsertDoc('conversations', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateMessages() {
  console.log('\n── messages (Subcollection) ──');
  let n = 0, skip = 0;
  const convsSnap = await fsDb.collection('conversations').get();
  for (const convDoc of convsSnap.docs) {
    const convId = convDoc.id;
    const orgId  = convDoc.data().orgId ?? '';
    for await (const msgDoc of paginate(fsDb.collection('conversations').doc(convId).collection('messages'))) {
      const d = msgDoc.data();
      let imageUrl = d.imageUrl ?? null;
      let audioUrl = d.audioUrl ?? null;
      let fileUrl  = d.fileUrl  ?? null;
      if (!SKIP_STORAGE) {
        if (isFirebaseUrl(imageUrl)) imageUrl = await migrateFile(imageUrl, d.senderUid);
        if (isFirebaseUrl(audioUrl)) audioUrl = await migrateFile(audioUrl, d.senderUid);
        if (isFirebaseUrl(fileUrl))  fileUrl  = await migrateFile(fileUrl,  d.senderUid);
      }
      const data = {
        convId,
        orgId,
        senderUid:          d.senderUid,
        senderName:         d.senderName ?? '',
        text:               d.text ?? '',
        sentAt:             ts(d.sentAt) ?? new Date().toISOString(),
        imageUrl,
        audioUrl,
        audioDurationMs:    d.audioDurationMs ?? null,
        pollId:             d.pollId ?? null,
        fileUrl,
        fileName:           d.fileName ?? null,
        fileSizeBytes:      d.fileSizeBytes ?? null,
        editedAt:           ts(d.editedAt),
        isArchived:         d.isArchived ?? false,
        archivedByUid:      d.archivedByUid ?? null,
        archivedByName:     d.archivedByName ?? null,
        replyToId:          d.replyToId ?? null,
        replyToSenderName:  d.replyToSenderName ?? null,
        replyToText:        d.replyToText ?? null,
        reactionsJson:      JSON.stringify(d.reactions ?? {}),
        type:               d.type ?? 'user',
        systemEvent:        d.systemEvent ?? null,
        systemActorName:    d.systemActorName ?? null,
        systemTargetName:   d.systemTargetName ?? null,
        isGif:              d.isGif ?? false,
        deletedAt:          ts(d.deletedAt),
        deletedBy:          d.deletedBy ?? null,
      };
      const created = await upsertDoc('messages', msgDoc.id, data);
      created ? n++ : skip++;
      process.stdout.write(created ? '.' : '~');
    }
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migratePolls() {
  console.log('\n── polls (Subcollection) ──');
  let n = 0, skip = 0;
  const convsSnap = await fsDb.collection('conversations').get();
  for (const convDoc of convsSnap.docs) {
    const convId = convDoc.id;
    const convData = convDoc.data();
    for await (const pollDoc of paginate(fsDb.collection('conversations').doc(convId).collection('polls'))) {
      const d = pollDoc.data();
      const data = {
        convId,
        orgId: d.orgId ?? convData.orgId ?? '',
        question:      d.question,
        optionsJson:   JSON.stringify((d.options ?? []).map((o) => ({ id: o.id, text: o.text }))),
        createdBy:     d.createdBy,
        createdByName: d.createdByName ?? '',
        createdAt:     ts(d.createdAt) ?? new Date().toISOString(),
        multipleChoice: d.multipleChoice ?? false,
        isClosed:      d.isClosed ?? false,
        isAnonymous:   d.isAnonymous ?? false,
        expiresAt:     ts(d.expiresAt),
        votesJson:     JSON.stringify(
          Object.fromEntries(
            Object.entries(d.votes ?? {}).map(([k, v]) => [k, Array.isArray(v) ? v : []]),
          ),
        ),
      };
      const created = await upsertDoc('polls', pollDoc.id, data);
      created ? n++ : skip++;
      process.stdout.write(created ? '.' : '~');
    }
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateScheduledMessages() {
  console.log('\n── scheduled_messages (Subcollection) ──');
  let n = 0, skip = 0;
  const convsSnap = await fsDb.collection('conversations').get();
  for (const convDoc of convsSnap.docs) {
    const convId = convDoc.id;
    for await (const smDoc of paginate(fsDb.collection('conversations').doc(convId).collection('scheduledMessages'))) {
      const d = smDoc.data();
      const data = {
        convId,
        text:         d.text,
        senderUid:    d.senderUid,
        senderName:   d.senderName ?? '',
        scheduledFor: ts(d.scheduledFor) ?? new Date().toISOString(),
        createdAt:    ts(d.createdAt)    ?? new Date().toISOString(),
      };
      const created = await upsertDoc('scheduled_messages', smDoc.id, data);
      created ? n++ : skip++;
      process.stdout.write(created ? '.' : '~');
    }
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateAnnouncements() {
  console.log('\n── announcements (Subcollection) ──');
  let n = 0, skip = 0;
  const orgsSnap = await fsDb.collection('organizations').get();
  for (const orgDoc of orgsSnap.docs) {
    const orgId = orgDoc.id;
    for await (const annDoc of paginate(fsDb.collection('organizations').doc(orgId).collection('announcements'))) {
      const d = annDoc.data();
      const data = {
        orgId,
        title:         d.title ?? '',
        content:       d.content ?? '',
        authorUid:     d.authorUid ?? '',
        authorName:    d.authorName ?? '',
        createdAt:     ts(d.createdAt) ?? new Date().toISOString(),
        updatedAt:     ts(d.updatedAt),
        expiresAt:     ts(d.expiresAt),
        type:          d.type ?? 'announcement',
        eventDate:     ts(d.eventDate),
        eventEndDate:  ts(d.eventEndDate),
        location:      d.location ?? null,
        rsvpPublic:    d.rsvpPublic ?? false,
        reactionsJson: JSON.stringify(d.reactions ?? {}),
        rsvpJson:      JSON.stringify(d.rsvp ?? {}),
      };
      const created = await upsertDoc('announcements', annDoc.id, data);
      created ? n++ : skip++;
      process.stdout.write(created ? '.' : '~');
    }
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateInvitations() {
  console.log('\n── invitations ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('invitations'))) {
    const d = doc.data();
    const data = {
      orgId:        d.orgId,
      orgName:      d.orgName ?? '',
      inviterName:  d.invitedByName ?? d.inviterName ?? '',
      email:        d.email,
      role:         d.role ?? 'member',
      guardianUids: d.guardianUids ?? [],
      status:       d.status ?? 'pending',
      createdAt:    ts(d.createdAt) ?? new Date().toISOString(),
    };
    const created = await upsertDoc('invitations', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateClaimRequests() {
  // Firestore: 'claimRequests', Appwrite: 'claim_requests'
  console.log('\n── claim_requests ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('claimRequests'))) {
    const d = doc.data();
    const data = {
      fromUid:   d.fromUid,
      fromName:  d.fromName ?? '',
      fromEmail: d.fromEmail ?? '',
      toUid:     d.toUid,
      toEmail:   d.toEmail ?? '',
      status:    d.status ?? 'pending',
      createdAt: ts(d.createdAt) ?? new Date().toISOString(),
      expiresAt: ts(d.expiresAt) ?? new Date().toISOString(),
    };
    const created = await upsertDoc('claim_requests', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateOrgInviteConsents() {
  // Firestore: 'orgInviteConsents', Appwrite: 'org_invite_consents'
  console.log('\n── org_invite_consents ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('orgInviteConsents'))) {
    const d = doc.data();
    const data = {
      orgId:              d.orgId,
      orgName:            d.orgName ?? '',
      childUid:           d.childUid,
      childName:          d.childName ?? '',
      invitedByUid:       d.invitedBy ?? d.invitedByUid ?? null,
      invitedByName:      d.invitedByName ?? '',
      status:             d.status ?? 'pending',
      parentUids:         d.parentUids ?? [],
      proposedGuardianUids: d.proposedGuardianUids ?? [],
      approvedBy:         d.approvedBy ?? null,
      vetoedBy:           d.vetoedBy ?? null,
      createdAt:          ts(d.createdAt) ?? new Date().toISOString(),
      expiresAt:          ts(d.expiresAt),
    };
    const created = await upsertDoc('org_invite_consents', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

async function migrateReports() {
  console.log('\n── reports ──');
  let n = 0, skip = 0;
  for await (const doc of paginate(fsDb.collection('reports'))) {
    const d = doc.data();
    const data = {
      orgId:             d.orgId,
      reportedByUid:     d.reportedByUid ?? null,
      convId:            d.convId ?? null,
      orgAdminUid:       d.orgAdminUid ?? '',
      messageSenderName: d.messageSenderName ?? '',
      messageText:       d.messageText ?? '',
      createdAt:         ts(d.createdAt) ?? new Date().toISOString(),
    };
    const created = await upsertDoc('reports', doc.id, data);
    created ? n++ : skip++;
    process.stdout.write(created ? '.' : '~');
  }
  console.log(`\n  ✓ ${n} neu, ${skip} übersprungen`);
}

// ─── Hauptprogramm ────────────────────────────────────────────────────────────

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===\n');
  console.log(`Flags: skip-auth=${SKIP_AUTH}, skip-storage=${SKIP_STORAGE}, only-storage=${ONLY_STORAGE}`);

  if (!ONLY_STORAGE) {
    if (!SKIP_AUTH) await migrateAuth();

    console.log('\n── Phase 2: Firestore-Collections ──');
    await migrateUsers();
    await migrateOrganizations();
    await migrateMembers();
    await migrateConversations();   // enthält Storage-Migration für Gruppenbilder
    await migrateMessages();        // enthält Storage-Migration für Medien
    await migratePolls();
    await migrateScheduledMessages();
    await migrateAnnouncements();
    await migrateInvitations();
    await migrateClaimRequests();
    await migrateOrgInviteConsents();
    await migrateReports();
  } else {
    // Nur Storage: Appwrite-Dokumente aktualisieren die noch Firebase-URLs enthalten
    console.log('\n── Nur Storage: Nachbearbeitung bestehender Appwrite-Dokumente ──');
    await repairStorageUrls();
  }

  console.log('\n\n✅ Migration abgeschlossen.');
}

/**
 * Nachbearbeitung: findet Appwrite-Dokumente die noch Firebase-URLs enthalten
 * und migriert die Dateien nach Appwrite Storage.
 * Nützlich wenn die erste Migration mit --skip-storage lief.
 */
async function repairStorageUrls() {
  const collections = [
    { col: 'conversations', fields: ['imageUrl'] },
    { col: 'messages',      fields: ['imageUrl', 'audioUrl', 'fileUrl'] },
  ];
  for (const { col, fields } of collections) {
    console.log(`\n  Prüfe ${col}...`);
    let fixed = 0;
    // Appwrite: paginierte Abfrage
    let offset = 0;
    while (true) {
      const result = await awDb.listDocuments(DB_ID, col, [
        Query.limit(100), Query.offset(offset),
      ]);
      if (result.documents.length === 0) break;
      for (const doc of result.documents) {
        const updates = {};
        for (const field of fields) {
          if (isFirebaseUrl(doc[field])) {
            updates[field] = await migrateFile(doc[field], doc.senderUid ?? doc.adminUid ?? null);
          }
        }
        if (Object.keys(updates).length > 0 && !DRY_RUN) {
          await awDb.updateDocument(DB_ID, col, doc.$id, updates);
          fixed++;
          process.stdout.write('✓');
        }
      }
      offset += result.documents.length;
      if (result.documents.length < 100) break;
    }
    console.log(`\n  ${fixed} Dokumente aktualisiert`);
  }
}

main().catch((e) => {
  console.error('\n✗ Migration fehlgeschlagen:', JSON.stringify({
    message: e.message,
    code: e.code,
    response: e.response,
    type: e.type,
  }, null, 2));
  process.exit(1);
});
