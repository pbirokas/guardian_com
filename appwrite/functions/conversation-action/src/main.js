/**
 * conversation-action — alle schreibenden Conversation-Operationen der App.
 *
 * Warum eine Function: Appwrite kennt keine Feld-Rechte. Solange die
 * Conversation-ACL `update/delete team(convId)` enthielt, konnte jeder
 * Teilnehmer (auch ein Kind) per API `status` (Selbst-Genehmigung),
 * `participantUids` und `guardianUids` ändern oder den Chat löschen —
 * `sync-conversation-permissions` hat das dann ins Conv-Team übernommen.
 * Jetzt trägt eine Conversation nur noch `read team(convId)`; geschrieben wird
 * ausschließlich hier (API-Key) bzw. von anderen Server-Functions.
 *
 * Aktionen (body.action):
 *  - request        { orgId, targetUid }          → Direktchat-Anfrage (pending)
 *  - createDirect   { orgId, targetUid }          → genehmigter Direktchat (Admin/Mod oder Guardian des Ziels)
 *  - createGroup    { orgId, name, memberUids }   → Gruppenchat (Admin/Mod)
 *  - approve        { convId }                    → pending→approved (Admin/Mod oder Guardian eines Teilnehmers),
 *                                                   archived→approved (Admin/Mod)
 *  - reject         { convId }                    → pending-Anfrage löschen (wie approve)
 *  - archive        { convId }                    → Admin/Mod
 *  - updateGroupInfo{ convId, name?, imageUrl?, removeImage? } → Admin/Mod, nur Gruppen
 *  - setPersonalName{ convId, name }              → eigener Anzeigename eines Direktchats (Teilnehmer)
 *  - pin            { convId, msgId }             → Admin/Mod (Text kommt aus der Nachricht, nicht vom Client)
 *  - unpin          { convId }                    → Admin/Mod
 *  - addMembers     { convId, uids }              → Admin/Mod, nur Gruppen
 *  - removeMember   { convId, uid }               → Admin/Mod, nur Gruppen
 *
 * `lastMessage`/`lastMessageAt` setzt `on-new-message`.
 *
 * Sicherheit:
 *  - Aufrufer über x-appwrite-user-id (von Appwrite gesetzt)
 *  - Rolle LIVE aus dem Member-Doc des Aufrufers (nur `active`); Member-Docs
 *    sind seit der Härtung nicht mehr client-schreibbar
 *  - guardianUids/canApproveUids/orgAdminUid werden immer serverseitig aus den
 *    Member-/Org-Docs berechnet, nie vom Client übernommen
 */

const { Client, Databases, Query, ID, Permission, Role } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVS = 'conversations';
const COL_MEMBERS = 'members';
const COL_ORGS = 'organizations';
const COL_MESSAGES = 'chat_messages';

const MAX_NAME = 100;
const MAX_GROUP_MEMBERS = 256;
const IMAGE_URL_RE = /^https:\/\/[^\s"]+\/storage\/buckets\/[^/\s]+\/files\/[^/\s]+\/view(\?[^\s"]*)?$/;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

