/**
 * Setzt alte, auf Firebase Storage zeigende Bild-URLs in der Datenbank zurück.
 *
 * Hintergrund: Der kostenlose Firebase-Storage-Zeitraum ist abgelaufen, alte
 * Bild-URLs (host = firebasestorage.googleapis.com) liefern jetzt HTTP 402.
 * Neue Bilder werden nach Appwrite Storage hochgeladen. Dieses Skript leert die
 * toten Firebase-Verweise, damit die App nicht unnötig fehlschlagende Requests
 * absetzt — Profile/Gruppen zeigen dann Initialen bzw. Icon (Crash-sicher durch
 * UserAvatar/GroupAvatar), Nutzer laden ihr Bild bei Gelegenheit neu hoch.
 *
 * Betroffen:
 *   users.photoUrl, conversations.imageUrl
 *
 * Idempotent: bereits geleerte oder bereits auf Appwrite zeigende URLs bleiben unberührt.
 *
 * Usage:
 *   node reset-firebase-image-urls.js                              # Dry-run
 *   node reset-firebase-image-urls.js --delete --confirm=<projId>  # Führt Änderungen aus
 *
 * Voraussetzung: .env mit APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Query } from 'node-appwrite';

config();

const DRY_RUN = !process.argv.includes('--delete');

// Sicherheitsgate: --delete erfordert --confirm=<projectId>.
if (!DRY_RUN) {
  const confirmArg = process.argv.find(a => a.startsWith('--confirm='));
  const confirmId  = confirmArg?.slice('--confirm='.length);
  if (confirmId !== process.env.APPWRITE_PROJECT_ID) {
    console.error(
      `Fehler: --confirm=<projectId> muss mit APPWRITE_PROJECT_ID übereinstimmen.\n` +
      `  Erwartet: ${process.env.APPWRITE_PROJECT_ID}\n` +
      `  Erhalten: ${confirmId ?? '(nicht angegeben)'}\n\n` +
      `  Beispiel: node reset-firebase-image-urls.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`
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
const PAGE_SIZE = 100;
const FIREBASE_HOST = 'firebasestorage.googleapis.com';

function isFirebaseUrl(url) {
  if (typeof url !== 'string' || url.length === 0) return false;
  try {
    return new URL(url).host === FIREBASE_HOST;
  } catch (_) {
    return false;
  }
}

// Cursor-basierte Pagination — robust auch bei großen Collections.
async function fetchAll(collectionId) {
  const all = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, collectionId, queries);
    all.push(...result.documents);
    if (result.documents.length < PAGE_SIZE) break;
    cursor = result.documents[result.documents.length - 1].$id;
  }
  return all;
}

// Leert ein Bild-Feld überall dort, wo es auf Firebase zeigt.
async function resetCollection(collectionId, field) {
  console.log(`\n== ${collectionId}.${field} ==`);
  const docs = await fetchAll(collectionId);
  let reset = 0;
  for (const doc of docs) {
    if (!isFirebaseUrl(doc[field])) continue;
    console.log(`RESET ${collectionId}/${doc.$id} (${field})`);
    if (!DRY_RUN) {
      await db.updateDocument(DB_ID, collectionId, doc.$id, { [field]: null });
    }
    reset++;
  }
  console.log(`   ${docs.length} geprüft, ${reset} zurückgesetzt.`);
  return reset;
}

async function main() {
  if (DRY_RUN) console.log('=== DRY RUN — keine Änderungen ===');

  const users = await resetCollection('users', 'photoUrl');
  const convs = await resetCollection('conversations', 'imageUrl');

  console.log(`\n✅ ${DRY_RUN ? 'Dry-run' : 'Reset'} abgeschlossen.`);
  console.log(`   users.photoUrl zurückgesetzt:        ${users}`);
  console.log(`   conversations.imageUrl zurückgesetzt: ${convs}`);
  if (DRY_RUN) {
    console.log(`\nZum Ausführen: node reset-firebase-image-urls.js --delete --confirm=${process.env.APPWRITE_PROJECT_ID}`);
  }
}

main().catch(console.error);
