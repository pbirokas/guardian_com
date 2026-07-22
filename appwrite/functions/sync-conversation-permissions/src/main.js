const {
  Client,
  Databases,
  Teams,
  Permission,
  Role,
  Query,
} = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVERSATIONS = 'conversations';
const COL_MEMBERS = 'members';

/**
 * Hält Team-Mitgliedschaft und Lese-/Schreibrechte einer Conversation synchron.
 *
 * Trigger: databases.guardian.collections.conversations.documents.*.(create|update|delete)
 *
 * Ein Chat = ein Team (id = convId). Mitglieder = Teilnehmer + Guardians +
 * Aufsicht (Admin/Moderatoren der Org). Nachrichten referenzieren in ihrer ACL
 * nur `team(convId)` — das kann der Client setzen (er ist selbst im Team), und
 * ein späterer Beitritt/eine Beförderung wirkt in O(1) rückwirkend auf alle
 * (auch historischen) Nachrichten.
 */
module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);
  const teams = new Teams(client);

  const conv = req.body;
  if (!conv || !conv.$id) {
    error('No document in payload');
    return res.empty();
  }
  const convId = conv.$id;
  const event = req.headers['x-appwrite-event'] || '';

  // Conversation gelöscht → zugehöriges Team entsorgen.
  if (event.endsWith('.delete')) {
    try {
      await teams.delete(convId);
      log(`Deleted team ${convId}`);
    } catch (e) {
      log(`Team ${convId} delete skipped: ${e.message}`);
    }
    return res.empty();
  }

  const orgId = conv.orgId;
  if (!orgId) {
    error(`Conv ${convId} has no orgId`);
    return res.empty();
  }

  // Aufsicht der Org (Admin + Moderatoren) — gehören in JEDES Conv-Team, damit
  // sie Nachrichten lesen können (Nachrichten-ACL kennt nur team(convId)).
  const supervisorUids = await orgSupervisors(db, orgId);

  const desiredMembers = [
    ...new Set([
      ...(conv.participantUids ?? []),
      ...(conv.guardianUids ?? []),
      ...supervisorUids,
    ]),
  ].filter(Boolean);

  await ensureTeam(teams, convId, `Conversation ${convId}`, log);
  await reconcileTeamMembers(teams, convId, desiredMembers, log, error);

  // ACL idempotent setzen — nur schreiben, wenn abweichend (sonst Update-Loop).
  const desiredPerms = buildConvPerms(convId);
  if (!samePerms(conv.$permissions ?? [], desiredPerms)) {
    try {
      await db.updateDocument(DB_ID, COL_CONVERSATIONS, convId, {}, desiredPerms);
      log(`Conv ${convId}: permissions updated to team model`);
    } catch (e) {
      error(`Conv ${convId}: failed to update permissions: ${e.message}`);
    }
  } else {
    log(`Conv ${convId}: permissions already correct, skipping write`);
  }

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

function buildConvPerms(convId) {
  const c = Role.team(convId);
  return [Permission.read(c), Permission.update(c), Permission.delete(c)];
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
      // userId-basiert + kein url → serverseitig sofort bestätigt (keine E-Mail).
      await teams.createMembership(teamId, ['member'], undefined, uid);
      log(`Team ${teamId}: added ${uid}`);
    } catch (e) {
      if (e.code === 409) continue; // schon Mitglied (Race)
      if (e.code === 404) continue; // Nutzer existiert nicht (verwaister UID)
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

function samePerms(a, b) {
  if (a.length !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}
