const { Client, Databases, Teams, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';

// Org-weites Aufsichts-Team: Admin + alle Moderatoren einer Org.
// Wird in der ACL jeder Conversation/Nachricht referenziert → Beförderung
// eines Mods wirkt in O(1) rückwirkend auf alle Bestandschats + Historie.
function supTeamId(orgId) {
  return `sup_${orgId}`;
}

/**
 * Hält das Org-Supervisor-Team synchron mit den Mitgliedern der Rolle
 * admin/moderator.
 *
 * Trigger: databases.guardian.collections.members.documents.*.(create|update|delete)
 *
 * Die members-Collection ist die einzige Quelle: Org-Erstellung (Admin-Member),
 * Beförderung/Degradierung, Admin-Übergabe und Entfernen laufen alle darüber.
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

  // Früh-Ausstieg: ein NEU erstelltes Mitglied ohne Aufsichtsrolle kann nicht
  // im Supervisor-Team sein → spart bei jedem Beitritt (häufigster Fall) die
  // Team-API-Aufrufe. Bei update/delete ist ohne alten Doc-Stand kein sicherer
  // Skip möglich (Rolle könnte vorher admin/moderator gewesen sein).
  const event = req.headers['x-appwrite-event'] || '';
  if (event.endsWith('.create') && !['admin', 'moderator'].includes(member.role)) {
    log(`Create of non-supervisor member (${member.role}) — skipping`);
    return res.empty();
  }

  const teamId = supTeamId(orgId);

  // Soll-Zustand: alle Admin-/Moderator-UIDs der Org.
  const result = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', ['admin', 'moderator']),
    Query.limit(200),
  ]);
  const desiredUids = [
    ...new Set(result.documents.map((d) => d.uid).filter(Boolean)),
  ];

  await ensureTeam(teams, teamId, `Supervisors ${orgId}`, log);
  await reconcileTeamMembers(teams, teamId, desiredUids, log, error);

  log(`Supervisor team ${teamId}: ${desiredUids.length} member(s)`);
  return res.empty();
};

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
