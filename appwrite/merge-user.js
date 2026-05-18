/**
 * Überträgt alle Daten von einem alten Appwrite-UID auf einen neuen UID.
 * Anwendungsfall: Firebase-migrierter Account → Google-OAuth-Account zusammenführen.
 *
 * Usage:
 *   node merge-user.js <OLD_UID> <NEW_UID>
 *
 * Beispiel:
 *   node merge-user.js fFXl5XPL2GMadraFUqZRrUCeX6N2 6a0a260ef1ad6e578bf7
 *
 * Was passiert:
 *   1. users/{newUid} erhält die Daten aus users/{oldUid} (displayName, memberships, etc.)
 *   2. Alle members/{orgId}_{oldUid} → members/{orgId}_{newUid}
 *   3. organizations.memberUids: oldUid → newUid
 *   4. conversations.participantUids / guardianUids / canApproveUids: oldUid → newUid
 *   5. Alter Appwrite-Auth-Account wird gelöscht
 *
 * Erforderliche Umgebungsvariablen (.env):
 *   APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY
 */

import { config } from 'dotenv';
import { Client, Databases, Users, Query } from 'node-appwrite';

config();

const OLD_UID = process.argv[2];
const NEW_UID = process.argv[3];

if (!OLD_UID || !NEW_UID) {
  console.error('Usage: node merge-user.js <OLD_UID> <NEW_UID>');
  process.exit(1);
}
if (OLD_UID === NEW_UID) {
  console.error('OLD_UID und NEW_UID sind identisch – nichts zu tun.');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db    = new Databases(client);
const users = new Users(client);

const DB_ID = 'guardian';

/** Liest alle Dokumente aus einer Collection (paginiert). */
async function listAll(colId, queries = []) {
  const docs = [];
  let cursor = null;
  while (true) {
    const q = [...queries, Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const res = await db.listDocuments(DB_ID, colId, q);
    docs.push(...res.documents);
    if (res.documents.length < 100) break;
    cursor = res.documents[res.documents.length - 1].$id;
  }
  return docs;
}

/** Ersetzt oldUid durch newUid in einem Array-Feld eines Dokuments. */
function replaceInArray(arr, oldVal, newVal) {
  if (!Array.isArray(arr)) return arr;
  return arr.map((v) => (v === oldVal ? newVal : v));
}

async function main() {
  console.log(`\n🔄 Merge: ${OLD_UID} → ${NEW_UID}\n`);

  // ── 1. users-Dokument kopieren ─────────────────────────────────────────────
  console.log('── 1. users-Dokument ──');
  let oldUserDoc;
  try {
    oldUserDoc = await db.getDocument(DB_ID, 'users', OLD_UID);
  } catch (e) {
    console.error(`  ✗ users/${OLD_UID} nicht gefunden: ${e.message}`);
    process.exit(1);
  }

  // Systeminterne Felder entfernen
  const { $id, $collectionId, $databaseId, $createdAt, $updatedAt, $permissions, ...userData } = oldUserDoc;

  try {
    await db.updateDocument(DB_ID, 'users', NEW_UID, userData);
    console.log(`  ✓ users/${NEW_UID} aktualisiert`);
  } catch (e) {
    if (e.code === 404) {
      // Neues Dokument anlegen falls noch nicht vorhanden
      await db.createDocument(DB_ID, 'users', NEW_UID, userData);
      console.log(`  ✓ users/${NEW_UID} erstellt`);
    } else {
      throw e;
    }
  }

  // ── 2. members-Dokumente umschreiben ───────────────────────────────────────
  console.log('\n── 2. members ──');
  const memberDocs = await listAll('members', [Query.equal('uid', OLD_UID)]);
  console.log(`  ${memberDocs.length} Mitgliedschaften gefunden`);

  for (const doc of memberDocs) {
    const orgId = doc.orgId;
    const oldMemberId = `${orgId}_${OLD_UID}`;
    const newMemberId = `${orgId}_${NEW_UID}`;

    const { $id, $collectionId, $databaseId, $createdAt, $updatedAt, $permissions, ...memberData } = doc;
    const newData = { ...memberData, uid: NEW_UID };

    try {
      await db.createDocument(DB_ID, 'members', newMemberId, newData);
      console.log(`  ✓ ${newMemberId} erstellt`);
    } catch (e) {
      if (e.code === 409) {
        await db.updateDocument(DB_ID, 'members', newMemberId, newData);
        console.log(`  ~ ${newMemberId} aktualisiert`);
      } else throw e;
    }

    // Altes Member-Dokument löschen
    try {
      await db.deleteDocument(DB_ID, 'members', oldMemberId);
      console.log(`  ✗ ${oldMemberId} gelöscht`);
    } catch (_) {}
  }

  // ── 3. organizations.memberUids aktualisieren ──────────────────────────────
  console.log('\n── 3. organizations ──');
  const orgs = await listAll('organizations', [Query.contains('memberUids', OLD_UID)]);
  console.log(`  ${orgs.length} Organisationen betroffen`);

  for (const org of orgs) {
    const newMemberUids = replaceInArray(org.memberUids, OLD_UID, NEW_UID);
    await db.updateDocument(DB_ID, 'organizations', org.$id, { memberUids: newMemberUids });
    console.log(`  ✓ org ${org.$id}: memberUids aktualisiert`);
  }

  // ── 4. conversations aktualisieren ────────────────────────────────────────
  console.log('\n── 4. conversations ──');
  let convCount = 0;

  // participantUids
  const convParticipant = await listAll('conversations', [Query.contains('participantUids', OLD_UID)]);
  for (const conv of convParticipant) {
    const updates = {
      participantUids: replaceInArray(conv.participantUids, OLD_UID, NEW_UID),
    };
    if (conv.guardianUids?.includes(OLD_UID))
      updates.guardianUids = replaceInArray(conv.guardianUids, OLD_UID, NEW_UID);
    if (conv.canApproveUids?.includes(OLD_UID))
      updates.canApproveUids = replaceInArray(conv.canApproveUids, OLD_UID, NEW_UID);
    if (conv.requestedBy === OLD_UID) updates.requestedBy = NEW_UID;
    if (conv.orgAdminUid === OLD_UID)  updates.orgAdminUid = NEW_UID;
    await db.updateDocument(DB_ID, 'conversations', conv.$id, updates);
    convCount++;
  }

  // guardianUids (die noch nicht in participantUids waren)
  const convGuardian = await listAll('conversations', [Query.contains('guardianUids', OLD_UID)]);
  for (const conv of convGuardian) {
    if (convParticipant.find((c) => c.$id === conv.$id)) continue; // bereits verarbeitet
    await db.updateDocument(DB_ID, 'conversations', conv.$id, {
      guardianUids: replaceInArray(conv.guardianUids, OLD_UID, NEW_UID),
    });
    convCount++;
  }

  console.log(`  ✓ ${convCount} Conversations aktualisiert`);

  // ── 5. users-Dokument des alten UIDs löschen ──────────────────────────────
  console.log('\n── 5. Altes users-Dokument löschen ──');
  try {
    await db.deleteDocument(DB_ID, 'users', OLD_UID);
    console.log(`  ✓ users/${OLD_UID} gelöscht`);
  } catch (e) {
    console.warn(`  ~ users/${OLD_UID} konnte nicht gelöscht werden: ${e.message}`);
  }

  // ── 6. Alten Appwrite-Auth-Account löschen ─────────────────────────────────
  console.log('\n── 6. Alten Auth-Account löschen ──');
  try {
    await users.delete(OLD_UID);
    console.log(`  ✓ Auth-Account ${OLD_UID} gelöscht`);
  } catch (e) {
    console.warn(`  ~ Auth-Account konnte nicht gelöscht werden: ${e.message}`);
    console.warn('    Bitte manuell in der Appwrite Console löschen.');
  }

  console.log('\n✅ Merge abgeschlossen.');
  console.log(`   Nutzer kann sich jetzt mit Google (UID: ${NEW_UID}) anmelden und sieht alle Daten.`);
}

main().catch((e) => {
  console.error('\n✗ Fehler:', e.message ?? e);
  process.exit(1);
});
