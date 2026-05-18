/**
 * One-time fix: add missing permissions to migrated conversation documents.
 *
 * Root cause: migrate.js created conversation documents with empty $permissions.
 * With documentSecurity: true, this makes them inaccessible to Flutter clients → 401.
 *
 * Fix: add Permission.read(Role.users()) + Permission.update(Role.users()) to every
 * conversation document that currently has no permissions.
 *
 * Safe to re-run (idempotent via --fix-all flag which updates all regardless).
 *
 * Usage:
 *   node fix-conversation-permissions.js           (only fixes docs with empty permissions)
 *   node fix-conversation-permissions.js --dry-run  (count only, no changes)
 *   node fix-conversation-permissions.js --fix-all  (update all docs, useful after re-run)
 */

import { config } from 'dotenv';
import { Client, Databases, Permission, Role, Query } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');
const FIX_ALL = process.argv.includes('--fix-all');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);

const DB_ID = 'guardian';
const COL   = 'conversations';

const PERMS = [
  Permission.read(Role.users()),
  Permission.update(Role.users()),
];

async function main() {
  console.log('=== fix-conversation-permissions ===');
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : FIX_ALL ? 'FIX ALL' : 'FIX EMPTY'}\n`);

  let cursor  = null;
  let total   = 0;
  let fixed   = 0;
  let skipped = 0;
  let errors  = 0;

  do {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));

    const result = await db.listDocuments(DB_ID, COL, q);
    total += result.documents.length;

    for (const doc of result.documents) {
      const hasPerms = doc.$permissions && doc.$permissions.length > 0;

      if (!FIX_ALL && hasPerms) {
        skipped++;
        continue;
      }

      if (DRY_RUN) {
        fixed++;
        continue;
      }

      try {
        await db.updateDocument(DB_ID, COL, doc.$id, {}, PERMS);
        fixed++;
        process.stdout.write('.');
      } catch (e) {
        errors++;
        console.error(`\n  ✗ ${doc.$id}: ${e.message}`);
      }
    }

    cursor = result.documents.length === 100
      ? result.documents.at(-1).$id
      : null;
  } while (cursor);

  console.log(`\n\nTotal: ${total}  Fixed: ${fixed}  Skipped (had perms): ${skipped}  Errors: ${errors}`);
  if (DRY_RUN) console.log('\n[DRY RUN] No changes made.');
  else console.log('\nDone. Flutter app should now be able to access all conversations.');
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
