/**
 * Legt fehlende Datenbank-Indexes an, ohne bestehende Collections zu verändern.
 * Sicher: nur additive Operation, kein Löschen.
 *
 * Usage: node add-missing-indexes.js [--dry-run]
 */

import { config } from 'dotenv';
import { Client, Databases, IndexType } from 'node-appwrite';

config();

const DRY_RUN = process.argv.includes('--dry-run');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID = 'guardian';

const INDEXES_TO_ADD = [
  {
    collectionId: 'announcements',
    key: 'eventEndDate_idx',
    type: IndexType.Key,
    attributes: ['eventEndDate'],
    orders: ['ASC'],
  },
];

async function main() {
  console.log('=== add-missing-indexes ===');
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : 'LIVE'}\n`);

  for (const idx of INDEXES_TO_ADD) {
    const label = `${idx.collectionId}.${idx.key}`;

    // Prüfen ob Index bereits existiert
    try {
      const col = await db.getCollection(DB_ID, idx.collectionId);
      const exists = col.indexes.some((i) => i.key === idx.key);
      if (exists) {
        console.log(`  ✓ ${label}: already exists — skipping`);
        continue;
      }
    } catch (e) {
      console.error(`  ✗ ${label}: getCollection failed — ${e.message}`);
      continue;
    }

    if (DRY_RUN) {
      console.log(`  [DRY] ${label}: would create index on [${idx.attributes.join(', ')}]`);
      continue;
    }

    try {
      await db.createIndex(DB_ID, idx.collectionId, idx.key, idx.type, idx.attributes, idx.orders);
      console.log(`  ✓ ${label}: created`);
    } catch (e) {
      console.error(`  ✗ ${label}: ${e.message}`);
    }
  }

  console.log('\nDone.');
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
