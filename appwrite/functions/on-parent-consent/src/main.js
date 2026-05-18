const { Client, Databases } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_MEMBERS = 'members';
const COL_ORGS = 'organizations';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
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
    const memberId = `${orgId}_${childUid}`;

    const [childData, existingMember] = await Promise.all([
      db.getDocument(DB_ID, COL_USERS, childUid).catch(() => null),
      db.getDocument(DB_ID, COL_MEMBERS, memberId).catch(() => null),
    ]);

    if (!existingMember) {
      await db.createDocument(DB_ID, COL_MEMBERS, memberId, {
        orgId,
        uid: childUid,
        displayName: childData?.displayName ?? childName ?? '',
        email: childData?.email ?? '',
        photoUrl: childData?.photoUrl ?? null,
        role: 'child',
        joinedAt: new Date().toISOString(),
        guardianUids: proposedGuardianUids ?? [],
        status: 'active',
        childAlertInterval: 'hourly',
        notificationsEnabled: true,
      });
      log(`Created member doc for child ${childUid} in org ${orgId}`);
    } else if (existingMember.status !== 'active') {
      await db.updateDocument(DB_ID, COL_MEMBERS, memberId, { status: 'active' });
      log(`Activated member ${childUid} in org ${orgId}`);
    }

    // Kind in org.memberUids eintragen (für watchMyOrganizations)
    try {
      const org = await db.getDocument(DB_ID, COL_ORGS, orgId);
      const memberUids = [...(org.memberUids ?? [])];
      if (!memberUids.includes(childUid)) {
        memberUids.push(childUid);
        await db.updateDocument(DB_ID, COL_ORGS, orgId, { memberUids });
        log(`Added ${childUid} to org.memberUids`);
      }
    } catch (e) {
      error(`Failed to update org.memberUids: ${e.message}`);
    }

    // membershipsJson des Kindes aktualisieren
    try {
      const parsed = childData?.membershipsJson ? JSON.parse(childData.membershipsJson) : [];
      const memberships = Array.isArray(parsed) ? parsed : [];
      if (!memberships.some((m) => m.orgId === orgId)) {
        memberships.push({ orgId, role: 'child' });
        await db.updateDocument(DB_ID, COL_USERS, childUid, {
          membershipsJson: JSON.stringify(memberships),
        });
        log(`Updated membershipsJson for child ${childUid}`);
      }
    } catch (e) {
      error(`Failed to update membershipsJson: ${e.message}`);
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
