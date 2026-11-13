/**
 * Bereinigt verwaiste Dokumente deren orgId nicht mehr in der organizations-Collection
 * existiert — und Orgs die beim Löschen abgebrochen sind (deletionStatus: 'deleting').
 *
 *   members, conversations (+ Sub-Collections), announcements, invitations,
 *   org_invite_consents, audit_log, reports
 *
 * Sub-Collections einer Conversation (per convId):
 *   chat_messages (+ zugehörige Storage-Dateien), polls, scheduled_messages, read_receipts
 *
 * Usage:
 *   node cleanup-orphaned-data.js                              # Dry-run
 *   node cleanup-orphaned-data.js --delete --confirm=<projId> # Löscht tatsächlich
 *
 * Voraussetzung: .env mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Storage, Query } from 'node-appwrite';

config();

const DRY_RUN = !process.argv.includes('--delete');

// Sicherheitsgate: --delete erfordert --confirm=<projectId> damit man nicht
// versehentlich die falsche Umgebung (z.B. Produktion statt Staging) leert.
if (!DRY_RUN) {
  const confirmArg = process.argv.find(a => a.startsWith('--confirm='));
  const confirmId  = confirmArg?.slice('--confirm='.length);
  if (confirmId !== process.env.APPWRITE_PROJECT_ID) {
    console.error(
      `Fehler: --confirm=<projectId> muss mit APPWRITE_PROJECT_ID übereinstimmen.\n` +
      `  Erwartet: ${process.env.APPWRITE_PROJECT_ID}\n` +
      `  Erhalten: ${confirmId ?? '(nicht angegeben)'}\n\n` +
      `  Beispiel: node cleanup-orphaned-data.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`
    );
    process.exit(1);
  }
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db      = new Databases(client);
const storage = new Storage(client);

const DB_ID          = 'guardian';
const BUCKET_MEDIA   = '6a02e524000954c9f1de';

const COL_ORGS          = 'organizations';
const COL_MEMBERS       = 'members';
const COL_CONVS         = 'conversations';
const COL_MESSAGES      = 'chat_messages';
const COL_POLLS         = 'polls';
const COL_SCHEDULED     = 'scheduled_messages';
const COL_RECEIPTS      = 'read_receipts';
const COL_ANNOUNCEMENTS = 'announcements';
const COL_INVITATIONS   = 'invitations';
const COL_CONSENTS      = 'org_invite_consents';
const COL_AUDIT         = 'audit_log';
const COL_REPORTS       = 'reports';

// Zähler für den Abschlussbericht
const counts = {};
function inc(col, n = 1) {
  counts[col] = (counts[col] ?? 0) + n;
}

// Alle Dokumente einer Collection seitenweise laden (cursor-basiert)
async function* listAll(col, queries = []) {
  let cursor = null;
  while (true) {
    const q = [...queries, Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const { documents } = await db.listDocuments(DB_ID, col, q);
    for (const doc of documents) yield doc;
    if (documents.length < 100) break;
    cursor = documents[documents.length - 1].$id;
  }
}

async function deleteDoc(col, id) {
  inc(col);
  if (DRY_RUN) return;
  await db.deleteDocument(DB_ID, col, id);
}

async function deleteBatch(col, queries) {
  for await (const doc of listAll(col, queries)) {
    await deleteDoc(col, doc.$id);
  }
}

// Löscht Messages inklusive zugehöriger Storage-Dateien (Bilder, Audio, Anhänge).
async function deleteMessageBatch(queries) {
  for await (const msg of listAll(COL_MESSAGES, queries)) {
    if (!DRY_RUN) await deleteMessageFiles(storage, msg);
    await deleteDoc(COL_MESSAGES, msg.$id);
  }
}

// Extrahiert die Appwrite-File-ID aus einer Storage-View-URL.
// Format: .../storage/buckets/<bucketId>/files/<fileId>/view?...
function extractStorageFileId(url) {
  const m = url && url.match(/\/files\/([^/?]+)\/view/);
  return m ? m[1] : null;
}

// Löscht die Storage-Dateien einer Nachricht — aber nur solche, die der Autor
// der Nachricht selbst hochgeladen hat. Die URLs in einer Nachricht sind
// Client-Daten: ohne diese Prüfung könnte jemand die Datei-ID einer fremden
// Datei in eine eigene Nachricht schreiben und sie mit API-Key löschen lassen.
// Der Autor wird aus der Dokument-ACL gelesen (ein Client kann dort nur seine
// eigene `user:`-Rolle setzen), nicht aus dem frei beschreibbaren `senderUid`.
// Uploads tragen `delete("user:<uploader>")` (siehe chat_service.dart).
async function deleteMessageFiles(storage, msg) {
  const authorPerms = (msg.$permissions ?? [])
    .map((p) => p.match(/^(?:update|delete)\("user:([^"/]+)/)?.[1])
    .filter(Boolean)
    .map((uid) => `delete("user:${uid}")`);
  if (authorPerms.length === 0) return;
  const fileIds = [...new Set(
    [msg.imageUrl, ...(msg.imageUrls ?? []), msg.audioUrl, msg.fileUrl]
      .filter(Boolean)
      .map(extractStorageFileId)
      .filter(Boolean),
  )];
  // Fehler ignorieren — Datei kann bereits weg sein oder nie existiert haben.
  await Promise.allSettled(fileIds.map(async (id) => {
    const file = await storage.getFile(BUCKET_MEDIA, id);
    if (!file.$permissions.some((p) => authorPerms.includes(p))) return;
    await storage.deleteFile(BUCKET_MEDIA, id);
  }));
}

async function main() {
  if (DRY_RUN) {
    console.log('DRY-RUN Modus — es wird nichts gelöscht.\nMit --delete --confirm=<projectId> tatsächlich löschen.\n');
  } else {
    console.log('LÖSCHEN aktiv — alle verwaisten Dokumente werden entfernt.\n');
  }

  // 1. Alle existierenden Org-IDs einlesen.
  //    Orgs mit deletionStatus='deleting' gelten als nicht-existent —
  //    sie sind halbgelöschte Orgs bei denen die Cloud Function abgestürzt ist.
  console.log('Lade existierende Organisationen …');
  const existingOrgIds = new Set();
  for await (const org of listAll(COL_ORGS)) {
    if (org.deletionStatus !== 'deleting') {
      existingOrgIds.add(org.$id);
    } else {
      console.log(`  [org] ${org.$id} — deletionStatus=deleting, wird als verwaist behandelt`);
    }
  }
  console.log(`  ${existingOrgIds.size} aktive Org(s) gefunden.\n`);

  // 2. Members bereinigen
  console.log('Prüfe members …');
  for await (const doc of listAll(COL_MEMBERS)) {
    if (!existingOrgIds.has(doc.orgId)) {
      console.log(`  [members] ${doc.$id}  orgId=${doc.orgId}`);
      await deleteDoc(COL_MEMBERS, doc.$id);
    }
  }

  // 3. Conversations + Sub-Collections bereinigen
  console.log('Prüfe conversations …');
  for await (const conv of listAll(COL_CONVS)) {
    if (!existingOrgIds.has(conv.orgId)) {
      console.log(`  [conversations] ${conv.$id}  orgId=${conv.orgId}`);
      await Promise.all([
        deleteMessageBatch([Query.equal('convId', conv.$id)]),
        deleteBatch(COL_POLLS,     [Query.equal('convId', conv.$id)]),
        deleteBatch(COL_SCHEDULED, [Query.equal('convId', conv.$id)]),
        deleteBatch(COL_RECEIPTS,  [Query.equal('convId', conv.$id)]),
      ]);
      await deleteDoc(COL_CONVS, conv.$id);
    }
  }

  // 4. Org-weite Collections bereinigen
  for (const col of [COL_ANNOUNCEMENTS, COL_INVITATIONS, COL_CONSENTS, COL_AUDIT, COL_REPORTS]) {
    console.log(`Prüfe ${col} …`);
    for await (const doc of listAll(col)) {
      if (doc.orgId && !existingOrgIds.has(doc.orgId)) {
        console.log(`  [${col}] ${doc.$id}  orgId=${doc.orgId}`);
        await deleteDoc(col, doc.$id);
      }
    }
  }

  // 5. Halbgelöschte Org-Docs selbst entfernen (zuletzt, da sie als Anker dienten)
  if (!DRY_RUN) {
    for await (const org of listAll(COL_ORGS, [Query.equal('deletionStatus', 'deleting')])) {
      console.log(`  [organizations] ${org.$id} — halbgelöscht, wird entfernt`);
      inc(COL_ORGS);
      await db.deleteDocument(DB_ID, COL_ORGS, org.$id);
    }
  }

  // 6. Abschlussbericht
  console.log('\n--- Ergebnis ---');
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  if (total === 0) {
    console.log('Keine verwaisten Dokumente gefunden.');
  } else {
    for (const [col, n] of Object.entries(counts)) {
      console.log(`  ${col}: ${n} Dokument(e) ${DRY_RUN ? 'würden gelöscht' : 'gelöscht'}`);
    }
    console.log(`  Gesamt: ${total}`);
    if (DRY_RUN) {
      console.log('\nMit --delete --confirm=<projectId> erneut ausführen um tatsächlich zu löschen.');
    }
  }
}

main().catch(e => {
  console.error('Fehler:', e.message);
  process.exit(1);
});
