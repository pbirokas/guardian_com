const { Client, Databases, Query } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_MEMBERS = 'members';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const claimRequest = req.body;
  if (!claimRequest || !claimRequest.$id) {
    error('No document in payload');
    return res.empty();
  }

  // Nur bei status=confirmed verarbeiten
  if (claimRequest.status !== 'confirmed') {
    log(`Status is "${claimRequest.status}", skipping`);
    return res.empty();
  }

  const parentUid = claimRequest.fromUid;
  const childUid = claimRequest.toUid;

  if (!parentUid || !childUid) {
    error('Missing fromUid or toUid');
    return res.empty();
  }

  // Idempotenz-Check: falls Verknüpfung bereits besteht, überspringen
  const childUserResult = await db.listDocuments(DB_ID, COL_USERS, [
    Query.equal('$id', childUid),
    Query.limit(1),
  ]);
  const childUser = childUserResult.documents[0];
  if (!childUser) {
    error(`Child user ${childUid} not found`);
    return res.empty();
  }

  if ((childUser.verifiedParentUids ?? []).includes(parentUid)) {
    log(`Link already exists for ${parentUid} → ${childUid}, skipping`);
    return res.empty();
  }

  log(`Processing claim: parent=${parentUid} child=${childUid}`);

  // 1. Gegenseitige Verknüpfung setzen + isChild=true
  await db.updateDocument(DB_ID, COL_USERS, childUid, {
    verifiedParentUids: [...(childUser.verifiedParentUids ?? []), parentUid],
    isChild: true,
  });

  const parentUserResult = await db.listDocuments(DB_ID, COL_USERS, [
    Query.equal('$id', parentUid),
    Query.limit(1),
  ]);
  const parentUser = parentUserResult.documents[0];
  if (parentUser) {
    await db.updateDocument(DB_ID, COL_USERS, parentUid, {
      verifiedChildUids: [...(parentUser.verifiedChildUids ?? []), childUid],
    });
  }

  // 2. Alle Org-Memberships des Kindes auf role=child downgraden
  const membershipsRaw = childUser.membershipsJson
    ? JSON.parse(childUser.membershipsJson)
    : [];

  const updatedMemberships = membershipsRaw.map((m) => ({ ...m, role: 'child' }));

  // Member-Docs in allen Orgs updaten
  for (const membership of membershipsRaw) {
    if (!membership.orgId || membership.role === 'child') continue;
    try {
      const memberResult = await db.listDocuments(DB_ID, COL_MEMBERS, [
        Query.equal('orgId', membership.orgId),
        Query.equal('uid', childUid),
        Query.limit(1),
      ]);
      if (memberResult.documents[0]) {
        await db.updateDocument(DB_ID, COL_MEMBERS, memberResult.documents[0].$id, {
          role: 'child',
        });
        log(`Downgraded role in org ${membership.orgId}`);
      }
    } catch (err) {
      error(`Failed to downgrade role in org ${membership.orgId}: ${err.message}`);
    }
  }

  // membershipsJson auf user doc aktualisieren
  if (updatedMemberships.length > 0) {
    await db.updateDocument(DB_ID, COL_USERS, childUid, {
      membershipsJson: JSON.stringify(updatedMemberships),
    });
  }

  await sendToUsers(
    db,
    [parentUid],
    'Verknüpfung bestätigt',
    `${childUser.displayName} hat deine Verknüpfungsanfrage bestätigt.`,
    { type: 'claim_confirmed', childUid },
    log,
    error,
  );

  log(`onClaimConfirmed done: parent=${parentUid} child=${childUid}`);
  return res.empty();
};
