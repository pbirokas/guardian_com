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
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
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
    if (candidates.length > 1) {
      error(`Multiple old accounts for ${email}: ${candidates.map((d) => d.$id).join(', ')}`);
      return res.json({ merged: false, reason: 'ambiguous_old_account' }, 409);
    }
    oldDoc = candidates[0];
  } catch (e) {
    error(`listDocuments failed: ${e.message}`);
    return res.json({ merged: false, reason: 'db_error' }, 500);
  }

  const oldUid = oldDoc.$id;

  // ── Auth-seitige E-Mail des alten Accounts verifizieren ───────────────────
  try {
    const oldAuthUser = await users.get(oldUid);
    if (oldAuthUser.email?.toLowerCase() !== email) {
      error(`Auth email mismatch for ${oldUid}: ${oldAuthUser.email} !== ${email}`);
      return res.json({ merged: false, reason: 'email_mismatch' }, 403);
    }
  } catch (e) {
    error(`users.get(${oldUid}) failed: ${e.message}`);
    return res.json({ merged: false, reason: 'old_user_not_found' }, 404);
  }
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

  // ── 4. verifiedParentUids / verifiedChildUids in anderen User-Docs ───────
  try {
    const seenUserIds = new Set();

    async function updateUserVerified(queryFn) {
      const userDocs = await listAll('users', [queryFn]);
      for (const doc of userDocs) {
        if (seenUserIds.has(doc.$id)) continue;
        seenUserIds.add(doc.$id);
        const updates = {};
        if (doc.verifiedParentUids?.includes(oldUid))
          updates.verifiedParentUids = replaceUid(doc.verifiedParentUids, oldUid, newUid);
        if (doc.verifiedChildUids?.includes(oldUid))
          updates.verifiedChildUids = replaceUid(doc.verifiedChildUids, oldUid, newUid);
        if (Object.keys(updates).length)
          await db.updateDocument(DB_ID, 'users', doc.$id, updates);
      }
    }

    await updateUserVerified(Query.contains('verifiedParentUids', oldUid));
    await updateUserVerified(Query.contains('verifiedChildUids', oldUid));
    log(`${seenUserIds.size} user docs updated (verified links)`);
  } catch (e) {
    error(`verified links update failed: ${e.message}`);
    return res.json({ merged: false, reason: 'verified_links_failed' }, 500);
  }

  // ── 5. conversations aktualisieren ────────────────────────────────────────
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

  // ── 6. Alten Account aufräumen ────────────────────────────────────────────
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
