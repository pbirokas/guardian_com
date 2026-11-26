/**
 * delete-account — Konto eines Nutzers komplett serverseitig löschen.
 *
 * Warum eine Function: users-, members- und conversations-Docs sind für
 * Clients nur lesbar, fremde Nachrichten/Medien sowieso — die Löschung muss
 * mit API-Key laufen. Eigene Function (statt self-service-Aktion), weil ein
 * Lauf lange dauern kann (Timeout 900 s statt 15 s).
 *
 * Aufrufe:
 *  - { action: 'check' }  (synchron, App) → { ok, blockers: [{ code, orgId?, orgName? }] }
 *      codes: childHasParents | parentHasChildren | orgAdmin
 *  - { action: 'start' }  (synchron, App) → prüft die Sperren erneut, setzt
 *      users.deletionStatus = 'deleting' und stößt den eigentlichen Lauf
 *      ASYNCHRON an (eine synchrone Execution, die die API zurückruft, kann
 *      einen API-Worker blockieren — siehe CLAUDE.md). → { ok, started }
 *      Gesperrt: 409 { error: 'blocked', blockers }.
 *  - { action: 'run', uid } (nur intern: ohne Nutzer-Header, per API-Key von
 *      'start' bzw. einem vorigen Lauf angestoßen) → arbeitet nur, wenn
 *      users/{uid}.deletionStatus === 'deleting' (das setzt allein 'start').
 *  - Schedule (alle 15 min): setzt hängengebliebene Löschungen fort.
 *
 * Jeder Schritt ist idempotent (sucht per uid/senderUid, 404 = erledigt);
 * ein Lauf hört nach RUN_BUDGET_MS auf und stößt sich selbst erneut an.
 * Reihenfolge: Org-Anonymisierung → Chats → Rest → Member-Docs → Auth-Konto
 * (beendet Sessions, Appwrite entfernt die Team-Mitgliedschaften) → zuletzt
 * das users-Doc (sonst legte `ensureUserDoc` es bei einem App-Start neu an).
 *
 * Was passiert (abgestimmt 2026-11-26):
 *  - 1:1-Chats werden komplett gelöscht (inkl. Nachrichten/Medien des Partners).
 *  - Gruppen: eigene Nachrichten bleiben als leerer Platzhalter von
 *    „Gelöschter Nutzer“ (Text, Medien, Reaktionen, Zitat weg); eigene Polls
 *    gelöscht, eigene Stimmen/Reaktionen bei anderen entfernt; Austritt.
 *  - Orgs, in denen der Nutzer einziges aktives Mitglied ist: komplett gelöscht.
 *    Admin einer Org mit weiteren Mitgliedern: gesperrt (erst übertragen).
 *  - Guardian von Kindern: UID entfernt; ein Kind ohne Guardian zeigt die App
 *    Admins/Mods als „Aktion erforderlich“ im Mitglieder-Tab.
 *  - Audit-Log, Meldungen, Einladungen, Pinnwand: Name → „Gelöschter Nutzer“,
 *    gemeldeter Nachrichtentext geleert.
 *  - read_receipts, scheduled_messages, claim_requests, offene Einladungen an
 *    die eigene E-Mail, Eltern-Zustimmungen: gelöscht bzw. UID entfernt.
 */

const { Client, Databases, Users, Storage, Functions, Query } = require('node-appwrite');

const FUNCTION_ID = 'delete-account';
const DB_ID = 'guardian';
const BUCKET_MEDIA = '6a02e524000954c9f1de';
const COL = {
  users: 'users',
  members: 'members',
  orgs: 'organizations',
  convs: 'conversations',
  messages: 'chat_messages',
  polls: 'polls',
  scheduled: 'scheduled_messages',
  receipts: 'read_receipts',
  announcements: 'announcements',
  invitations: 'invitations',
  consents: 'org_invite_consents',
  audit: 'audit_log',
  reports: 'reports',
  claims: 'claim_requests',
};

