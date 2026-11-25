/**
 * Migration: Read-Receipts für die Lesestatus-Häkchen im Chat-Team lesbar machen.
 *
 * Soll-ACL je Receipt (deckungsgleich mit receiptPerms in
 * functions/mark-as-read/src/main.js):
 *   - read user(uid)                       — immer (Eigentümer)
 *   - read team(convId)                    — nur wenn uid in conv.participantUids
 *   - KEIN update/delete für den Client    — schreiben darf nur mark-as-read
 *
 * Lesezeiten von Guardians und Aufsicht (keine Teilnehmer) bleiben privat.
 * Receipts, deren Conversation nicht mehr existiert, werden nur gezählt
 * (Aufräumen: cleanup-orphaned-data.js).
 *
 * Reihenfolge im Rollout:
 *   1. mark-as-read deployen (setzt die neue ACL bei jedem Gelesen-Markieren).
 *   2. Dieses Skript ausführen (Altbestand).
 *   Die App-Version mit den neuen Häkchen funktioniert erst nach Schritt 1+2
 *   vollständig; alte Apps sind nicht betroffen (sie lesen nur eigene Receipts).
 *
 * Rollback: node share-read-receipts.js --rollback --confirm=<projectId>
 *   setzt alle Receipts zurück auf read/update/delete user(uid) (Stand vor
 *   dieser Migration). Vorher mark-as-read auf den alten Stand deployen.
 *
 * Idempotent & wiederholbar. Standardmäßig Dry-Run.
 *
 * Nutzung:
 *   node share-read-receipts.js                       (Dry-Run, nur zählen)
 *   node share-read-receipts.js --confirm=<projectId> (führt die Migration aus)
 */

import { config } from 'dotenv';
import { Client, Databases, Permission, Role, Query } from 'node-appwrite';

config();

const DB_ID = 'guardian';
const COL_CONVERSATIONS = 'conversations';
const COL_RECEIPTS = 'read_receipts';

const projectId = process.env.APPWRITE_PROJECT_ID;
const confirmArg = process.argv.find((a) => a.startsWith('--confirm='));
const CONFIRMED = confirmArg && confirmArg.split('=')[1] === projectId;
const DRY = !CONFIRMED;
const ROLLBACK = process.argv.includes('--rollback');

if (confirmArg && !CONFIRMED) {
  console.error(
    `✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`
  );
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);

function receiptPerms(convId, uid, isParticipant) {
  const perms = [Permission.read(Role.user(uid))];
  if (isParticipant) perms.push(Permission.read(Role.team(convId)));
  return perms;
}

function legacyPerms(uid) {
  const u = Role.user(uid);
  return [Permission.read(u), Permission.update(u), Permission.delete(u)];
}

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

const convCache = new Map();
async function participantsOf(convId) {
  if (convCache.has(convId)) return convCache.get(convId);
  let participants = null;
  try {
    const conv = await db.getDocument(DB_ID, COL_CONVERSATIONS, convId);
    participants = conv.participantUids ?? [];
  } catch (e) {
    if (e.code !== 404) throw e;
  }
  convCache.set(convId, participants);
  return participants;
}

async function main() {
  console.log('=== share-read-receipts ===');
  console.log(`Projekt: ${projectId}`);
  console.log(`Modus:   ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'}${ROLLBACK ? ' · ROLLBACK' : ''}\n`);

  let total = 0;
  let shared = 0;
  let priv = 0;
  let orphaned = 0;
  let changed = 0;
  let failed = 0;

  let cursor = null;
  do {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, COL_RECEIPTS, q);
    for (const rr of result.documents) {
      total++;
      if (!rr.uid || !rr.convId) {
        console.error(`  ✗ Receipt ${rr.$id} ohne uid/convId — übersprungen`);
        failed++;
        continue;
      }
      let desired;
      if (ROLLBACK) {
        desired = legacyPerms(rr.uid);
      } else {
        const participants = await participantsOf(rr.convId);
        if (participants === null) {
          orphaned++;
          continue;
        }
        const isParticipant = participants.includes(rr.uid);
        isParticipant ? shared++ : priv++;
        desired = receiptPerms(rr.convId, rr.uid, isParticipant);
      }
      if (samePerms(rr.$permissions, desired)) continue;
      changed++;
      if (DRY) continue;
      try {
        await db.updateDocument(DB_ID, COL_RECEIPTS, rr.$id, {}, desired);
      } catch (e) {
        failed++;
        console.error(`  ✗ Receipt-ACL ${rr.$id}: ${e.message}`);
      }
    }
    cursor = result.documents.length === 100 ? result.documents.at(-1).$id : null;
  } while (cursor);

  console.log(`Receipts gesamt:               ${total}`);
  if (!ROLLBACK) {
    console.log(`  Teilnehmer (team-lesbar):    ${shared}`);
    console.log(`  Guardian/Aufsicht (privat):  ${priv}`);
    console.log(`  ohne Conversation (ignoriert): ${orphaned}`);
  }
  console.log(`ACL ${DRY ? 'würde geändert' : 'geändert'}:        ${changed}`);
  if (failed) console.log(`Fehler:                        ${failed}`);
  if (DRY) console.log(`\nDry-Run. Ausführen mit --confirm=${projectId}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