module.exports = async ({ req, res, log, error }) => {
  const callerId = req.headers['x-appwrite-user-id'];
  if (!callerId) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
  const db = new Databases(client);

  const handler = ACTIONS[body.action];
  if (!handler) return res.json({ error: `Unknown action: ${body.action}` }, 400);

  try {
    const result = await handler({ db, callerId, body, log });
    return res.json({ ok: true, ...result });
  } catch (e) {
    if (e instanceof HttpError) return res.json({ error: e.message }, e.status);
    error(`conversation-action ${body.action} failed: ${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }
};

// ── Aktionen ────────────────────────────────────────────────────────────────

const ACTIONS = {
  async request({ db, callerId, body }) {
    const { orgId, targetUid } = body;
    requireStr(orgId, 'orgId');
    requireStr(targetUid, 'targetUid');
    if (targetUid === callerId) throw new HttpError(400, 'Cannot chat with yourself');

    const caller = await activeMember(db, orgId, callerId);
    await activeMember(db, orgId, targetUid, 'Target is not an active member');

    const existing = await findDirect(db, orgId, callerId, targetUid);
    if (existing.some((c) => !['rejected', 'archived'].includes(c.status))) {
      throw new HttpError(409, 'conversation_exists');
    }

    const conv = await createConv(db, {
      orgId,
      callerId,
      participantUids: [callerId, targetUid],
      status: 'pending',
      requestorGuardianUid: (caller.guardianUids ?? [])[0] ?? null,
    });
    return { conversation: conv };
  },

  async createDirect({ db, callerId, body }) {
    const { orgId, targetUid } = body;
    requireStr(orgId, 'orgId');
    requireStr(targetUid, 'targetUid');
    if (targetUid === callerId) throw new HttpError(400, 'Cannot chat with yourself');

    const caller = await activeMember(db, orgId, callerId);
    const target = await activeMember(db, orgId, targetUid, 'Target is not an active member');
    const isGuardianOfTarget = (target.guardianUids ?? []).includes(callerId);
    if (!isSupervisor(caller) && !isGuardianOfTarget) throw new HttpError(403, 'Forbidden');

    // Wie bisher im Client: vorhandenen Direktchat wiederverwenden.
    const existing = await findDirect(db, orgId, callerId, targetUid);
    if (existing.length > 0) return { conversation: existing[0] };

    const conv = await createConv(db, {
      orgId,
      callerId,
      participantUids: [callerId, targetUid],
      status: 'approved',
    });
    return { conversation: conv };
  },

  async createGroup({ db, callerId, body }) {
    const { orgId } = body;
    requireStr(orgId, 'orgId');
    const name = cleanName(body.name, true);
    const memberUids = uniqStrings(body.memberUids);
    if (memberUids.length === 0 || memberUids.length > MAX_GROUP_MEMBERS) {
      throw new HttpError(400, 'Invalid memberUids');
    }

    const caller = await activeMember(db, orgId, callerId);
    if (!isSupervisor(caller)) throw new HttpError(403, 'Forbidden');
    const members = await loadMembers(db, orgId, memberUids);
    const invalid = memberUids.filter((u) => members[u]?.status !== 'active');
    if (invalid.length > 0) throw new HttpError(400, `Not active members: ${invalid.join(',')}`);

    const conv = await createConv(db, {
      orgId,
      callerId,
      participantUids: memberUids,
      status: 'approved',
      name,
      isGroup: true,
    });
    return { conversation: conv };
  },

  async approve({ db, callerId, body, log }) {
    const conv = await loadConv(db, body.convId);
    if (conv.status === 'approved') return {};
    const caller = await activeMember(db, conv.orgId, callerId);
    if (conv.status === 'pending') {
      await assertCanDecide(db, conv, caller, callerId);
    } else if (conv.status === 'archived') {
      if (!isSupervisor(caller)) throw new HttpError(403, 'Forbidden');
    } else {
      throw new HttpError(400, `Cannot approve conversation in status ${conv.status}`);
    }
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, {
      status: 'approved',
      approvedBy: callerId,
      approvedAt: new Date().toISOString(),
    });
    log(`approve: ${conv.$id} by ${callerId}`);
    return {};
  },

  async reject({ db, callerId, body, log }) {
    const conv = await loadConv(db, body.convId, true);
    if (!conv) return { alreadyGone: true };
    if (conv.status !== 'pending') throw new HttpError(400, 'Only pending requests can be rejected');
    const caller = await activeMember(db, conv.orgId, callerId);
    await assertCanDecide(db, conv, caller, callerId);
    // Team entsorgt sync-conversation-permissions beim delete-Event.
    await db.deleteDocument(DB_ID, COL_CONVS, conv.$id);
    log(`reject: ${conv.$id} by ${callerId}`);
    return {};
  },

  async archive({ db, callerId, body, log }) {
    const conv = await loadConv(db, body.convId);
    await requireSupervisor(db, conv.orgId, callerId);
    if (conv.status !== 'archived') {
      await db.updateDocument(DB_ID, COL_CONVS, conv.$id, { status: 'archived' });
    }
    log(`archive: ${conv.$id} by ${callerId}`);
    return {};
  },

  async updateGroupInfo({ db, callerId, body }) {
    const conv = await loadConv(db, body.convId);
    if (!conv.isGroup) throw new HttpError(400, 'Not a group');
    await requireSupervisor(db, conv.orgId, callerId);
    const updates = {};
    if (body.name !== undefined && body.name !== null) updates.name = cleanName(body.name, true);
    if (body.removeImage === true) {
      updates.imageUrl = null;
    } else if (body.imageUrl !== undefined && body.imageUrl !== null) {
      if (typeof body.imageUrl !== 'string' || body.imageUrl.length > 1000 ||
          !IMAGE_URL_RE.test(body.imageUrl)) {
        throw new HttpError(400, 'Invalid imageUrl');
      }
      updates.imageUrl = body.imageUrl;
    }
    if (Object.keys(updates).length > 0) {
      await db.updateDocument(DB_ID, COL_CONVS, conv.$id, updates);
    }
    return {};
  },

  async setPersonalName({ db, callerId, body }) {
    const conv = await loadConv(db, body.convId);
    if (conv.isGroup) throw new HttpError(400, 'Personal names only for direct chats');
    if (!(conv.participantUids ?? []).includes(callerId)) throw new HttpError(403, 'Forbidden');
    const name = cleanName(body.name ?? '', false);
    let names = {};
    try { names = JSON.parse(conv.personalNamesJson || '{}') ?? {}; } catch (_) { names = {}; }
    if (typeof names !== 'object' || Array.isArray(names)) names = {};
    if (name) names[callerId] = name; else delete names[callerId];
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, { personalNamesJson: JSON.stringify(names) });
    return {};
  },

  async pin({ db, callerId, body }) {
    const conv = await loadConv(db, body.convId);
    await requireSupervisor(db, conv.orgId, callerId);
    requireStr(body.msgId, 'msgId');
    let msg;
    try {
      msg = await db.getDocument(DB_ID, COL_MESSAGES, body.msgId);
    } catch (_) {
      throw new HttpError(404, 'Message not found');
    }
    if (msg.convId !== conv.$id) throw new HttpError(400, 'Message belongs to another conversation');
    if (msg.isDeleted) throw new HttpError(400, 'Message is deleted');
    const text = String(msg.text ?? '');
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, {
      pinnedMessageId: msg.$id,
      pinnedMessageText: text.length > 120 ? `${text.substring(0, 120)}…` : text,
    });
    return {};
  },

  async unpin({ db, callerId, body }) {
    const conv = await loadConv(db, body.convId);
    await requireSupervisor(db, conv.orgId, callerId);
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, {
      pinnedMessageId: null,
      pinnedMessageText: null,
    });
    return {};
  },

  async addMembers({ db, callerId, body, log }) {
    const conv = await loadConv(db, body.convId);
    if (!conv.isGroup) throw new HttpError(400, 'Not a group');
    await requireSupervisor(db, conv.orgId, callerId);
    const current = conv.participantUids ?? [];
    const uids = uniqStrings(body.uids).filter((u) => !current.includes(u));
    if (uids.length === 0) return { addedNames: [] };
    if (current.length + uids.length > MAX_GROUP_MEMBERS) throw new HttpError(400, 'Group too large');

    const members = await loadMembers(db, conv.orgId, uids);
    const invalid = uids.filter((u) => members[u]?.status !== 'active');
    if (invalid.length > 0) throw new HttpError(400, `Not active members: ${invalid.join(',')}`);

    const participantUids = [...current, ...uids];
    const guardianUids = await computeGuardians(db, conv.orgId, participantUids);
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, { participantUids, guardianUids });
    log(`addMembers: ${uids.join(',')} → ${conv.$id} by ${callerId}`);
    return { addedNames: uids.map((u) => members[u]?.displayName).filter(Boolean) };
  },

  async removeMember({ db, callerId, body, log }) {
    const conv = await loadConv(db, body.convId);
    if (!conv.isGroup) throw new HttpError(400, 'Not a group');
    await requireSupervisor(db, conv.orgId, callerId);
    requireStr(body.uid, 'uid');
    const current = conv.participantUids ?? [];
    if (!current.includes(body.uid)) return {};
    const participantUids = current.filter((u) => u !== body.uid);
    const guardianUids = await computeGuardians(db, conv.orgId, participantUids);
    await db.updateDocument(DB_ID, COL_CONVS, conv.$id, { participantUids, guardianUids });
    log(`removeMember: ${body.uid} ← ${conv.$id} by ${callerId}`);
    return {};
  },
};

// ── Hilfsfunktionen ─────────────────────────────────────────────────────────

function requireStr(v, name) {
  if (typeof v !== 'string' || v.length === 0 || v.length > 64) {
    throw new HttpError(400, `${name} required`);
  }
}

function uniqStrings(arr) {
  if (!Array.isArray(arr)) return [];
  return [...new Set(arr.filter((v) => typeof v === 'string' && v.length > 0 && v.length <= 64))];
}

function cleanName(raw, required) {
  if (typeof raw !== 'string') throw new HttpError(400, 'Invalid name');
  const name = raw.trim();
  if (required && name.length === 0) throw new HttpError(400, 'Name required');
  if (name.length > MAX_NAME) throw new HttpError(400, 'Name too long');
  return name;
}

function isSupervisor(member) {
  return member?.role === 'admin' || member?.role === 'moderator';
}

async function activeMember(db, orgId, uid, msg = 'Not an active member of this organization') {
  let m;
  try {
    m = await db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${uid}`);
  } catch (_) {
    throw new HttpError(403, msg);
  }
  if (m.orgId !== orgId || m.uid !== uid || (m.status ?? 'active') !== 'active') {
    throw new HttpError(403, msg);
  }
  return m;
}

