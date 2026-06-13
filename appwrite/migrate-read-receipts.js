/**
 * Migration: lastReadAtJson → read_receipts Collection
 *
 * Liest alle Conversations, extrahiert den lastReadAtJson-Eintrag pro Nutzer
 * und erstellt entsprechende Dokumente in der neuen read_receipts-Collection.
 *
 * Idempotent: bereits vorhandene read_receipts-Dokumente werden aktualisiert.
 *
 * Usage:
 *   node migrate-read-receipts.js
 *   node migrate-read-receipts.js --dry-run
 *
 * Erforderliche Umgebungsvariablen (.env):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Query, ID, Permission, Role } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const client = new Client()
  .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID        = 'guardian';
const COL_CONVS    = 'conversations';
const COL_RECEIPTS = 'read_receipts';
const PAGE_SIZE    = 100;

async function fetchAllConversations() {
  const all = [];
  let offset = 0;
  while (true) {
    const result = await db.listDocuments(DB_ID, COL_CONVS, [
      Query.limit(PAGE_SIZE),
      Query.offset(offset),
    ]);
    all.push(...result.documents);
    if (result.documents.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }
  return all;
}

async function upsertReceipt(convId, uid, readAt) {
  // Vorhandenes Dokument suchen
  const existing = await db.listDocuments(DB_ID, COL_RECEIPTS, [
    Query.equal('convId', convId),
    Query.equal('uid', uid),
    Query.limit(1),
  ]);

  if (existing.documents.length > 0) {
    if (DRY_RUN) {
      console.log(`  [DRY] update receipt ${existing.documents[0].$id} (convId=${convId} uid=${uid})`);
      return;
    }
    await db.updateDocument(DB_ID, COL_RECEIPTS, existing.documents[0].$id, { readAt });
    return;
  }

  if (DRY_RUN) {
    console.log(`  [DRY] create receipt (convId=${convId} uid=${uid} readAt=${readAt})`);
    return;
  }
  await db.createDocument(DB_ID, COL_RECEIPTS, ID.unique(), {
    convId,
    uid,
    readAt,
  }, [
    Permission.read(Role.user(uid)),
    Permission.update(Role.user(uid)),
    Permission.delete(Role.user(uid)),
  ]);
}

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===\n');

  console.log('Lade alle Conversations...');
  const conversations = await fetchAllConversations();
  console.log(`${conversations.length} Conversations gefunden.\n`);

  let totalReceipts = 0;
  let totalSkipped  = 0;

  for (const conv of conversations) {
    const json = conv.lastReadAtJson;
    if (!json) { totalSkipped++; continue; }

    let readMap;
    try {
      readMap = JSON.parse(json);
    } catch (_) {
      console.warn(`  ⚠ Ungültiges lastReadAtJson bei convId=${conv.$id}, übersprungen`);
      totalSkipped++;
      continue;
    }

    const entries = Object.entries(readMap);
    if (entries.length === 0) { totalSkipped++; continue; }

    console.log(`Conversation ${conv.$id}: ${entries.length} Einträge`);
    for (const [uid, readAt] of entries) {
      try {
        await upsertReceipt(conv.$id, uid, readAt);
        totalReceipts++;
      } catch (e) {
        console.error(`  ✗ Fehler bei uid=${uid} convId=${conv.$id}: ${e.message}`);
      }
    }
  }

  console.log(`\n✅ Migration abgeschlossen.`);
  console.log(`   Receipts erstellt/aktualisiert: ${totalReceipts}`);
  console.log(`   Conversations ohne Einträge:    ${totalSkipped}`);
  if (!DRY_RUN) {
    console.log('\nNächster Schritt: lastReadAtJson-Attribut aus Conversations entfernen');
    console.log('(erst nach vollständigem Flutter-Rollout)');
  }
}

main().catch(console.error);
