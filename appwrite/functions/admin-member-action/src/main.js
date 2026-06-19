/**
 * admin-member-action — Cloud Function für alle privilegierten Mitglied-Operationen.
 *
 * Aktionen (body.action):
 *  - addMember      : Neues Mitglied direkt hinzufügen (Admin/Mod)
 *  - updateRole     : Rolle eines Mitglieds ändern (Admin/Mod)
 *  - transferAdmin  : Admin-Rolle übertragen (nur Admin)
 *  - approveChild   : Kind-Einladung bestätigen (Admin/Mod)
 *  - updateGuardians: Guardians eines Kindes aktualisieren (Admin/Mod)
 *  - removeMember   : Mitglied entfernen (Admin/Mod)
 *  - leaveOrg       : Organisation verlassen (eigener Aufruf)
 *
 * Sicherheit:
 *  - Caller wird über x-appwrite-user-id identifiziert (Appwrite setzt diesen Header)
 *  - Berechtigung wird serverseitig gegen den members-Doc des Callers geprüft
 *  - DB-Operationen laufen mit API-Key (umgeht collection-level Permissions)
 */

const { Client, Databases, Storage, Query, Permission, Role } = require('node-appwrite');

const DB_ID          = 'guardian';
const BUCKET_MEDIA   = '6a02e524000954c9f1de';
const COL_ORGS          = 'organizations';
const COL_MEMBERS       = 'members';
const COL_USERS         = 'users';
const COL_CONVS         = 'conversations';
const COL_MESSAGES      = 'chat_messages';
const COL_POLLS         = 'polls';
const COL_SCHEDULED     = 'scheduled_messages';
const COL_RECEIPTS      = 'read_receipts';
const COL_ANNOUNCEMENTS = 'announcements';
const COL_INVITATIONS   = 'invitations';
const COL_CONSENTS      = 'org_invite_consents';
const COL_AUDIT         = 'audit_log';
const COL_REPORTS       = 'reports';

