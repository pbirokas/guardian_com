const { Client, Databases } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVS = 'conversations';

module.exports = async ({ req, res, log, error }) => {
  const uid = req.headers['x-appwrite-user-id'];
  if (!uid) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const { convId, readAt } = body;
  if (!convId || typeof convId !== 'string') {
    return res.json({ error: 'convId required' }, 400);
  }

  // readAt muss ein gültiger ISO-8601-Timestamp sein und darf nicht mehr als
  // 60s in der Zukunft liegen (Toleranz für Clock-Drift zwischen Geräten).
  let effectiveReadAt;
  if (readAt != null) {
    const parsed = new Date(readAt);
    if (isNaN(parsed.getTime()) || parsed > new Date(Date.now() + 60_000)) {
      return res.json({ error: 'Invalid readAt' }, 400);
    }
    effectiveReadAt = parsed.toISOString();
  } else {
    effectiveReadAt = new Date().toISOString();
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  let conv;
  try {
    conv = await db.getDocument(DB_ID, COL_CONVS, convId);
  } catch (e) {
    const code = e?.code ?? e?.status ?? 0;
    error(`getDocument failed: code=${code} msg=${e?.message}`);
    if (code === 404) return res.json({ error: 'Conversation not found' }, 404);
    return res.json({ error: 'Internal server error' }, 500);
  }

  // Nur Teilnehmer, Guardians und berechtigte Approver dürfen als gelesen markieren.
  const allowed = [
    ...(conv.participantUids ?? []),
    ...(conv.guardianUids ?? []),
    ...(conv.canApproveUids ?? []),
  ];
  if (!allowed.includes(uid)) {
    return res.json({ error: 'Not a participant' }, 403);
  }

  // Nur den eigenen Eintrag aktualisieren — kein anderer UID wird berührt.
  let existing = {};
  try {
    existing = conv.lastReadAtJson ? JSON.parse(conv.lastReadAtJson) : {};
  } catch (_) { /* korrupter Wert → leere Map als Fallback */ }

  existing[uid] = effectiveReadAt;

  try {
    await db.updateDocument(DB_ID, COL_CONVS, convId, {
      lastReadAtJson: JSON.stringify(existing),
    });
  } catch (e) {
    const code = e?.code ?? e?.status ?? 0;
    error(`updateDocument failed: code=${code} msg=${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }

  log(`mark-as-read: uid=${uid} convId=${convId} readAt=${effectiveReadAt}`);
  return res.json({ ok: true });
};
