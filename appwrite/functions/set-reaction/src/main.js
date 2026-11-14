const { Client, Databases, Teams, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_MESSAGES = 'chat_messages';
const COL_ANNOUNCEMENTS = 'announcements';
const COL_MEMBERS = 'members';

const RSVP_VALUES = new Set(['yes', 'no', 'maybe']);
const MAX_EMOJI_LENGTH = 16;

/**
 * set-reaction — setzt/entfernt die EIGENE Reaktion bzw. Termin-Zusage des
 * Aufrufers auf einem fremden Dokument.
 *
 * Callable (kein Event-Trigger), vom Client asynchron aufgerufen
 * (`executeRaw(..., xasync: true)`); die Änderung kommt per Realtime zurück.
 *
 * Warum eine Function: Appwrite kennt keine Feld-Rechte. Damit jeder
 * Chat-Teilnehmer auf jede Nachricht reagieren kann, müsste die Nachrichten-ACL
 * sonst `update team(convId)` enthalten — dann könnte jeder Teilnehmer auch den
 * Text fremder Nachrichten ändern. Gleiches gilt für Ankündigungen.
 *
 * Body:
 *   { kind: 'message',      convId, docId, value: <emoji|null> }
 *   { kind: 'announcement', docId, value: <emoji|null> }
 *   { kind: 'rsvp',         docId, value: 'yes'|'no'|'maybe'|null }
 *
 * Sicherheit:
 *  - Aufrufer über x-appwrite-user-id (von Appwrite gesetzt)
 *  - message: Aufrufer muss Mitglied im Conversation-Team sein (= Leserecht)
 *  - announcement/rsvp: Aufrufer muss Mitglied der Org der Ankündigung sein
 *  - geschrieben wird ausschließlich der eigene Map-Eintrag (Key = callerId)
 */
module.exports = async ({ req, res, log, error }) => {
  const callerId = req.headers['x-appwrite-user-id'];
  if (!callerId) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body);
    } catch (_) {
      body = {};
    }
  }

  const { kind, convId, docId } = body;
  const value = body.value ?? null;
  if (!docId || !['message', 'announcement', 'rsvp'].includes(kind)) {
    return res.json({ error: 'kind and docId required' }, 400);
  }
  if (value !== null) {
    if (typeof value !== 'string' || value.length === 0) {
      return res.json({ error: 'Invalid value' }, 400);
    }
    if (kind === 'rsvp' && !RSVP_VALUES.has(value)) {
      return res.json({ error: 'Invalid rsvp value' }, 400);
    }
    if (kind !== 'rsvp' && value.length > MAX_EMOJI_LENGTH) {
      return res.json({ error: 'Emoji too long' }, 400);
    }
  }

  const client = new Client()
    .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);
  const teams = new Teams(client);

  const collection = kind === 'message' ? COL_MESSAGES : COL_ANNOUNCEMENTS;
  const field = kind === 'rsvp' ? 'rsvpJson' : 'reactionsJson';

  let doc;
  try {
    doc = await db.getDocument(DB_ID, collection, docId);
  } catch (_) {
    return res.json({ error: 'Not found' }, 404);
  }

  // ── Berechtigung ─────────────────────────────────────────────────────────
  if (kind === 'message') {
    if (!convId || doc.convId !== convId) {
      return res.json({ error: 'convId mismatch' }, 400);
    }
    if (!(await isTeamMember(teams, convId, callerId))) {
      return res.json({ error: 'Forbidden' }, 403);
    }
  } else {
    const orgId = doc.orgId;
    if (!orgId) return res.json({ error: 'Announcement has no orgId' }, 400);
    try {
      await db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${callerId}`);
    } catch (_) {
      return res.json({ error: 'Forbidden' }, 403);
    }
  }

  // ── Eigenen Eintrag setzen/entfernen ─────────────────────────────────────
  const map = parseJsonMap(doc[field]);
  if (value === null) {
    if (!(callerId in map)) return res.json({ ok: true, unchanged: true });
    delete map[callerId];
  } else {
    if (map[callerId] === value) return res.json({ ok: true, unchanged: true });
    map[callerId] = value;
  }

  try {
    await db.updateDocument(DB_ID, collection, docId, { [field]: JSON.stringify(map) });
  } catch (e) {
    error(`set-reaction ${kind} ${docId}: update failed: ${e.message}`);
    return res.json({ error: 'Update failed' }, 500);
  }

  log(`set-reaction: ${kind} ${docId} by ${callerId} → ${value ?? '(removed)'}`);
  return res.json({ ok: true });
};

async function isTeamMember(teams, teamId, uid) {
  try {
    const result = await teams.listMemberships(teamId, [
      Query.equal('userId', uid),
      Query.limit(1),
    ]);
    return (result.memberships ?? []).some((m) => m.userId === uid);
  } catch (e) {
    if (e.code === 404) return false; // Team existiert nicht
    // Fallback, falls der Server die userId-Query ablehnt: Mitglieder seitenweise prüfen.
    let offset = 0;
    while (true) {
      const page = await teams.listMemberships(teamId, [Query.limit(100), Query.offset(offset)]);
      const list = page.memberships ?? [];
      if (list.some((m) => m.userId === uid)) return true;
      if (list.length < 100) return false;
      offset += 100;
    }
  }
}

function parseJsonMap(raw) {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (_) {
    return {};
  }
}
