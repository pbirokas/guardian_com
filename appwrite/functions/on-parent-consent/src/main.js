const { Client, Databases, Permission, Role } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_MEMBERS = 'members';
const COL_ORGS = 'organizations';

// ACL-Einträge `<recht>("user:<uid>")` eines Docs → Set „recht:uid“.
function aclSet(perms) {
  const out = new Set();
  for (const p of perms ?? []) {
    const m = /^(\w+)\("user:([^"/]+)"\)$/.exec(p);
    if (m) out.add(`${m[1]}:${m[2]}`);
  }
  return out;
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
 * Prüft eine genehmigte Eltern-Zustimmung gegen Live-Daten:
 *  - Kind ist ein Kind-Konto mit verifizierten Eltern; parentUids im Doc sind
 *    nicht leer und alle echte verifizierte Eltern dieses Kindes.
 *  - Das Doc stammt von inviteByEmail: jedes Elternteil hat `update` in der ACL
 *    (ein Client kann beim Anlegen nur Rechte für sich selbst vergeben) und
 *    sonst hat niemand `update` (der Einladende darf nicht selbst genehmigen).
 *  - approvedBy ist eines dieser Elternteile.
 *  - Der Einladende ist LIVE aktiver Admin/Moderator der Org.
 *  - Nicht abgelaufen.
 *  - Guardians: nur aktive Nicht-Kind-Mitglieder der Org, mindestens einer.
 */
async function vetConsent(db, consent, childData) {
  const { childUid, orgId, invitedByUid } = consent;
  if (!childData) return { reject: `child ${childUid} not found` };
  if (childData.isChild !== true) return { reject: 'target is not a child account' };
  const verified = new Set(childData.verifiedParentUids ?? []);
  const parentUids = [...new Set(consent.parentUids ?? [])];
  if (parentUids.length === 0) return { reject: 'no parents on consent' };
  if (parentUids.some((u) => !verified.has(u))) return { reject: 'parentUids are not verified parents' };

  const acl = aclSet(consent.$permissions);
  if (parentUids.some((u) => !acl.has(`update:${u}`))) return { reject: 'acl lacks parent update (not server-created)' };
  const otherUpdaters = [...acl].filter((e) => e.startsWith('update:') && !parentUids.includes(e.slice(7)));
  if (otherUpdaters.length > 0) return { reject: `non-parent update rights: ${otherUpdaters.join(',')}` };
  if (!parentUids.includes(consent.approvedBy)) return { reject: `approvedBy ${consent.approvedBy || '-'} is not a parent` };

  const inviter = await activeMember(db, orgId, invitedByUid);
  if (!inviter || (inviter.role !== 'admin' && inviter.role !== 'moderator')) {
    return { reject: `inviter ${invitedByUid || '-'} is not an active admin/mod of ${orgId}` };
  }
  if (consent.expiresAt && new Date(consent.expiresAt).getTime() < Date.now()) {
    return { reject: 'consent expired' };
  }

  const guardianUids = [];
  for (const g of new Set(consent.proposedGuardianUids ?? [])) {
    const m = await activeMember(db, orgId, g);
    if (m && m.role !== 'child' && g !== childUid) guardianUids.push(g);
  }
  if (guardianUids.length === 0) return { reject: 'no valid guardian' };
  return { guardianUids };
}

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const consent = req.body;
  if (!consent || !consent.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { status, childUid, childName, orgId, orgName, invitedByUid } = consent;

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

    // Das Consent-Doc ist (noch) client-beschreibbar → nichts darin ist ein
    // Nachweis. Alles gegen Live-Daten prüfen (Release-Review 182, K2).
    const verdict = await vetConsent(db, consent, childData);
    if (verdict.reject) {
      error(`Consent ${consent.$id} rejected: ${verdict.reject}`);
      return res.empty();
    }
    const { guardianUids } = verdict;

    if (!existingMember) {
      await db.createDocument(DB_ID, COL_MEMBERS, memberId, {
        orgId,
        uid: childUid,
        displayName: childData?.displayName ?? childName ?? '',
        // Keine E-Mail von Kindern in Member-Docs (für alle lesbar, DSGVO).
        email: '',
        photoUrl: childData?.photoUrl ?? null,
        role: 'child',
        joinedAt: new Date().toISOString(),
        guardianUids,
        status: 'active',
        childAlertInterval: 'hourly',
        notificationsEnabled: true,
      }, [
        // Nur lesbar — Member-Docs schreiben ausschließlich Server-Functions.
        Permission.read(Role.users()),
      ]);
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
