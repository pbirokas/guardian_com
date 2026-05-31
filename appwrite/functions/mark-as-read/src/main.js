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

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  let conv;
  try {
    conv = await db.getDocument(DB_ID, COL_CONVS, convId);
  } catch (_) {
    return res.json({ error: 'Conversation not found' }, 404);
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
  const existing = conv.lastReadAtJson ? JSON.parse(conv.lastReadAtJson) : {};
  const effectiveReadAt = readAt ?? new Date().toISOString();
  existing[uid] = effectiveReadAt;

  await db.updateDocument(DB_ID, COL_CONVS, convId, {
    lastReadAtJson: JSON.stringify(existing),
  });

  log(`mark-as-read: uid=${uid} convId=${convId} readAt=${effectiveReadAt}`);
  return res.json({ ok: true });
};
