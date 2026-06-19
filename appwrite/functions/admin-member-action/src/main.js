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

const { Client, Databases, Query, Permission, Role } = require('node-appwrite');

const DB_ID   = 'guardian';
const COL_ORGS    = 'organizations';
const COL_MEMBERS = 'members';
const COL_USERS   = 'users';

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

  const db = new Databases(client);

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
        // Alle Member seitenweise laden und entfernen.
        // Kein Query.offset nötig: nach dem Löschen liefert die nächste
        // Abfrage automatisch die verbleibenden Dokumente.
        while (true) {
          const membersResult = await db.listDocuments(DB_ID, COL_MEMBERS, [
            Query.equal('orgId', orgId),
            Query.limit(100),
          ]);
          if (membersResult.documents.length === 0) break;

          await Promise.all(membersResult.documents.map(async (doc) => {
            await db.deleteDocument(DB_ID, COL_MEMBERS, doc.$id);
            await removeMembership(db, doc.uid, orgId, doc.role, log);
          }));

          if (membersResult.documents.length < 100) break;
        }

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
