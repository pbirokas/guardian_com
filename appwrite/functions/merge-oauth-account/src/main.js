/**
 * merge-oauth-account
 *
 * Wird nach erfolgreichem Google-OAuth-Login aufgerufen.
 * Sucht nach einem bereits migrierten Account mit derselben E-Mail-Adresse
 * und überträgt alle Daten auf den neuen Google-OAuth-Account.
 *
 * Aufruf aus Flutter: _functions.createExecution(functionId: 'merge-oauth-account')
 */

const { Client, Databases, Users, Query, Permission, Role } = require('node-appwrite');

const DB_ID = 'guardian';

module.exports = async ({ req, res, log, error }) => {
  const newUid = req.headers['x-appwrite-user-id'];
  if (!newUid) return res.json({ merged: false, reason: 'unauthenticated' }, 401);

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db    = new Databases(client);
  const users = new Users(client);

  // ── E-Mail des eingeloggten Nutzers ermitteln ──────────────────────────────
  let email;
  try {
    const user = await users.get(newUid);
    email = user.email?.toLowerCase();
  } catch (e) {
    error(`users.get(${newUid}) failed: ${e.message}`);
    return res.json({ merged: false, reason: 'user_not_found' }, 404);
  }

  if (!email) return res.json({ merged: false, reason: 'no_email' });

  // ── Vorhandenes users-Dokument mit gleicher E-Mail finden ─────────────────
  let oldDoc;
  try {
    const result = await db.listDocuments(DB_ID, 'users', [
      Query.equal('email', email),
      Query.limit(5),
    ]);
    // Eigenes (neues) Dokument herausfiltern
    const candidates = result.documents.filter((d) => d.$id !== newUid);
    if (candidates.length === 0) {
      log(`No old account found for ${email} — nothing to merge.`);
      return res.json({ merged: false, reason: 'no_old_account' });
    }
    oldDoc = candidates[0];
  } catch (e) {
    error(`listDocuments failed: ${e.message}`);
    return res.json({ merged: false, reason: 'db_error' }, 500);
  }

  const oldUid = oldDoc.$id;
  log(`Merging ${oldUid} → ${newUid} (email: ${email})`);

  // ── Hilfsfunktionen ────────────────────────────────────────────────────────

  function stripMeta({ $id, $collectionId, $databaseId, $createdAt, $updatedAt, $permissions, ...data }) {
    return data;
  }

  function replaceUid(arr, from, to) {
    if (!Array.isArray(arr)) return arr;
    return arr.map((v) => (v === from ? to : v));
  }

  async function listAll(colId, queries) {
    const docs = [];
    let cursor = null;
    while (true) {
      const q = [...queries, Query.limit(100)];
      if (cursor) q.push(Query.cursorAfter(cursor));
      const r = await db.listDocuments(DB_ID, colId, q);
      docs.push(...r.documents);
      if (r.documents.length < 100) break;
      cursor = r.documents[r.documents.length - 1].$id;
    }
    return docs;
  }

  // ── 1. users-Dokument: alte Daten auf neuen Account übertragen ────────────
  try {
    const data = stripMeta(oldDoc);
    // Google-Profildaten (Name/Foto) behalten falls im neuen Account vorhanden
    let newDoc;
    try { newDoc = await db.getDocument(DB_ID, 'users', newUid); } catch (_) {}
    const merged = {
      ...data,
      // Neuere Felder vom Google-Account bevorzugen
      displayName: newDoc?.displayName || data.displayName,
      photoUrl:    newDoc?.photoUrl    || data.photoUrl,
    };
    const userPerms = [
      Permission.read(Role.user(newUid)),
      Permission.update(Role.user(newUid)),
      Permission.delete(Role.user(newUid)),
    ];
    try {
      await db.updateDocument(DB_ID, 'users', newUid, merged, userPerms);
    } catch (_) {
      await db.createDocument(DB_ID, 'users', newUid, merged, userPerms);
    }
    log('users doc merged');
  } catch (e) {
    error(`users merge failed: ${e.message}`);
    return res.json({ merged: false, reason: 'users_merge_failed' }, 500);
  }

  // ── 2. members-Dokumente verschieben ──────────────────────────────────────
  try {
    const memberDocs = await listAll('members', [Query.equal('uid', oldUid)]);
    for (const doc of memberDocs) {
      const orgId      = doc.orgId;
      const newMemId   = `${orgId}_${newUid}`;
      const memberData = { ...stripMeta(doc), uid: newUid };
      try {
        await db.createDocument(DB_ID, 'members', newMemId, memberData);
      } catch (e) {
        if (e.code === 409) await db.updateDocument(DB_ID, 'members', newMemId, memberData);
        else throw e;
      }
      try { await db.deleteDocument(DB_ID, 'members', `${orgId}_${oldUid}`); } catch (_) {}
    }
    log(`${memberDocs.length} member docs migrated`);
  } catch (e) {
    error(`members merge failed: ${e.message}`);
  }

  // ── 3. organizations.memberUids aktualisieren ─────────────────────────────
  try {
    const orgs = await listAll('organizations', [Query.contains('memberUids', oldUid)]);
    for (const org of orgs) {
      await db.updateDocument(DB_ID, 'organizations', org.$id, {
        memberUids: replaceUid(org.memberUids, oldUid, newUid),
      });
    }
    log(`${orgs.length} orgs updated`);
  } catch (e) {
    error(`orgs update failed: ${e.message}`);
  }

  // ── 4. conversations aktualisieren ────────────────────────────────────────
  try {
    const seenIds = new Set();

    async function updateConvs(queryFn) {
      const convs = await listAll('conversations', [queryFn]);
      for (const conv of convs) {
        if (seenIds.has(conv.$id)) continue;
        seenIds.add(conv.$id);
        const updates = {};
        if (conv.participantUids?.includes(oldUid))
          updates.participantUids = replaceUid(conv.participantUids, oldUid, newUid);
        if (conv.guardianUids?.includes(oldUid))
          updates.guardianUids = replaceUid(conv.guardianUids, oldUid, newUid);
        if (conv.canApproveUids?.includes(oldUid))
          updates.canApproveUids = replaceUid(conv.canApproveUids, oldUid, newUid);
        if (conv.requestedBy === oldUid) updates.requestedBy = newUid;
        if (conv.orgAdminUid === oldUid)  updates.orgAdminUid = newUid;
        if (Object.keys(updates).length)
          await db.updateDocument(DB_ID, 'conversations', conv.$id, updates);
      }
    }

    await updateConvs(Query.contains('participantUids', oldUid));
    await updateConvs(Query.contains('guardianUids', oldUid));
    log(`${seenIds.size} conversations updated`);
  } catch (e) {
    error(`conversations update failed: ${e.message}`);
  }

  // ── 5. Alten Account aufräumen ────────────────────────────────────────────
  try {
    await db.deleteDocument(DB_ID, 'users', oldUid);
    log(`users/${oldUid} deleted`);
  } catch (_) {}

  try {
    await users.delete(oldUid);
    log(`auth user ${oldUid} deleted`);
  } catch (e) {
    error(`auth user delete failed (manual cleanup needed): ${e.message}`);
  }

  log(`Merge complete: ${oldUid} → ${newUid}`);
  return res.json({ merged: true, oldUid, newUid });
};
