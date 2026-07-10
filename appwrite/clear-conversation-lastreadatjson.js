/**
 * Leert das (nicht mehr genutzte) lastReadAtJson-Feld aller Conversation-Dokumente.
 *
 * Hintergrund: Früher schrieb mark-as-read bei jedem Aufruf den Lesezeitpunkt in
 * conversations.lastReadAtJson (Kompat für alte App-Versionen). Das Feld wurde nie
 * bereinigt und wuchs über die Zeit stark an → große Conversation-Dokumente →
 * getDocument(conv) lief in Timeouts. Der Kompat-Block ist entfernt; der Lesestatus
 * läuft ausschließlich über die read_receipts-Collection. Dieses Skript entfernt die
 * aufgeblähten Alt-Daten, damit getDocument wieder schnell ist.
 *
 * Idempotent: bereits leere/entfernte Felder werden übersprungen.
 *
 * Usage:
 *   node clear-conversation-lastreadatjson.js                              # Dry-run
 *   node clear-conversation-lastreadatjson.js --delete --confirm=<projId>  # Führt aus
 *
 * Voraussetzung: .env mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Query } from 'node-appwrite';

config();

const DRY_RUN = !process.argv.includes('--delete');

if (!DRY_RUN) {
  const confirmArg = process.argv.find(a => a.startsWith('--confirm='));
  const confirmId  = confirmArg?.slice('--confirm='.length);
  if (confirmId !== process.env.APPWRITE_PROJECT_ID) {
    console.error(
      `Fehler: --confirm=<projectId> muss mit APPWRITE_PROJECT_ID übereinstimmen.\n` +
      `  Erwartet: ${process.env.APPWRITE_PROJECT_ID}\n` +
      `  Erhalten: ${confirmId ?? '(nicht angegeben)'}\n\n` +
      `  Beispiel: node clear-conversation-lastreadatjson.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`
    );
    process.exit(1);
  }
}

const client = new Client()
  .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID     = 'guardian';
const COL_CONVS = 'conversations';
const PAGE_SIZE = 100;

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===\n');
  console.log('Lade alle Conversations...');

  let cursor = null;
  let checked = 0;
  let cleared = 0;
  let maxLen = 0;

  while (true) {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const page = await db.listDocuments(DB_ID, COL_CONVS, queries);

    for (const doc of page.documents) {
      checked++;
      const val = doc.lastReadAtJson;
      const len = typeof val === 'string' ? val.length : 0;
      if (len === 0) continue; // bereits leer
      if (len > maxLen) maxLen = len;
      console.log(`CLEAR ${doc.$id} (lastReadAtJson: ${len} Zeichen)`);
      if (!DRY_RUN) {
        await db.updateDocument(DB_ID, COL_CONVS, doc.$id, { lastReadAtJson: null });
      }
      cleared++;
    }

    if (page.documents.length < PAGE_SIZE) break;
    cursor = page.documents[page.documents.length - 1].$id;
  }

  console.log(`\n✅ ${DRY_RUN ? 'Dry-run' : 'Cleanup'} abgeschlossen.`);
  console.log(`   Conversations geprüft:   ${checked}`);
  console.log(`   lastReadAtJson geleert:  ${cleared}`);
  console.log(`   größtes Feld (Zeichen):  ${maxLen}`);
  if (DRY_RUN) {
    console.log(`\nZum Ausführen: node clear-conversation-lastreadatjson.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`);
  }
}

main().catch(console.error);
