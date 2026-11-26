const { Client, Databases, Users, Query, Permission, Role } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_ORGANIZATIONS = 'organizations';
const COL_MEMBERS = 'members';
const COL_INVITATIONS = 'invitations';

// Wer hat das Einladungs-Doc angelegt? Ein Client kann beim Anlegen nur
// Rechte für sich selbst vergeben (`user:<self>`); `inviteByEmail` (API-Key)
// setzt read/update/delete für den Einladenden. Das Feld `invitedByUid` im
// Doc ist dagegen frei wählbar und zählt allein NICHT als Nachweis.
// Nutzer mit Schreibrechten (update/delete) = Ersteller; reine Leserechte
// vergibt inviteByEmail zusätzlich an die Guardians.
function aclUsers(perms, kinds = ['update', 'delete', 'write']) {
  const uids = new Set();
  for (const p of perms ?? []) {
    const m = /^(\w+)\("user:([^"/]+)"\)$/.exec(p);
    if (m && kinds.includes(m[1])) uids.add(m[2]);
  }
  return [...uids];
}

async function activeMember(db, orgId, uid) {
  if (!uid) return null;
  try {
    const m = await db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${uid}`);
    if (m.uid !== uid || (m.status ?? 'active') !== 'active') return null;
    return m;
  } catch (_) {
    return null;
  }
}

/**
 * Prüft eine Einladung und liefert die zu vergebende Rolle + Guardians oder
 * `{ reject: <Grund> }`. Regeln (Release-Review 182, K1/H1):
 *  - Einladender = einziger Nutzer mit update/delete in der ACL und =
 *    invitedByUid (Guardians haben nur read),
 *    LIVE aktiver Admin/Moderator der Org (nie `org.adminUid`).
 *  - Rolle: member | child | moderator (moderator nur, wenn der Einladende
 *    Admin ist); `admin` wird nie über Einladungen vergeben.
 *  - Kind-Rolle nur für Konten, die NACH der Einladung angelegt wurden und
 *    keine verifizierten Eltern haben (sonst Eltern-Zustimmung über
 *    inviteByEmail) — ein bestehendes Erwachsenen-Konto darf nicht per
 *    umgeschriebener Einladung zum Kind werden.
 *  - Ein Kind-Konto bekommt nie eine andere Rolle als child.
 *  - Guardians: aktive Nicht-Kind-Mitglieder der Org.
 */
async function vetInvite(db, invite, authUser, userData) {
  const orgId = invite.orgId;
  const invitedByUid = invite.invitedByUid;
  const aclOwners = aclUsers(invite.$permissions);
  if (!invitedByUid || aclOwners.length !== 1 || aclOwners[0] !== invitedByUid) {
    return { reject: `acl owner ${aclOwners.join(',') || '-'} != invitedByUid ${invitedByUid || '-'}` };
  }
  // Leserechte nur für den Einladenden und die Guardians der Einladung.
  const guardianSet = new Set(invite.guardianUids ?? []);
  const strayReaders = aclUsers(invite.$permissions, ['read'])
    .filter((u) => u !== invitedByUid && !guardianSet.has(u));
  if (strayReaders.length > 0) return { reject: `unexpected readers ${strayReaders.join(',')}` };
  const inviter = await activeMember(db, orgId, invitedByUid);
  const inviterRole = inviter?.role ?? '';
  if (inviterRole !== 'admin' && inviterRole !== 'moderator') {
    return { reject: `inviter ${invitedByUid} is not an active admin/mod (role=${inviterRole || '-'})` };
  }

  const rawRole = invite.role ?? 'member';
  let role;
  if (rawRole === 'child') role = 'child';
  else if (rawRole === 'moderator' && inviterRole === 'admin') role = 'moderator';
  else role = 'member';
  if (rawRole !== role) {
    return { reject: `role ${rawRole} not allowed for inviter role ${inviterRole}` };
  }

  const isChildAccount = userData?.isChild === true;
  const hasParents = (userData?.verifiedParentUids ?? []).length > 0;
  if (isChildAccount && role !== 'child') {
    return { reject: 'child account cannot get a non-child role' };
  }

  const guardianUids = [];
  if (role === 'child') {
    if (hasParents) return { reject: 'child has verified parents — consent flow required' };
    const accountCreated = new Date(authUser.$createdAt).getTime();
    const invited = new Date(invite.$createdAt).getTime();
    if (!isChildAccount && !(accountCreated >= invited)) {
      return { reject: 'existing account cannot be turned into a child via invitation' };
    }
    const raw = [...new Set((invite.guardianUids ?? []).filter((u) => typeof u === 'string' && u))];
    for (const g of raw) {
      const m = await activeMember(db, orgId, g);
      if (m && m.role !== 'child') guardianUids.push(g);
    }
    if (guardianUids.length === 0) return { reject: 'no valid guardian' };
  }
  return { role, guardianUids };
}

module.exports = async ({ req, res, log, error }) => {
  const uid = req.headers['x-appwrite-user-id'];
  if (!uid) {
    return res.json({ error: 'Unauthenticated' }, 401);
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);
  const users = new Users(client);

  let authUser;
  try {
    authUser = await users.get(uid);
  } catch (err) {
    error(`Failed to get user ${uid}: ${err.message}`);
    return res.json({ error: 'User not found' }, 404);
  }
  const email = authUser.email.toLowerCase().trim();
  log(`processMyInvitations: uid=${uid} email=${email}`);

  const invitesResult = await db.listDocuments(DB_ID, COL_INVITATIONS, [
    Query.equal('email', email),
    Query.equal('status', 'pending'),
    Query.limit(50),
  ]);

  log(`Found ${invitesResult.documents.length} pending invitation(s)`);

  let processed = 0;

  // User-Doc einmal laden (Anzeigename, Foto, isChild, Eltern-Links)
  let userData = null;
  try {
    userData = await db.getDocument(DB_ID, COL_USERS, uid);
  } catch (_) { /* User-Doc noch nicht angelegt */ }

  // Jede Einladung einzeln absichern: ein Fehler blockiert die übrigen nicht.
  for (const invite of invitesResult.documents) {
    try {
      if (await processInvite(db, invite, authUser, userData, uid, email, log)) processed++;
    } catch (e) {
      error(`Invite ${invite.$id}: ${e.message}`);
    }
  }

  return res.json({ processed });
};

async function processInvite(db, invite, authUser, userData, uid, email, log) {
  const orgId = invite.orgId;

  // Org existiert?
  let org;
  try {
    org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
  } catch (_) {
    await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'invalid' });
    log(`Org ${orgId} not found, invite ${invite.$id} marked invalid`);
    return false;
  }

  const verdict = await vetInvite(db, invite, authUser, userData);
  if (verdict.reject) {
    await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'invalid' });
    log(`Invite ${invite.$id} rejected: ${verdict.reject}`);
    return false;
  }
  const { role, guardianUids } = verdict;
  const isChild = role === 'child';

  // Bereits Mitglied?
  const memberId = `${orgId}_${uid}`;
  let alreadyMember = false;
  try {
    await db.getDocument(DB_ID, COL_MEMBERS, memberId);
    alreadyMember = true;
  } catch (_) { /* nicht vorhanden — OK */ }

  if (alreadyMember) {
    await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'accepted' });
    log(`Already member, invite ${invite.$id} marked accepted`);
    return false;
  }

  const displayName = userData?.displayName ?? email;
  const memberStatus = isChild ? 'pending' : 'active';

  const memberData = {
    orgId,
    uid,
    displayName,
    // Email wird nur für Nicht-Kinder gespeichert — Minderjährigendaten
    // dürfen nicht in für alle Org-Mitglieder lesbaren Docs stehen (DSGVO).
    email: isChild ? '' : email,
    role,
    joinedAt: new Date().toISOString(),
    guardianUids: isChild ? guardianUids : [],
    status: memberStatus,
    childAlertInterval: 'hourly',
    notificationsEnabled: true,
  };
  if (userData?.photoUrl) memberData.photoUrl = userData.photoUrl;

  // Nur lesbar — Member-Docs schreiben ausschließlich Server-Functions
  // (sonst Selbst-Eskalation über `role`, siehe self-service).
  await db.createDocument(DB_ID, COL_MEMBERS, memberId, memberData, [
    Permission.read(Role.users()),
  ]);

  if (!isChild) {
    // Zu org.memberUids hinzufügen (manuelles arrayUnion)
    const memberUids = [...(org.memberUids ?? [])];
    if (!memberUids.includes(uid)) {
      memberUids.push(uid);
      await db.updateDocument(DB_ID, COL_ORGANIZATIONS, orgId, { memberUids });
    }

    // membershipsJson auf User-Doc aktualisieren
    if (userData) {
      const memberships = userData.membershipsJson
        ? JSON.parse(userData.membershipsJson)
        : [];
      if (!memberships.some((m) => m.orgId === orgId)) {
        memberships.push({ orgId, role });
        userData.membershipsJson = JSON.stringify(memberships);
        await db.updateDocument(DB_ID, COL_USERS, uid, {
          membershipsJson: userData.membershipsJson,
        });
      }
    }
  } else if (userData && userData.isChild !== true) {
    // Kind (frisch registriert, siehe vetInvite): isChild=true setzen
    userData.isChild = true;
    await db.updateDocument(DB_ID, COL_USERS, uid, { isChild: true });
  }

  await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'accepted' });
  log(`Invite ${invite.$id} processed (role=${role})`);
  return true;
}