/** Muss zu `kDeletedUserName` in guardian_app/lib/core/models/message.dart passen. */
const DELETED_NAME = 'Gelöschter Nutzer';
const RUN_BUDGET_MS = 10 * 60 * 1000;   // Timeout der Function: 900 s
const RESUME_AFTER_MS = 15 * 60 * 1000; // Schedule übernimmt erst danach
const PAGE = 100;

class OutOfTime extends Error {}

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
  const ctx = {
    db: new Databases(client),
    users: new Users(client),
    storage: new Storage(client),
    functions: new Functions(client),
    log,
    error,
    deadline: Date.now() + RUN_BUDGET_MS,
  };

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const callerId = req.headers['x-appwrite-user-id'];

  try {
    if (req.headers['x-appwrite-trigger'] === 'schedule') {
      await resumeStale(ctx);
      return res.json({ ok: true });
    }

    if (!callerId) {
      // Interne Fortsetzung. Ohne Session kann niemand sonst ausführen
      // (execute: users); zusätzlich arbeitet runDeletion nur, wenn der
      // Nutzer selbst per 'start' die Löschung beantragt hat.
      if (body.action === 'run' && typeof body.uid === 'string' && body.uid) {
        await runDeletion(ctx, body.uid);
        return res.json({ ok: true });
      }
      return res.json({ error: 'Unauthenticated' }, 401);
    }

    if (body.action === 'check') {
      const user = await getOrNull(ctx.db, COL.users, callerId);
      return res.json({ ok: true, blockers: await findBlockers(ctx, callerId, user) });
    }

    if (body.action === 'start') {
      const user = await getOrNull(ctx.db, COL.users, callerId);
      if (user?.deletionStatus !== 'deleting') {
        const blockers = await findBlockers(ctx, callerId, user);
        if (blockers.length > 0) return res.json({ error: 'blocked', blockers }, 409);
        if (!user) {
          // Ohne users-Doc fände der Schedule die Löschung nicht wieder —
          // gibt es praktisch nicht (ensureUserDoc beim Login); dann inline.
          await runDeletion(ctx, callerId, { force: true });
          return res.json({ ok: true, started: true });
        }
        await ctx.db.updateDocument(DB_ID, COL.users, callerId, {
          deletionStatus: 'deleting',
          deletionRequestedAt: new Date().toISOString(),
        });
        log(`start: deletion of ${callerId} requested`);
      }
      await enqueueRun(ctx, callerId);
      return res.json({ ok: true, started: true });
    }

    return res.json({ error: `Unknown action: ${body.action}` }, 400);
  } catch (e) {
    error(`delete-account ${body.action ?? 'schedule'} failed: ${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }
};

// ── Sperren ─────────────────────────────────────────────────────────────────

async function findBlockers(ctx, uid, user) {
  const blockers = [];
  if (user?.isChild && (user.verifiedParentUids ?? []).length > 0) {
    blockers.push({ code: 'childHasParents' });
  }
  if ((user?.verifiedChildUids ?? []).length > 0) {
    blockers.push({ code: 'parentHasChildren' });
  }
  for (const org of await adminOrgs(ctx, uid)) {
    if (org.hasOthers) blockers.push({ code: 'orgAdmin', orgId: org.id, orgName: org.name });
  }
  return blockers;
}

/**
 * Orgs, in denen uid Admin ist (org.adminUid oder Member-Rolle admin), mit
 * der Angabe, ob es weitere aktive Mitglieder gibt. Ausstehende Kind-
 * Einladungen zählen nicht — die verschwinden mit der Org.
 */
async function adminOrgs(ctx, uid) {
  const { db } = ctx;
  const ids = new Set();
  for (const o of await listAll(db, COL.orgs, [Query.equal('adminUid', uid)])) ids.add(o.$id);
  for (const m of await listAll(db, COL.members, [Query.equal('uid', uid)])) {
    if (m.role === 'admin') ids.add(m.orgId);
  }
  const result = [];
  for (const id of ids) {
    const org = await getOrNull(db, COL.orgs, id);
    if (!org) continue;
    const { documents } = await db.listDocuments(DB_ID, COL.members, [
      Query.equal('orgId', id), Query.notEqual('uid', uid), Query.limit(PAGE),
    ]);
    const others = documents.filter((m) => m.uid !== uid);
    const hasOthers = others.some((m) => (m.status ?? 'active') !== 'pending') ||
      documents.length >= PAGE; // vorsichtig: mehr als eine Seite → nicht „allein“
    result.push({ id, name: org.name ?? '', hasOthers });
  }
  return result;
}

// ── Läufe ───────────────────────────────────────────────────────────────────

async function enqueueRun(ctx, uid) {
  try {
    await ctx.functions.createExecution(FUNCTION_ID, JSON.stringify({ action: 'run', uid }), true);
  } catch (e) {
    // Nicht fatal: der Schedule setzt die Löschung spätestens in 15 min fort.
    ctx.error(`enqueueRun(${uid}) failed: ${e?.message}`);
  }
}

async function resumeStale(ctx) {
  const pending = await listAll(ctx.db, COL.users, [Query.equal('deletionStatus', 'deleting')]);
  const now = Date.now();
  for (const u of pending) {
    const last = u.deletionRunAt ? new Date(u.deletionRunAt).getTime() : 0;
    if (now - last < RESUME_AFTER_MS) continue; // läuft vermutlich noch
    ctx.log(`resume: deletion of ${u.$id}`);
    await runDeletion(ctx, u.$id);
    if (Date.now() > ctx.deadline) break;
  }
}

/**
 * Ein Lauf. Bricht bei Zeitablauf ab und stößt sich selbst neu an.
 * `force`: ohne users-Doc (nur aus 'start').
 */
async function runDeletion(ctx, uid, { force = false } = {}) {
  const { db, log } = ctx;
  const user = await getOrNull(db, COL.users, uid);
  if (!force && user?.deletionStatus !== 'deleting') {
    log(`run: ${uid} not marked for deletion — skipped`);
    return;
  }
  if (user) await db.updateDocument(DB_ID, COL.users, uid, { deletionRunAt: new Date().toISOString() });

  // Sperren erneut prüfen: zwischen 'start' und Lauf kann jemand einer Org
  // beigetreten sein. Dann nichts weiter löschen und den Status zurücksetzen.
  const blockers = await findBlockers(ctx, uid, user);
  if (blockers.length > 0) {
    if (user) await db.updateDocument(DB_ID, COL.users, uid, { deletionStatus: 'blocked' });
    log(`run: ${uid} blocked (${blockers.map((b) => b.code).join(',')})`);
    return;
  }

  try {
    await deleteEverything(ctx, uid, user);
    log(`run: account ${uid} deleted`);
  } catch (e) {
    if (!(e instanceof OutOfTime)) throw e;
    log(`run: ${uid} paused (time budget) — re-enqueued`);
    await enqueueRun(ctx, uid);
  }
}

function tick(ctx) {
  if (Date.now() > ctx.deadline) throw new OutOfTime();
}

// ── Die eigentliche Löschung ────────────────────────────────────────────────

async function deleteEverything(ctx, uid, user) {
  const { db, users } = ctx;
  const displayName = user?.displayName ?? '';
  const email = String(user?.email ?? '').toLowerCase();

  // 1. Orgs, in denen der Nutzer allein ist, komplett löschen.
  for (const org of await adminOrgs(ctx, uid)) {
    if (!org.hasOthers) await deleteOrgCompletely(ctx, org.id);
  }

  const memberDocs = await listAll(db, COL.members, [Query.equal('uid', uid)]);
  const orgIds = [...new Set(memberDocs.map((m) => m.orgId))];

  // 2. Org-weite Daten anonymisieren (vor dem Löschen der 1:1-Chats: Meldungen
  //    brauchen die gemeldete Nachricht, um den Absender zu prüfen).
  for (const orgId of orgIds) {
    tick(ctx);
    await anonymizeOrgData(ctx, orgId, uid, displayName);
  }

  // 3. Chats, in denen der Nutzer Teilnehmer ist.
  for (const conv of await listAll(db, COL.convs, [Query.contains('participantUids', [uid])])) {
    tick(ctx);
    if (conv.isGroup) await leaveGroup(ctx, conv, uid);
    else await deleteConversationCompletely(ctx, conv.$id);
  }

  // 4. Was übrig ist (Gruppen, die er früher verlassen hat; verwaiste Docs).
  await forEachPage(ctx, COL.messages, [Query.equal('senderUid', uid)], async (msg) => {
    await anonymizeOwnMessage(ctx, msg, uid);
  });
  await deleteAll(ctx, COL.polls, [Query.equal('createdBy', uid)]);
  await deleteAll(ctx, COL.receipts, [Query.equal('uid', uid)]);
  await deleteAll(ctx, COL.scheduled, [Query.equal('senderUid', uid)]);
  await deleteAll(ctx, COL.claims, [Query.equal('fromUid', uid)]);
  await deleteAll(ctx, COL.claims, [Query.equal('toUid', uid)]);
  if (email) await deleteAll(ctx, COL.invitations, [Query.equal('email', email)]);
  await deleteAll(ctx, COL.consents, [Query.equal('childUid', uid)]);
  await forEachPage(ctx, COL.consents, [Query.contains('parentUids', [uid])], async (c) => {
    const parentUids = (c.parentUids ?? []).filter((u) => u !== uid);
    if (parentUids.length === 0 && (c.status ?? 'pending') === 'pending') {
      await del(db, COL.consents, c.$id);
    } else {
      await db.updateDocument(DB_ID, COL.consents, c.$id, { parentUids });
    }
  });

  // 5. Profilbild (nur wenn der Nutzer es selbst hochgeladen hat).
  if (user?.photoUrl) await deleteOwnFile(ctx, user.photoUrl, uid);

  // 6. Eigene Member-Docs + org.memberUids.
  for (const m of memberDocs) {
    tick(ctx);
    await del(db, COL.members, m.$id);
    const org = await getOrNull(db, COL.orgs, m.orgId);
    if (org && (org.memberUids ?? []).includes(uid)) {
      await db.updateDocument(DB_ID, COL.orgs, org.$id, {
        memberUids: org.memberUids.filter((u) => u !== uid),
      });
    }
  }

  // 7. Auth-Konto (Sessions + Team-Mitgliedschaften), dann users-Doc.
  try {
    await users.delete(uid);
  } catch (e) {
    if (e?.code !== 404) throw e;
  }
  await del(db, COL.users, uid);
}

/** Audit-Log, Meldungen, Einladungen, Zustimmungen, Pinnwand, Guardian-Rollen. */
async function anonymizeOrgData(ctx, orgId, uid, displayName) {
  const { db } = ctx;
  const byOrg = [Query.equal('orgId', orgId)];

  await forEachPage(ctx, COL.audit, byOrg, async (a) => {
    if (a.actorUid === uid && a.actorName !== DELETED_NAME) {
      await db.updateDocument(DB_ID, COL.audit, a.$id, { actorName: DELETED_NAME });
    }
  });

  await forEachPage(ctx, COL.reports, byOrg, async (r) => {
    if (!r.msgId || (r.messageSenderName === DELETED_NAME && !r.messageText)) return;
    const msg = await getOrNull(db, COL.messages, r.msgId);
    // Nachricht noch da → Absender prüfen; schon weg (Löschzeitraum) → über
    // den Namen zuordnen (Meldungen speichern keine Absender-UID).
    const isOwn = msg ? msg.senderUid === uid : (!!displayName && r.messageSenderName === displayName);
    if (!isOwn) return;
    await db.updateDocument(DB_ID, COL.reports, r.$id, { messageSenderName: DELETED_NAME, messageText: '' });
  });

  await forEachPage(ctx, COL.invitations, byOrg, async (i) => {
    if (i.invitedByUid === uid && i.inviterName !== DELETED_NAME) {
      await db.updateDocument(DB_ID, COL.invitations, i.$id, { inviterName: DELETED_NAME });
    }
  });

  await forEachPage(ctx, COL.consents, byOrg, async (c) => {
    if (c.invitedByUid === uid && c.invitedByName !== DELETED_NAME) {
      await db.updateDocument(DB_ID, COL.consents, c.$id, { invitedByName: DELETED_NAME });
    }
  });

  await forEachPage(ctx, COL.announcements, byOrg, async (a) => {
    const updates = {};
    if (a.authorUid === uid && a.authorName !== DELETED_NAME) updates.authorName = DELETED_NAME;
    const reactions = withoutKey(a.reactionsJson, uid);
    if (reactions !== null) updates.reactionsJson = reactions;
    const rsvp = withoutKey(a.rsvpJson, uid);
    if (rsvp !== null) updates.rsvpJson = rsvp;
    if (Object.keys(updates).length > 0) await db.updateDocument(DB_ID, COL.announcements, a.$id, updates);
  });

  // Guardian-Rolle bei Kindern abgeben. on-member-guardians-changed zieht das
  // in die Chats nach; ein Kind ohne Guardian markiert die App als
  // „Aktion erforderlich“ (abgestimmt: nicht sperren).
  await forEachPage(ctx, COL.members, byOrg, async (m) => {
    if (m.uid === uid || !(m.guardianUids ?? []).includes(uid)) return;
    await db.updateDocument(DB_ID, COL.members, m.$id, {
      guardianUids: m.guardianUids.filter((u) => u !== uid),
    });
  });
}

/**
 * Gruppe verlassen: eigene Nachrichten → Platzhalter, eigene Reaktionen und
 * Zitate eigener Nachrichten bei anderen entfernen, eigene Polls löschen,
 * Stimmen entfernen, Pin/Vorschau bereinigen, dann aus participantUids.
 * Der Austritt kommt zuletzt — bis dahin findet ein Folgelauf die Gruppe wieder.
 */
async function leaveGroup(ctx, conv, uid) {
  const { db } = ctx;
  const ownIds = new Set();
  let newest = null;

  await forEachPage(ctx, COL.messages, [Query.equal('convId', conv.$id)], async (msg) => {
    if (!newest || String(msg.sentAt) > String(newest.sentAt)) newest = msg;
    if (msg.senderUid === uid) {
      ownIds.add(msg.$id);
      await anonymizeOwnMessage(ctx, msg, uid);
      return;
    }
    const updates = {};
    const reactions = withoutKey(msg.reactionsJson, uid);
    if (reactions !== null) updates.reactionsJson = reactions;
    if (msg.replyToId && ownIds.has(msg.replyToId) &&
        (msg.replyToText || msg.replyToSenderName !== DELETED_NAME)) {
      updates.replyToText = '';
      updates.replyToSenderName = DELETED_NAME;
    }
    if (Object.keys(updates).length > 0) await db.updateDocument(DB_ID, COL.messages, msg.$id, updates);
  });

  await forEachPage(ctx, COL.polls, [Query.equal('convId', conv.$id)], async (poll) => {
    if (poll.createdBy === uid) return del(db, COL.polls, poll.$id);
    const votes = withoutVoter(poll.votesJson, uid);
    if (votes !== null) await db.updateDocument(DB_ID, COL.polls, poll.$id, { votesJson: votes });
  });
  await deleteAll(ctx, COL.scheduled, [Query.equal('convId', conv.$id), Query.equal('senderUid', uid)]);

  const participantUids = (conv.participantUids ?? []).filter((u) => u !== uid);
  const updates = {
    participantUids,
    guardianUids: await computeGuardians(db, conv.orgId, participantUids),
  };
  if (conv.pinnedMessageId && ownIds.has(conv.pinnedMessageId)) {
    updates.pinnedMessageId = null;
    updates.pinnedMessageText = null;
  }
  if (newest && newest.senderUid === uid) updates.lastMessage = '';
  await db.updateDocument(DB_ID, COL.convs, conv.$id, updates);
}

async function anonymizeOwnMessage(ctx, msg, uid) {
  const { db } = ctx;
  if (msg.type === 'system') {
    if (msg.senderName === DELETED_NAME) return;
    await db.updateDocument(DB_ID, COL.messages, msg.$id, {
      senderName: DELETED_NAME,
      ...(msg.systemActorName ? { systemActorName: DELETED_NAME } : {}),
    });
    return;
  }
  if (msg.senderName === DELETED_NAME && msg.deletedAt && !msg.text) return;
  await deleteMessageFiles(ctx, msg);
  await db.updateDocument(DB_ID, COL.messages, msg.$id, {
    text: '',
    senderName: DELETED_NAME,
    imageUrl: null,
    imageUrls: [],
    audioUrl: null,
    audioDurationMs: null,
    fileUrl: null,
    fileName: null,
    fileSizeBytes: null,
    isGif: false,
    pollId: null,
    replyToId: null,
    replyToSenderName: null,
    replyToText: null,
    reactionsJson: '{}',
    editedAt: null,
    deletedAt: msg.deletedAt ?? new Date().toISOString(),
    deletedBy: uid,
  });
}

/** Wie admin-member-action/deleteConversation. Team entsorgt sync-conversation-permissions. */
async function deleteConversationCompletely(ctx, convId) {
  const { db } = ctx;
  await forEachPage(ctx, COL.messages, [Query.equal('convId', convId)], async (msg) => {
    await deleteMessageFiles(ctx, msg);
    await del(db, COL.messages, msg.$id);
  });
  await deleteAll(ctx, COL.polls, [Query.equal('convId', convId)]);
  await deleteAll(ctx, COL.scheduled, [Query.equal('convId', convId)]);
  await deleteAll(ctx, COL.receipts, [Query.equal('convId', convId)]);
  await del(db, COL.convs, convId);
}

/** Wie admin-member-action/deleteOrg (Org, in der der Nutzer allein ist). */
async function deleteOrgCompletely(ctx, orgId) {
  const { db } = ctx;
  await db.updateDocument(DB_ID, COL.orgs, orgId, { deletionStatus: 'deleting' }).catch(() => {});
  for (const conv of await listAll(db, COL.convs, [Query.equal('orgId', orgId)])) {
    tick(ctx);
    await deleteConversationCompletely(ctx, conv.$id);
  }
  const byOrg = [Query.equal('orgId', orgId)];
  for (const c of [COL.announcements, COL.invitations, COL.consents, COL.audit, COL.reports, COL.members]) {
    await deleteAll(ctx, c, byOrg);
  }
  await del(db, COL.orgs, orgId);
  ctx.log(`deleted solo org ${orgId}`);
}

// ── Hilfsfunktionen ─────────────────────────────────────────────────────────

async function computeGuardians(db, orgId, participantUids) {
  const docs = await Promise.all(participantUids.map((u) =>
    db.getDocument(DB_ID, COL.members, `${orgId}_${u}`).catch(() => null)));
  return [...new Set(docs.filter((d) => d && d.orgId === orgId).flatMap((d) => d.guardianUids ?? []))];
}

/** JSON-Map ohne Schlüssel uid; null, wenn uid nicht drin war. */
function withoutKey(raw, uid) {
  const map = parseObject(raw);
  if (!map || !(uid in map)) return null;
  delete map[uid];
  return JSON.stringify(map);
}

/** votesJson (Map<optionId, uid[]>) ohne uid; null, wenn uid nicht abgestimmt hat. */
function withoutVoter(raw, uid) {
  const map = parseObject(raw);
  if (!map) return null;
  let changed = false;
  for (const [k, v] of Object.entries(map)) {
    if (Array.isArray(v) && v.includes(uid)) {
      map[k] = v.filter((u) => u !== uid);
      changed = true;
    }
  }
  return changed ? JSON.stringify(map) : null;
}

function parseObject(raw) {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' && !Array.isArray(v) ? v : null;
  } catch (_) {
    return null;
  }
}

async function getOrNull(db, col, id) {
  try {
    return await db.getDocument(DB_ID, col, id);
  } catch (e) {
    if (e?.code === 404) return null;
    throw e;
  }
}

async function del(db, col, id) {
  try {
    await db.deleteDocument(DB_ID, col, id);
  } catch (e) {
    if (e?.code !== 404) throw e;
  }
}

/** Alle Treffer (Cursor-Paging) — für kleine Mengen (Orgs, Member-Docs, Chats). */
async function listAll(db, col, queries) {
  const out = [];
  let cursor = null;
  while (true) {
    const q = [...queries, Query.limit(PAGE)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const { documents } = await db.listDocuments(DB_ID, col, q);
    out.push(...documents);
    if (documents.length < PAGE) return out;
    cursor = documents[documents.length - 1].$id;
  }
}

/** Seitenweise verarbeiten (Docs bleiben bestehen → Cursor), mit Zeitprüfung. */
async function forEachPage(ctx, col, queries, fn) {
  let cursor = null;
  while (true) {
    tick(ctx);
    const q = [...queries, Query.limit(PAGE)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const { documents } = await ctx.db.listDocuments(DB_ID, col, q);
    for (const d of documents) await fn(d);
    if (documents.length < PAGE) return;
    cursor = documents[documents.length - 1].$id;
  }
}

/** Alle Treffer löschen (ohne Cursor: gelöschte Docs fallen aus dem Ergebnis). */
async function deleteAll(ctx, col, queries) {
  while (true) {
    tick(ctx);
    const { documents } = await ctx.db.listDocuments(DB_ID, col, [...queries, Query.limit(PAGE)]);
    if (documents.length === 0) return;
    await Promise.all(documents.map((d) => del(ctx.db, col, d.$id)));
    if (documents.length < PAGE) return;
  }
}

/**
 * Mediendateien einer Nachricht löschen — nur Dateien, die der Autor (laut
 * Dokument-ACL, nicht laut `senderUid`) selbst hochgeladen hat. Wie in
 * admin-member-action; beide Bildfelder (imageUrl + imageUrls).
 */
async function deleteMessageFiles(ctx, msg) {
  const authors = (msg.$permissions ?? [])
    .map((p) => p.match(/^(?:update|delete)\("user:([^"/]+)/)?.[1])
    .filter(Boolean);
  const urls = [msg.imageUrl, ...(msg.imageUrls ?? []), msg.audioUrl, msg.fileUrl].filter(Boolean);
  await Promise.allSettled([...new Set(urls)].map((url) => deleteOwnFile(ctx, url, authors)));
}

/** Datei hinter einer View-URL löschen, wenn einer der owner sie hochgeladen hat. */
async function deleteOwnFile(ctx, url, owners) {
  const list = [].concat(owners).filter(Boolean);
  const id = String(url).match(/\/files\/([^/?]+)\/view/)?.[1];
  if (!id || list.length === 0) return;
  try {
    const file = await ctx.storage.getFile(BUCKET_MEDIA, id);
    const allowed = list.map((u) => `delete("user:${u}")`);
    if (!(file.$permissions ?? []).some((p) => allowed.includes(p))) return;
    await ctx.storage.deleteFile(BUCKET_MEDIA, id);
  } catch (e) {
    if (e?.code !== 404) ctx.error(`deleteOwnFile ${id}: ${e?.message}`);
  }
}
