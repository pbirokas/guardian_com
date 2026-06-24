/**
 * Re-Key der read_receipts-Collection auf deterministische Dokument-IDs.
 *
 * Hintergrund: mark-as-read nutzt jetzt eine deterministische ID
 * (sha256(convId:uid), auf 36 Zeichen gekürzt) statt ID.unique() + listDocuments-Suche.
 * Dieses Skript überführt bestehende Receipts (mit zufälligen IDs) auf das neue
 * Schema und entfernt dabei doppelte Receipts pro (convId, uid).
 *
 * Pro (convId, uid)-Gruppe:
 *   - latest = jüngster readAt-Wert der Gruppe
 *   - genau ein Dokument mit der deterministischen ID erhält latest
 *   - alle übrigen Dokumente der Gruppe werden gelöscht
 *
 * Idempotent: bereits migrierte Receipts (ID == deterministische ID) bleiben unberührt.
 *
 * Usage:
 *   node rekey-read-receipts.js                              # Dry-run (keine Änderungen)
 *   node rekey-read-receipts.js --delete --confirm=<projId>  # Führt Änderungen aus
 *
 * Voraussetzung: .env mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Query, Permission, Role } from 'node-appwrite';
import crypto from 'crypto';

config();

const DRY_RUN = !process.argv.includes('--delete');

// Sicherheitsgate: --delete erfordert --confirm=<projectId>, damit nicht
// versehentlich die falsche Umgebung (z.B. Produktion) verändert wird.
if (!DRY_RUN) {
  const confirmArg = process.argv.find(a => a.startsWith('--confirm='));
  const confirmId  = confirmArg?.slice('--confirm='.length);
  if (confirmId !== process.env.APPWRITE_PROJECT_ID) {
    console.error(
      `Fehler: --confirm=<projectId> muss mit APPWRITE_PROJECT_ID übereinstimmen.\n` +
      `  Erwartet: ${process.env.APPWRITE_PROJECT_ID}\n` +
      `  Erhalten: ${confirmId ?? '(nicht angegeben)'}\n\n` +
      `  Beispiel: node rekey-read-receipts.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`
    );
    process.exit(1);
  }
}

const client = new Client()
  .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const DB_ID        = 'guardian';
const COL_RECEIPTS = 'read_receipts';
const PAGE_SIZE    = 100;

// Muss identisch zu receiptIdFor in functions/mark-as-read/src/main.js sein.
function receiptIdFor(convId, uid) {
  return crypto.createHash('sha256').update(`${convId}:${uid}`).digest('hex').slice(0, 36);
}

// Cursor-basierte Pagination — robust auch bei großen Collections
// (tiefe Offsets werden in MariaDB sonst langsam).
async function fetchAllReceipts() {
  const all = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, COL_RECEIPTS, queries);
    all.push(...result.documents);
    if (result.documents.length < PAGE_SIZE) break;
    cursor = result.documents[result.documents.length - 1].$id;
  }
  return all;
}

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===\n');

  console.log('Lade alle read_receipts...');
  const receipts = await fetchAllReceipts();
  console.log(`${receipts.length} Receipts gefunden.\n`);

  // Gruppieren nach (convId, uid).
  const groups = new Map(); // key -> { convId, uid, docs: [] }
  for (const doc of receipts) {
    const { convId, uid } = doc;
    if (!convId || !uid) {
      console.warn(`  ⚠ Receipt ${doc.$id} ohne convId/uid — übersprungen`);
      continue;
    }
    const key = `${convId}::${uid}`;
    if (!groups.has(key)) groups.set(key, { convId, uid, docs: [] });
    groups.get(key).docs.push(doc);
  }

  let migrated = 0;   // neue deterministische Dokumente erstellt
  let updated  = 0;   // bestehendes deterministisches Dokument aktualisiert
  let deleted  = 0;   // alte/überzählige Dokumente gelöscht
  let untouched = 0;  // bereits korrekt, nichts zu tun

  for (const { convId, uid, docs } of groups.values()) {
    const detId = receiptIdFor(convId, uid);
    // Jüngsten readAt-Wert der Gruppe bestimmen.
    const latest = docs.reduce((a, b) =>
      new Date(b.readAt) > new Date(a.readAt) ? b : a
    ).readAt;

    const canonical = docs.find(d => d.$id === detId) || null;
    const extras = docs.filter(d => d.$id !== detId);

    if (canonical) {
      // Kanonisches Dokument existiert: jüngsten Timestamp setzen, etwaige
      // Duplikate werden unten über die extras-Schleife entfernt.
      if (new Date(latest) > new Date(canonical.readAt)) {
        console.log(`UPDATE  ${detId} (convId=${convId} uid=${uid}) readAt→${latest}`);
        if (!DRY_RUN) await db.updateDocument(DB_ID, COL_RECEIPTS, detId, { readAt: latest });
        updated++;
      } else if (extras.length === 0) {
        // Bereits korrekt migriert, nichts zu tun.
        untouched++;
      }
    } else {
      // Kein kanonisches Dokument: mit deterministischer ID neu anlegen.
      console.log(`CREATE  ${detId} (convId=${convId} uid=${uid}) readAt=${latest}`);
      if (!DRY_RUN) {
        await db.createDocument(DB_ID, COL_RECEIPTS, detId, { convId, uid, readAt: latest }, [
          Permission.read(Role.user(uid)),
          Permission.update(Role.user(uid)),
          Permission.delete(Role.user(uid)),
        ]);
      }
      migrated++;
    }

    // Alte/überzählige Dokumente entfernen.
    for (const extra of extras) {
      console.log(`  DELETE ${extra.$id} (dup convId=${convId} uid=${uid})`);
      if (!DRY_RUN) await db.deleteDocument(DB_ID, COL_RECEIPTS, extra.$id);
      deleted++;
    }
  }

  console.log(`\n✅ ${DRY_RUN ? 'Dry-run' : 'Migration'} abgeschlossen.`);
  console.log(`   Gruppen (convId,uid):     ${groups.size}`);
  console.log(`   Neu erstellt (det. ID):   ${migrated}`);
  console.log(`   Aktualisiert:             ${updated}`);
  console.log(`   Gelöscht (Duplikate/alt): ${deleted}`);
  console.log(`   Unverändert:              ${untouched}`);
  if (DRY_RUN) {
    console.log(`\nZum Ausführen: node rekey-read-receipts.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`);
  }
}

main().catch(console.error);