async function requireSupervisor(db, orgId, uid) {
  const m = await activeMember(db, orgId, uid);
  if (!isSupervisor(m)) throw new HttpError(403, 'Forbidden');
  return m;
}

async function loadConv(db, convId, allowMissing = false) {
  requireStr(convId, 'convId');
  try {
    return await db.getDocument(DB_ID, COL_CONVS, convId);
  } catch (e) {
    if (allowMissing && e?.code === 404) return null;
    throw new HttpError(404, 'Conversation not found');
  }
}

async function loadMembers(db, orgId, uids) {
  const docs = await Promise.all(
    uids.map((u) => db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${u}`).catch(() => null)),
  );
  const map = {};
  for (const d of docs) if (d && d.orgId === orgId) map[d.uid] = d;
  return map;
}

/** Guardians aller Teilnehmer — immer aus den (server-gepflegten) Member-Docs. */
async function computeGuardians(db, orgId, participantUids) {
  const members = await loadMembers(db, orgId, participantUids);
  return [...new Set(Object.values(members).flatMap((m) => m.guardianUids ?? []))];
}

/**
 * Anfrage entscheiden (genehmigen/ablehnen) dürfen Admin/Mod sowie Guardians
 * eines Teilnehmers — nicht der Anfragende selbst (außer er ist Aufsicht).
 */
async function assertCanDecide(db, conv, caller, callerId) {
  if (isSupervisor(caller)) return;
  const guardians = await computeGuardians(db, conv.orgId, conv.participantUids ?? []);
  if (guardians.includes(callerId) && conv.requestedBy !== callerId) return;
  throw new HttpError(403, 'Forbidden');
}

async function findDirect(db, orgId, uidA, uidB) {
  const result = await db.listDocuments(DB_ID, COL_CONVS, [
    Query.equal('orgId', orgId),
    Query.contains('participantUids', [uidA]),
    Query.limit(500),
  ]);
  return result.documents.filter(
    (c) => !c.isGroup && (c.participantUids ?? []).includes(uidB),
  );
}

async function createConv(db, { orgId, callerId, participantUids, status, name, isGroup = false,
  requestorGuardianUid = null }) {
  const org = await db.getDocument(DB_ID, COL_ORGS, orgId);
  const mods = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', ['admin', 'moderator']),
    Query.limit(200),
  ]);
  // Nur aktive Admins/Moderatoren laut Member-Docs — org.adminUid ist bis
  // Phase 2 client-beschreibbar (Release-Review 182, K3).
  const canApproveUids = [...new Set(mods.documents
    .filter((d) => (d.status ?? 'active') === 'active')
    .map((d) => d.uid))].filter(Boolean);
  const guardianUids = await computeGuardians(db, orgId, participantUids);
  const now = new Date().toISOString();

  const data = {
    orgId,
    orgAdminUid: org.adminUid,
    participantUids,
    requestedBy: callerId,
    status,
    createdAt: now,
    isGroup,
    canApproveUids,
    guardianUids,
    personalNamesJson: '{}',
  };
  if (requestorGuardianUid) data.requestorGuardianUid = requestorGuardianUid;
  if (name) data.name = name;
  if (status === 'approved') {
    data.approvedBy = callerId;
    data.approvedAt = now;
  }

  const convId = ID.unique();
  // Der Aufrufer liest sofort mit; sync-conversation-permissions legt danach
  // das Conv-Team an und setzt die ACL auf `read team(convId)`.
  const doc = await db.createDocument(DB_ID, COL_CONVS, convId, data, [
    Permission.read(Role.team(convId)),
    Permission.read(Role.user(callerId)),
  ]);
  return doc;
}
