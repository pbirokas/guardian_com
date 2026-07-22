const {
  Client,
  Databases,
  Teams,
  Permission,
  Role,
} = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVERSATIONS = 'conversations';

// Team-ID-Schema (deterministisch, muss mit dem Client übereinstimmen):
//  - Conversation-Team:  = convId               → Teilnehmer + Guardians
//  - Org-Supervisor-Team: = `sup_<orgId>`       → Admin + Moderatoren (org-weite Aufsicht)
function supTeamId(orgId) {
  return `sup_${orgId}`;
}

/**
 * Hält Team-Mitgliedschaft und Lese-/Schreibrechte einer Conversation synchron.
 *
 * Trigger: databases.guardian.collections.conversations.documents.*.(create|update|delete)
 *
 * Read/Update/Delete auf Conversation + (über denselben Team-Bezug) alle Nachrichten
 * werden auf das Team-Modell festgelegt. Dadurch wirken Mitglieder-/Rollenänderungen
 * in O(1): eine Team-Mitgliedschaft ändern statt jede Nachricht umschreiben.
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

  // Gewünschte Mitglieder des Conversation-Teams: Teilnehmer + Guardians.
  // Aufsicht (Admin/Mods) läuft NICHT über dieses Team, sondern über das
  // Org-Supervisor-Team, das direkt in der ACL referenziert wird.
  const desiredMembers = [
    ...new Set([
      ...(conv.participantUids ?? []),
      ...(conv.guardianUids ?? []),
    ]),
  ].filter(Boolean);

  // 1) Conversation-Team sicherstellen.
  await ensureTeam(teams, convId, `Conversation ${convId}`, log);

  // 2) Mitglieder abgleichen (fehlende hinzufügen, überzählige entfernen).
  await reconcileTeamMembers(teams, convId, desiredMembers, log, error);

  // 3) ACL auf das Team-Modell festlegen — idempotent: nur schreiben, wenn
  //    sie abweicht, sonst würde jeder Permission-Write ein weiteres
  //    Update-Event auslösen (Endlosschleife).
  const desiredPerms = buildConvPerms(convId, orgId);
  const currentPerms = conv.$permissions ?? [];
  if (!samePerms(currentPerms, desiredPerms)) {
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

function buildConvPerms(convId, orgId) {
  const conv = Role.team(convId);
  const sup = Role.team(supTeamId(orgId));
  return [
    Permission.read(conv),
    Permission.read(sup),
    Permission.update(conv),
    Permission.update(sup),
    Permission.delete(conv),
    Permission.delete(sup),
  ];
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

  // Hinzufügen
  for (const uid of desiredSet) {
    if (currentByUid.has(uid)) continue;
    try {
      // userId-basiert + kein url → serverseitig sofort bestätigt (keine E-Mail).
      await teams.createMembership(teamId, ['member'], undefined, uid);
      log(`Team ${teamId}: added ${uid}`);
    } catch (e) {
      if (e.code === 409) continue; // schon Mitglied (Race)
      error(`Team ${teamId}: failed to add ${uid}: ${e.message}`);
    }
  }

  // Entfernen
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