module.exports = async ({ req, res, log, error }) => {
  const callerId = req.headers['x-appwrite-user-id'];
  if (!callerId) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const { action, orgId, targetUid, payload = {} } = body;
  if (!action || !orgId) return res.json({ error: 'action and orgId required' }, 400);

  const client = new Client()
    .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db      = new Databases(client);
  const storage = new Storage(client);

  // Caller-Mitglied laden
  const callerMemberId = `${orgId}_${callerId}`;
  let callerMember;
  try {
    callerMember = await db.getDocument(DB_ID, COL_MEMBERS, callerMemberId);
  } catch (_) {
    if (action === 'leaveOrg') {
      // Mitglied existiert vielleicht nicht mehr — kein Fehler
      return res.json({ ok: true, alreadyGone: true });
    }
    if (action === 'deleteOrg') {
      // Member-Doc des Admins könnte fehlen (Datenkonsistenz-Problem).
      // Fallback: Org laden und adminUid direkt prüfen.
      callerMember = null;
    } else {
      return res.json({ error: 'Not a member of this organization' }, 403);
    }
  }

  const callerRole  = callerMember?.role ?? null;
  const isAdmin     = callerRole === 'admin';
  const isAdminOrMod = isAdmin || callerRole === 'moderator';

  switch (action) {
    // ── addMember ────────────────────────────────────────────────────────────
    case 'addMember': {
      if (!isAdminOrMod) return res.json({ error: 'Forbidden' }, 403);
      const { memberData, isChild } = payload;
      if (!targetUid || !memberData) {
        return res.json({ error: 'targetUid and memberData required' }, 400);
      }
      const memberId = `${orgId}_${targetUid}`;

      // Bereits Mitglied?
      try {
        await db.getDocument(DB_ID, COL_MEMBERS, memberId);
        return res.json({ error: 'already_member' }, 409);
      } catch (e) {
        if ((e?.code ?? 0) !== 404) {
          error(`addMember getDocument error: ${e?.message}`);
          return res.json({ error: 'Internal server error' }, 500);
        }
      }

      try {
        await db.createDocument(DB_ID, COL_MEMBERS, memberId, memberData, [
          Permission.read(Role.users()),
          Permission.update(Role.user(targetUid)),
          Permission.delete(Role.user(targetUid)),
        ]);
      } catch (e) {
        if ((e?.code ?? 0) === 409) return res.json({ error: 'already_member' }, 409);
        error(`addMember createDocument error: ${e?.message}`);
        return res.json({ error: 'Internal server error' }, 500);
      }

      if (!isChild) {
        // org.memberUids aktualisieren
        const orgDoc = await db.getDocument(DB_ID, COL_ORGS, orgId);
        const memberUids = [...(orgDoc.memberUids ?? [])];
        if (!memberUids.includes(targetUid)) {
          memberUids.push(targetUid);
          await db.updateDocument(DB_ID, COL_ORGS, orgId, { memberUids });
        }
        // membershipsJson aktualisieren
        const role = memberData.role ?? 'member';
        await addMembership(db, targetUid, orgId, role, log);
      }

      return res.json({ ok: true });
    }

    // ── updateRole ───────────────────────────────────────────────────────────
    case 'updateRole': {
      if (!isAdminOrMod) return res.json({ error: 'Forbidden' }, 403);
      const { newRole } = payload;
      if (!targetUid || !newRole) {
        return res.json({ error: 'targetUid and newRole required' }, 400);
      }
      const validRoles = ['admin', 'moderator', 'member', 'child'];
      if (!validRoles.includes(newRole)) return res.json({ error: 'Invalid role' }, 400);
      if (!isAdmin && (newRole === 'admin' || newRole === 'moderator')) {
        return res.json({ error: 'Only admin can grant admin/moderator role' }, 403);
      }
      if (targetUid === callerId) return res.json({ error: 'Cannot change own role' }, 400);

      const memberId = `${orgId}_${targetUid}`;
      let memberDoc;
      try {
        memberDoc = await db.getDocument(DB_ID, COL_MEMBERS, memberId);
      } catch (_) {
        return res.json({ error: 'Member not found' }, 404);
      }
      const oldRole = memberDoc.role;
      if (oldRole === newRole) return res.json({ ok: true }); // idempotent

      await db.updateDocument(DB_ID, COL_MEMBERS, memberId, { role: newRole });

      await removeMembership(db, targetUid, orgId, oldRole, log);
      await addMembership(db, targetUid, orgId, newRole, log);

      log(`updateRole: ${targetUid} ${oldRole} → ${newRole} in ${orgId} by ${callerId}`);
      return res.json({ ok: true, oldRole });
    }

    // ── transferAdmin ────────────────────────────────────────────────────────
    case 'transferAdmin': {
      if (!isAdmin) return res.json({ error: 'Only admin can transfer admin role' }, 403);
      if (!targetUid) return res.json({ error: 'targetUid required' }, 400);
      if (targetUid === callerId) return res.json({ error: 'Cannot transfer to yourself' }, 400);

      const newAdminMemberId = `${orgId}_${targetUid}`;
      let newAdminDoc;
      try {
        newAdminDoc = await db.getDocument(DB_ID, COL_MEMBERS, newAdminMemberId);
      } catch (_) {
        return res.json({ error: 'Target member not found' }, 404);
      }
      const oldTargetRole = newAdminDoc.role;

      // Rollen tauschen
      await db.updateDocument(DB_ID, COL_MEMBERS, callerMemberId, { role: 'member' });
      await db.updateDocument(DB_ID, COL_MEMBERS, newAdminMemberId, { role: 'admin' });
      await db.updateDocument(DB_ID, COL_ORGS, orgId, { adminUid: targetUid });

      // membershipsJson beider Nutzer aktualisieren
      await removeMembership(db, callerId, orgId, 'admin', log);
      await addMembership(db, callerId, orgId, 'member', log);
      await removeMembership(db, targetUid, orgId, oldTargetRole, log);
      await addMembership(db, targetUid, orgId, 'admin', log);

      log(`transferAdmin: ${callerId} → ${targetUid} in ${orgId}`);
      return res.json({ ok: true });
    }

    // ── approveChild ─────────────────────────────────────────────────────────
    case 'approveChild': {
      if (!isAdminOrMod) return res.json({ error: 'Forbidden' }, 403);
      if (!targetUid) return res.json({ error: 'targetUid required' }, 400);

      const memberId = `${orgId}_${targetUid}`;
      await db.updateDocument(DB_ID, COL_MEMBERS, memberId, { status: 'active' });

      const orgDoc = await db.getDocument(DB_ID, COL_ORGS, orgId);
      const memberUids = [...(orgDoc.memberUids ?? [])];
      if (!memberUids.includes(targetUid)) {
        memberUids.push(targetUid);
        await db.updateDocument(DB_ID, COL_ORGS, orgId, { memberUids });
      }

      log(`approveChild: ${targetUid} approved in ${orgId} by ${callerId}`);
      return res.json({ ok: true });
    }

    // ── updateGuardians ──────────────────────────────────────────────────────
    case 'updateGuardians': {
      if (!isAdminOrMod) return res.json({ error: 'Forbidden' }, 403);
      if (!targetUid) return res.json({ error: 'targetUid required' }, 400);
      const { guardianUids } = payload;
      if (!Array.isArray(guardianUids)) {
        return res.json({ error: 'guardianUids array required' }, 400);
      }

      const memberId = `${orgId}_${targetUid}`;
      await db.updateDocument(DB_ID, COL_MEMBERS, memberId, { guardianUids });

      log(`updateGuardians: ${targetUid} in ${orgId} by ${callerId}`);
      return res.json({ ok: true });
    }

    // ── removeMember ─────────────────────────────────────────────────────────
    case 'removeMember': {
      if (!isAdminOrMod) return res.json({ error: 'Forbidden' }, 403);
      if (!targetUid) return res.json({ error: 'targetUid required' }, 400);
      if (targetUid === callerId) return res.json({ error: 'Use leaveOrg to remove yourself' }, 400);

      const memberId = `${orgId}_${targetUid}`;
      let memberDoc;
      try {
        memberDoc = await db.getDocument(DB_ID, COL_MEMBERS, memberId);
      } catch (_) {
        return res.json({ error: 'Member not found' }, 404);
      }
      const memberRole = memberDoc.role;

      // Mod kann keinen Admin entfernen
      if (!isAdmin && memberRole === 'admin') {
        return res.json({ error: 'Forbidden: moderator cannot remove admin' }, 403);
      }

      await db.deleteDocument(DB_ID, COL_MEMBERS, memberId);

      // org.memberUids aktualisieren
      try {
        const orgDoc = await db.getDocument(DB_ID, COL_ORGS, orgId);
        const memberUids = (orgDoc.memberUids ?? []).filter(u => u !== targetUid);
        await db.updateDocument(DB_ID, COL_ORGS, orgId, { memberUids });
      } catch (e) {
        error(`removeMember: failed to update memberUids: ${e?.message}`);
      }

      // membershipsJson aktualisieren
      await removeMembership(db, targetUid, orgId, memberRole, log);

      log(`removeMember: ${targetUid} removed from ${orgId} by ${callerId}`);
      return res.json({ ok: true, removedRole: memberRole });
    }

    // ── leaveOrg ─────────────────────────────────────────────────────────────
    case 'leaveOrg': {
      if (callerRole === 'admin') {
        return res.json({
          error: 'Als Admin kannst du die Organisation nicht verlassen. '
               + 'Übertrage zuerst die Admin-Rolle an ein anderes Mitglied.',
        }, 403);
      }

      await db.deleteDocument(DB_ID, COL_MEMBERS, callerMemberId);

      // org.memberUids aktualisieren
      try {
        const orgDoc = await db.getDocument(DB_ID, COL_ORGS, orgId);
        const memberUids = (orgDoc.memberUids ?? []).filter(u => u !== callerId);
        await db.updateDocument(DB_ID, COL_ORGS, orgId, { memberUids });
      } catch (e) {
        error(`leaveOrg: failed to update memberUids: ${e?.message}`);
      }

      // membershipsJson aktualisieren
      await removeMembership(db, callerId, orgId, callerRole, log);

      log(`leaveOrg: ${callerId} left ${orgId} (role=${callerRole})`);
      return res.json({ ok: true });
    }

    // ── deleteOrg ────────────────────────────────────────────────────────────
    case 'deleteOrg': {
      // callerMember kann null sein wenn der Admin-Member-Doc fehlt.
      // Dann direkt gegen org.adminUid prüfen.
      let isOrgAdmin = callerMember ? callerMember.role === 'admin' : false;
      if (!isOrgAdmin) {
        try {
          const orgDoc = await db.getDocument(DB_ID, COL_ORGS, orgId);
          isOrgAdmin = orgDoc.adminUid === callerId;
        } catch (e) {
          return res.json({ error: 'Organization not found' }, 404);
        }
      }
      if (!isOrgAdmin) return res.json({ error: 'Only admin can delete the organization' }, 403);

      try {
        // Status markieren, damit das Cleanup-Script halbgelöschte Orgs
        // erkennt und bei erneutem Lauf abräumt (Idempotenz bei Absturz).
        await db.updateDocument(DB_ID, COL_ORGS, orgId, { deletionStatus: 'deleting' });

        // 1. Mitglieder entfernen + Memberships bereinigen
        while (true) {
          const { documents } = await db.listDocuments(DB_ID, COL_MEMBERS, [
            Query.equal('orgId', orgId), Query.limit(100),
          ]);
          if (documents.length === 0) break;
          await Promise.all(documents.map((doc) =>
            Promise.all([
              db.deleteDocument(DB_ID, COL_MEMBERS, doc.$id),
              removeMembership(db, doc.uid, orgId, doc.role, log),
            ])
          ));
          if (documents.length < 100) break;
        }

        // 2. Conversations und ihre Sub-Collections löschen (Datenschutz: Nachrichten
        //    haben Permission.read(Role.users()) — ohne Löschung wären sie für alle
        //    angemeldeten Nutzer weiter lesbar auch nach Org-Löschung).
        while (true) {
          const { documents: convs } = await db.listDocuments(DB_ID, COL_CONVS, [
            Query.equal('orgId', orgId), Query.limit(20),
          ]);
          if (convs.length === 0) break;
          for (const conv of convs) {
            // Sub-Collections parallel löschen, dann erst den Conv-Doc
            await Promise.all([
              deleteMessageBatch(db, storage, [Query.equal('convId', conv.$id)]),
              deleteBatch(db, COL_POLLS,     [Query.equal('convId', conv.$id)]),
              deleteBatch(db, COL_SCHEDULED, [Query.equal('convId', conv.$id)]),
              deleteBatch(db, COL_RECEIPTS,  [Query.equal('convId', conv.$id)]),
            ]);
            await db.deleteDocument(DB_ID, COL_CONVS, conv.$id);
          }
          if (convs.length < 20) break;
        }

        // 3. Org-weite Collections parallel löschen
        await Promise.all([
          deleteBatch(db, COL_ANNOUNCEMENTS, [Query.equal('orgId', orgId)]),
          deleteBatch(db, COL_INVITATIONS,   [Query.equal('orgId', orgId)]),
          deleteBatch(db, COL_CONSENTS,      [Query.equal('orgId', orgId)]),
          deleteBatch(db, COL_AUDIT,         [Query.equal('orgId', orgId)]),
          deleteBatch(db, COL_REPORTS,       [Query.equal('orgId', orgId)]),
        ]);

        await db.deleteDocument(DB_ID, COL_ORGS, orgId);
      } catch (e) {
        error(`deleteOrg failed: ${e?.message}`);
        return res.json({ error: 'Internal server error' }, 500);
      }

      log(`deleteOrg: ${orgId} deleted by ${callerId}`);
      return res.json({ ok: true });
    }

    default:
      return res.json({ error: `Unknown action: ${action}` }, 400);
  }
};

