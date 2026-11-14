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
const COL_ORGS = 'organizations';

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

  // ── Geschützte Felder validieren ──────────────────────────────────────────
  // Conversations schreibt die App seit der Härtung nur noch über die Function
  // `conversation-action`. Alte App-Versionen legen sie aber noch selbst an
  // (Collection-`create`), solange die nicht entzogen ist → hier prüfen.
  // guardianUids wird IMMER aus den Member-Docs neu berechnet: so kann auch
  // über eine Alt-ACL (`update team(convId)`) niemand Guardians entfernen.
  const fix = {};
  const participantUids = conv.participantUids ?? [];
  const members = await loadMembers(db, orgId, participantUids);
  const guardianUids = [...new Set(Object.values(members).flatMap((m) => m.guardianUids ?? []))];
  if (!sameSet(guardianUids, conv.guardianUids ?? [])) fix.guardianUids = guardianUids;

  const creator = event.endsWith('.create') ? clientCreator(conv.$permissions ?? []) : null;
  if (creator) {
    const verdict = await validateClientCreate(db, conv, creator, members, supervisorUids, log);
    if (verdict === 'delete') {
      try {
        await db.deleteDocument(DB_ID, COL_CONVERSATIONS, convId);
        log(`Conv ${convId}: client-created by ${creator} without permission → deleted`);
      } catch (e) {
        error(`Conv ${convId}: failed to delete invalid conv: ${e.message}`);
      }
      return res.empty();
    }
    Object.assign(fix, verdict);
  }

  const desiredMembers = [
    ...new Set([
      ...participantUids,
      ...(fix.guardianUids ?? conv.guardianUids ?? []),
      ...supervisorUids,
    ]),
  ].filter(Boolean);

  await ensureTeam(teams, convId, `Conversation ${convId}`, log);
  await reconcileTeamMembers(teams, convId, desiredMembers, log, error);

  // ACL + Korrekturen idempotent setzen — nur schreiben, wenn abweichend
  // (sonst Update-Loop: jedes Update löst diese Function erneut aus).
  const desiredPerms = buildConvPerms(convId);
  const permsOk = samePerms(conv.$permissions ?? [], desiredPerms);
  if (!permsOk || Object.keys(fix).length > 0) {
    try {
      await db.updateDocument(DB_ID, COL_CONVERSATIONS, convId, fix, desiredPerms);
      log(`Conv ${convId}: updated (perms=${!permsOk}, fields=${Object.keys(fix).join(',') || '-'})`);
    } catch (e) {
      error(`Conv ${convId}: failed to update: ${e.message}`);
    }
  } else {
    log(`Conv ${convId}: permissions already correct, skipping write`);
  }

  return res.empty();
};

/**
 * Ersteller eines client-angelegten Docs: alte Apps setzen
 * `read/update user(self)` — ein Client kann nur seine eigene `user:`-Rolle
 * granten, die Angabe ist also fälschungssicher. `conversation-action` und das
 * Team-Modell vergeben nie `update("user:…")`.
 */
function clientCreator(perms) {
  for (const p of perms) {
    const m = p.match(/^update\("user:([^"/]+)"\)$/);
    if (m) return m[1];
  }
  return null;
}

/**
 * Prüft eine von einer alten App direkt angelegte Conversation mit denselben
 * Regeln wie `conversation-action`. Liefert 'delete' oder Feld-Korrekturen.
 */
async function validateClientCreate(db, conv, creator, members, supervisorUids, log) {
  const participantUids = conv.participantUids ?? [];
  const creatorMember = await getMember(db, conv.orgId, creator);
  if (!creatorMember || (creatorMember.status ?? 'active') !== 'active') return 'delete';
  if (!participantUids.includes(creator)) return 'delete';
  if (participantUids.some((u) => members[u]?.status !== 'active')) return 'delete';

  const isSup = supervisorUids.includes(creator);
  if (conv.isGroup && !isSup) return 'delete';

  const fix = {};
  if (conv.requestedBy !== creator) fix.requestedBy = creator;

  let org = null;
  try { org = await db.getDocument(DB_ID, COL_ORGS, conv.orgId); } catch (_) { /* egal */ }
  if (org && conv.orgAdminUid !== org.adminUid) fix.orgAdminUid = org.adminUid;
  const canApprove = [...new Set([org?.adminUid, ...supervisorUids])].filter(Boolean);
  if (!sameSet(canApprove, conv.canApproveUids ?? [])) fix.canApproveUids = canApprove;

  if (conv.status === 'approved') {
    const other = participantUids.find((u) => u !== creator);
    const isGuardianOfOther = !conv.isGroup && other &&
      (members[other]?.guardianUids ?? []).includes(creator);
    if (!isSup && !isGuardianOfOther) {
      fix.status = 'pending';
      fix.approvedBy = null;
      fix.approvedAt = null;
      log(`Conv ${conv.$id}: self-approved by ${creator} → reset to pending`);
    }
  } else if (conv.status !== 'pending') {
    fix.status = 'pending';
  }
  return fix;
}

async function getMember(db, orgId, uid) {
  try {
    const m = await db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${uid}`);
    return m.orgId === orgId && m.uid === uid ? m : null;
  } catch (_) {
    return null;
  }
}

/** Member-Docs der Teilnehmer in EINER Query (Index orgId_uid_idx). */
async function loadMembers(db, orgId, uids) {
  const map = {};
  const list = [...new Set(uids)].filter(Boolean);
  for (let i = 0; i < list.length; i += 100) {
    const r = await db.listDocuments(DB_ID, COL_MEMBERS, [
      Query.equal('orgId', orgId),
      Query.equal('uid', list.slice(i, i + 100)),
      Query.limit(100),
    ]);
    for (const d of r.documents) map[d.uid] = d;
  }
  return map;
}

function sameSet(a, b) {
  const sa = new Set(a);
  const sb = new Set(b);
  return sa.size === sb.size && [...sa].every((v) => sb.has(v));
}

async function orgSupervisors(db, orgId) {
  const result = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', ['admin', 'moderator']),
    Query.limit(200),
  ]);
  return result.documents.map((d) => d.uid).filter(Boolean);
}

// Nur Lesen: alle Schreibzugriffe laufen über `conversation-action` bzw.
// andere Server-Functions (Appwrite kennt keine Feld-Rechte — `update` fürs
// Team hieße: jeder Teilnehmer kann status/participantUids/guardianUids
// ändern; `delete` hieße: jeder kann den Chat löschen).
//
// Übergang (Rollout-Stufen 0–3, docs/security/self-escalation.md §4): Mit
// CONV_LEGACY_TEAM_WRITE=true behält das Team `update/delete`, damit alte
// App-Versionen in neu angelegten Chats weiter Vorschau/Pin schreiben können.
// Die Variable MUSS vor `lock-own-docs.js --only=conversations` entfernt
// werden, sonst öffnet diese Function gehärtete Chats beim nächsten Update.
function buildConvPerms(convId) {
  const c = Role.team(convId);
  if (process.env.CONV_LEGACY_TEAM_WRITE === 'true') {
    return [Permission.read(c), Permission.update(c), Permission.delete(c)];
  }
  return [Permission.read(c)];
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
