const { Client, Databases } = require('node-appwrite');
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

  const consent = req.body;
  if (!consent || !consent.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { status, childUid, childName, orgId, orgName, invitedByUid, proposedGuardianUids } = consent;

  // Nur bei approved oder vetoed verarbeiten
  if (status !== 'approved' && status !== 'vetoed') {
    log(`Status is "${status}", skipping`);
    return res.empty();
  }

  if (status === 'approved') {
    // Kind als Mitglied hinzufügen — Idempotenz: überspringen wenn bereits vorhanden
    const memberId = `${orgId}_${childUid}`;
    let alreadyMember = false;
    try {
      await db.getDocument(DB_ID, COL_MEMBERS, memberId);
      alreadyMember = true;
    } catch (_) { /* nicht vorhanden — OK */ }

    if (!alreadyMember) {
      let childData = null;
      try {
        childData = await db.getDocument(DB_ID, COL_USERS, childUid);
      } catch (_) { /* User-Doc noch nicht vorhanden */ }

      await db.createDocument(DB_ID, COL_MEMBERS, memberId, {
        orgId,
        uid: childUid,
        displayName: childData?.displayName ?? childName ?? '',
        email: childData?.email ?? '',
        photoUrl: childData?.photoUrl ?? null,
        role: 'child',
        joinedAt: new Date().toISOString(),
        guardianUids: proposedGuardianUids ?? [],
        status: 'pending',
        childAlertInterval: 'hourly',
        notificationsEnabled: true,
      });

      log(`Created member doc for child ${childUid} in org ${orgId}`);
    } else {
      log(`Child ${childUid} already member, skipping DB write`);
    }

    if (invitedByUid) {
      await sendToUsers(
        db,
        [invitedByUid],
        'Einladung genehmigt',
        `Die Eltern von ${childName ?? 'dem Kind'} haben der Einladung in ${orgName ?? orgId} zugestimmt.`,
        { type: 'consent_approved', orgId },
        log,
        error,
      );
    }
  } else {
    // vetoed
    if (invitedByUid) {
      await sendToUsers(
        db,
        [invitedByUid],
        'Einladung abgelehnt',
        `Die Eltern von ${childName ?? 'dem Kind'} haben die Einladung in ${orgName ?? orgId} abgelehnt.`,
        { type: 'consent_vetoed', orgId },
        log,
        error,
      );
    }
  }

  log(`on-parent-consent: status=${status} child=${childUid} org=${orgId}`);
  return res.empty();
};
