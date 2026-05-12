const { Client, Databases, Users, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_ORGANIZATIONS = 'organizations';
const COL_MEMBERS = 'members';
const COL_INVITATIONS = 'invitations';

module.exports = async ({ req, res, log, error }) => {
  const uid = req.headers['x-appwrite-user-id'];
  if (!uid) {
    return res.json({ error: 'Unauthenticated' }, 401);
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
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

  for (const invite of invitesResult.documents) {
    const orgId = invite.orgId;
    const role = invite.role ?? 'member';
    const guardianUids = invite.guardianUids ?? [];
    const isChild = role === 'child';

    // Org existiert?
    let org;
    try {
      org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
    } catch (_) {
      await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'invalid' });
      log(`Org ${orgId} not found, invite ${invite.$id} marked invalid`);
      continue;
    }

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
      continue;
    }

    // User-Doc laden (Anzeigename, Foto)
    let userData = null;
    try {
      userData = await db.getDocument(DB_ID, COL_USERS, uid);
    } catch (_) { /* User-Doc noch nicht angelegt */ }

    const displayName = userData?.displayName ?? email;
    const memberStatus = isChild ? 'pending' : 'active';

    const memberData = {
      orgId,
      uid,
      displayName,
      email,
      role,
      joinedAt: new Date().toISOString(),
      guardianUids: isChild ? guardianUids : [],
      status: memberStatus,
      childAlertInterval: 'hourly',
      notificationsEnabled: true,
    };
    if (userData?.photoUrl) memberData.photoUrl = userData.photoUrl;

    await db.createDocument(DB_ID, COL_MEMBERS, memberId, memberData);

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
          await db.updateDocument(DB_ID, COL_USERS, uid, {
            membershipsJson: JSON.stringify(memberships),
          });
        }
      }
    } else {
      // Kind: isChild=true setzen
      if (userData) {
        await db.updateDocument(DB_ID, COL_USERS, uid, { isChild: true });
      }
    }

    await db.updateDocument(DB_ID, COL_INVITATIONS, invite.$id, { status: 'accepted' });
    log(`Invite ${invite.$id} processed (role=${role})`);
    processed++;
  }

  return res.json({ processed });
};
