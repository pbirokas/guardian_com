/**
 * Migration: "messages" → "chat_messages"
 *
 * Hintergrund: Der Collection-Name "messages" kollidiert in Appwrite v1.9.0
 * mit dem eingebauten Messaging-Dienst (/v1/messaging/messages), wodurch
 * Datenbank-Events für diese Collection nicht mehr gefeuert werden.
 *
 * Was dieses Skript macht:
 *   1. Erstellt "chat_messages" Collection mit identischem Schema
 *   2. Migriert alle Dokumente von "messages" → "chat_messages"
 *
 * Usage:
 *   node migrate-to-chat-messages.js           (führt Migration durch)
 *   node migrate-to-chat-messages.js --dry-run (zeigt nur Anzahl Docs)
 *
 * Vorher sicherstellen:
 *   - App ist offline / wird nicht aktiv genutzt (kein neues Schreiben während Migration)
 *   - .env mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY gesetzt
 */

import { config } from 'dotenv';
import { Client, Databases, Permission, Role, Query } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);

const DB_ID     = 'guardian';
const OLD_COL   = 'messages';
const NEW_COL   = 'chat_messages';

const COL_PERMISSIONS = [
  Permission.read(Role.users()),
  Permission.create(Role.users()),
  Permission.delete(Role.users()),
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Schema-Erstellung ─────────────────────────────────────────────────────────

async function createSchema() {
  console.log(`Creating collection "${NEW_COL}"...`);
  try {
    await db.createCollection(DB_ID, NEW_COL, 'ChatMessages', COL_PERMISSIONS, true);
    console.log('✓ Collection created');
  } catch (e) {
    if (e.code === 409) {
      console.log('  Collection already exists, skipping creation');
    } else {
      throw e;
    }
  }

  const str  = (key, size, required = false, def = null) =>
    db.createStringAttribute(DB_ID, NEW_COL, key, size, required, def ?? undefined).catch(skipIfExists);
  const dt   = (key, required = false) =>
    db.createDatetimeAttribute(DB_ID, NEW_COL, key, required).catch(skipIfExists);
  const bool = (key, def = false) =>
    db.createBooleanAttribute(DB_ID, NEW_COL, key, false, def).catch(skipIfExists);
  const int  = (key) =>
    db.createIntegerAttribute(DB_ID, NEW_COL, key, false).catch(skipIfExists);

  function skipIfExists(e) {
    if (e.code === 409) return;
    throw e;
  }

  console.log('Creating attributes...');
  await str('convId',            36,   true);
  await str('orgId',             36,   true);
  await str('senderUid',         36,   true);
  await str('senderName',        100,  false, '');
  await str('text',              4096, false, '');
  await dt ('sentAt',            true);
  await str('imageUrl',          512);
  await str('audioUrl',          512);
  await int('audioDurationMs');
  await str('pollId',            36);
  await str('fileUrl',           512);
  await str('fileName',          255);
  await int('fileSizeBytes');
  await dt ('editedAt');
  await bool('isArchived',       false);
  await str('archivedByUid',     36);
  await str('archivedByName',    100);
  await str('replyToId',         36);
  await str('replyToSenderName', 100);
  await str('replyToText',       500);
  await str('type',              20,   false, 'user');
  await str('systemEvent',       50);
  await str('systemActorName',   100);
  await str('systemTargetName',  100);
  await bool('isGif',            false);
  await dt ('deletedAt');
  await str('deletedBy',         36);
  await str('reactionsJson',     4096);
  console.log('✓ Attributes submitted — waiting 15s for Appwrite to process...');
  await sleep(15000);

  console.log('Creating indexes...');
  const idx = (key, type, attrs, orders) =>
    db.createIndex(DB_ID, NEW_COL, key, type, attrs, orders).catch((e) => {
      console.log(`  Index ${key}: ${e.message} (skipping)`);
    });

  await idx('convId_idx',        'key', ['convId'],             []);
  await idx('convId_sentAt_idx', 'key', ['convId', 'sentAt'],   ['ASC']);
  await idx('senderUid_idx',     'key', ['senderUid'],          []);
  console.log('✓ Indexes submitted');
  await sleep(5000);
}

// ── Dokument-Migration ────────────────────────────────────────────────────────

async function migrateDocuments() {
  console.log(`\nCounting documents in "${OLD_COL}"...`);
  const countRes = await db.listDocuments(DB_ID, OLD_COL, [Query.limit(1)]);
  console.log(`  Total: ${countRes.total} documents`);

  if (DRY_RUN) {
    console.log('[DRY RUN] Skipping actual migration.');
    return;
  }

  let cursor = null;
  let migrated = 0;
  let skipped  = 0;
  let errors   = 0;

  do {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));

    const result = await db.listDocuments(DB_ID, OLD_COL, q);

    for (const doc of result.documents) {
      const {
        $id, $collectionId, $databaseId, $createdAt, $updatedAt, $permissions,
        ...data
      } = doc;

      // Dokumente ohne explizite Permissions bekommen read(users) damit sie lesbar bleiben
      const perms = $permissions.length > 0
        ? $permissions
        : [Permission.read(Role.users())];

      try {
        await db.createDocument(DB_ID, NEW_COL, $id, data, perms);
        migrated++;
      } catch (e) {
        if (e.code === 409) {
          skipped++; // bereits migriert (Skript wurde nochmal ausgeführt)
        } else {
          errors++;
          console.error(`  ✗ ${$id}: ${e.message}`);
        }
      }
    }

    cursor = result.documents.length === 100
      ? result.documents.at(-1).$id
      : null;

    process.stdout.write(`\r  Migrated: ${migrated}  Skipped: ${skipped}  Errors: ${errors}  `);
  } while (cursor);

  console.log(`\n✓ Migration complete: ${migrated} migrated, ${skipped} skipped, ${errors} errors`);
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log('=== chat_messages Migration ===');
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : 'LIVE'}\n`);

  await createSchema();
  await migrateDocuments();

  console.log('\n=== Next steps ===');
  console.log('1. appwrite push function --function-id on-new-message');
  console.log('2. appwrite push function --function-id cleanup-old-messages');
  console.log('3. appwrite push function --function-id get-child-summary');
  console.log('4. Flutter App neu bauen und testen');
  console.log('5. Wenn Events feuern: alte "messages" Collection in Appwrite Console löschen');
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
