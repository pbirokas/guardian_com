const { Client, Databases, Teams, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const COL_CONVERSATIONS = 'conversations';

// `sup_<orgId>` ist KEIN ACL-Team mehr, sondern ein günstiger Cache/Detektor:
// er hält den zuletzt bekannten Supervisor-Satz. Ändert er sich nicht, sparen
// wir die teure Iteration über alle Org-Conversations.
function supTeamId(orgId) {
  return `sup_${orgId}`;
}

/**
 * Propagiert Aufsichts-Rollen (Admin/Moderator) in die Conv-Teams der Org.
 *
 * Trigger: databases.guardian.collections.members.documents.*.(create|update|delete)
 *
 * Aufsicht muss in JEDEM Conv-Team der Org sein, weil Nachrichten-ACLs nur
 * `team(convId)` kennen. Ändert sich der Supervisor-Satz (Beförderung/
 * Degradierung/Admin-Wechsel/Entfernen), werden alle Conv-Teams der Org
 * nachgezogen — sonst früher Ausstieg.
 */
module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);
  const teams = new Teams(client);

  const member = req.body;
  const orgId = member?.orgId;
  if (!orgId) {
    error('No orgId in member payload');
    return res.empty();
  }

  // Früh-Ausstieg: ein NEU erstelltes Mitglied ohne Aufsichtsrolle ändert den
  // Supervisor-Satz nie → häufigster Fall (Beitritte) ohne weitere Arbeit.
  const event = req.headers['x-appwrite-event'] || '';
  if (event.endsWith('.create') && !['admin', 'moderator'].includes(member.role)) {
    return res.empty();
  }

  // Aktuellen Supervisor-Satz bestimmen.
  const supervisorUids = await orgSupervisors(db, orgId);

  // Mit dem Cache (`sup_<orgId>`) vergleichen. Unverändert → nichts zu tun.
  const cacheTeam = supTeamId(orgId);
  await ensureTeam(teams, cacheTeam, `Supervisors ${orgId}`, log);
  const known = await membershipUids(teams, cacheTeam);
  if (setsEqual(known, supervisorUids)) {
    log(`Supervisors unchanged for org ${orgId} — skipping conv propagation`);
    return res.empty();
  }

  // Cache aktualisieren …
  await reconcileTeamMembers(teams, cacheTeam, supervisorUids, log, error);

  // … und den neuen Supervisor-Satz in ALLE Conv-Teams der Org einpflegen.
  let cursor = null;
  let convCount = 0;
  do {
    const q = [Query.equal('orgId', orgId), Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const convs = await db.listDocuments(DB_ID, COL_CONVERSATIONS, q);
    for (const conv of convs.documents) {
      convCount++;
      const desired = [
        ...new Set([
          ...(conv.participantUids ?? []),
          ...(conv.guardianUids ?? []),
          ...supervisorUids,
        ]),
      ].filter(Boolean);
      await ensureTeam(teams, conv.$id, `Conversation ${conv.$id}`, log);
      await reconcileTeamMembers(teams, conv.$id, desired, log, error);
    }
    cursor = convs.documents.length === 100 ? convs.documents.at(-1).$id : null;
  } while (cursor);

  log(`Propagated supervisor change to ${convCount} conversation(s) in org ${orgId}`);
  return res.empty();
};

async function orgSupervisors(db, orgId) {
  const result = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', ['admin', 'moderator']),
    Query.limit(200),
  ]);
  return result.documents.map((d) => d.uid).filter(Boolean);
}

async function membershipUids(teams, teamId) {
  const current = await teams.listMemberships(teamId);
  return (current.memberships ?? []).map((m) => m.userId).filter(Boolean);
}

function setsEqual(a, b) {
  if (a.length !== b.length) return false;
  const sb = new Set(b);
  return a.every((x) => sb.has(x));
}

async function ensureTeam(teams, teamId, name, log) {
  try {
    await teams.get(teamId);
  } catch (e) {
    if (e.code === 404) {
      await teams.create(teamId, name);
      log(`Created team ${teamId}`);
    } else {
      throw e;
    }
  }
}

async function reconcileTeamMembers(teams, teamId, desiredUids, log, error) {
  const current = await teams.listMemberships(teamId);
  const currentByUid = new Map();
  for (const m of current.memberships ?? []) {
    if (m.userId) currentByUid.set(m.userId, m.$id);
  }
  const desiredSet = new Set(desiredUids);

  for (const uid of desiredSet) {
    if (currentByUid.has(uid)) continue;
    try {
      await teams.createMembership(teamId, ['member'], undefined, uid);
      log(`Team ${teamId}: added ${uid}`);
    } catch (e) {
      if (e.code === 409) continue;
      if (e.code === 404) continue; // verwaister UID
      error(`Team ${teamId}: failed to add ${uid}: ${e.message}`);
    }
  }

  for (const [uid, membershipId] of currentByUid) {
    if (desiredSet.has(uid)) continue;
    try {
      await teams.deleteMembership(teamId, membershipId);
      log(`Team ${teamId}: removed ${uid}`);
    } catch (e) {
      error(`Team ${teamId}: failed to remove ${uid}: ${e.message}`);
    }
  }
}