// ── Hilfsfunktionen ────────────────────────────────────────────────────────────

async function addMembership(db, uid, orgId, role, log) {
  try {
    const userDoc = await db.getDocument(DB_ID, COL_USERS, uid);
    const memberships = parseMembershipsJson(userDoc.membershipsJson);
    if (!memberships.some(m => m.orgId === orgId)) {
      memberships.push({ orgId, role });
      await db.updateDocument(DB_ID, COL_USERS, uid, {
        membershipsJson: JSON.stringify(memberships),
      });
    }
  } catch (e) {
    if (log) log(`addMembership(${uid}, ${orgId}, ${role}) failed: ${e?.message}`);
  }
}

async function removeMembership(db, uid, orgId, role, log) {
  try {
    const userDoc = await db.getDocument(DB_ID, COL_USERS, uid);
    const memberships = parseMembershipsJson(userDoc.membershipsJson);
    const updated = memberships.filter(m => !(m.orgId === orgId && m.role === role));
    await db.updateDocument(DB_ID, COL_USERS, uid, {
      membershipsJson: JSON.stringify(updated),
    });
  } catch (e) {
    if (log) log(`removeMembership(${uid}, ${orgId}, ${role}) failed: ${e?.message}`);
  }
}

function parseMembershipsJson(raw) {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

async function deleteBatch(db, col, queries) {
  while (true) {
    const { documents } = await db.listDocuments(DB_ID, col, [...queries, Query.limit(100)]);
    if (documents.length === 0) break;
    await Promise.all(documents.map(d => db.deleteDocument(DB_ID, col, d.$id)));
    if (documents.length < 100) break;
  }
}

// Wie deleteBatch, löscht zusätzlich alle Storage-Dateien (Bilder, Audio,
// Dateianhänge) die in den Message-Dokumenten referenziert sind.
async function deleteMessageBatch(db, storage, queries) {
  while (true) {
    const { documents } = await db.listDocuments(DB_ID, COL_MESSAGES, [...queries, Query.limit(100)]);
    if (documents.length === 0) break;
    await Promise.all(documents.map(async (msg) => {
      // Storage-Dateien parallel löschen (Fehler ignorieren — Datei kann
      // bereits weg sein oder nie existiert haben)
      const fileIds = [msg.imageUrl, msg.audioUrl, msg.fileUrl]
        .filter(Boolean)
        .map(extractStorageFileId)
        .filter(Boolean);
      await Promise.allSettled(fileIds.map(id => storage.deleteFile(BUCKET_MEDIA, id)));
      await db.deleteDocument(DB_ID, COL_MESSAGES, msg.$id);
    }));
    if (documents.length < 100) break;
  }
}

// Extrahiert die Appwrite-File-ID aus einer Storage-View-URL.
// Format: .../storage/buckets/<bucketId>/files/<fileId>/view?...
function extractStorageFileId(url) {
  const m = url && url.match(/\/files\/([^/?]+)\/view/);
  return m ? m[1] : null;
}
