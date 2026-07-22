const { Client, Databases } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const COL_MESSAGES = 'chat_messages';

/**
 * moderate-message — privilegierte Moderation einer FREMDEN Nachricht.
 *
 * Callable (kein Event-Trigger). Der Client ruft dies nur, wenn ein
 * Admin/Moderator eine Nachricht eines anderen Mitglieds archiviert. Der Autor
 * bearbeitet/löscht seine eigenen Nachrichten weiterhin direkt (per user:self).
 *
 * Sicherheit:
 *  - Aufrufer über x-appwrite-user-id (von Appwrite gesetzt)
 *  - Rolle serverseitig gegen members-Doc `${orgId}_${uid}` geprüft
 *  - Schreibzugriff mit API-Key (Nachrichten-ACL erlaubt sonst nur den Autor)
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

  const { convId, msgId, newText, archivedByName } = body;
  if (!convId || !msgId || typeof newText !== 'string') {
    return res.json({ error: 'convId, msgId, newText required' }, 400);
  }

  const client = new Client()
    .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Nachricht laden und Zugehörigkeit prüfen.
  let msg;
  try {
    msg = await db.getDocument(DB_ID, COL_MESSAGES, msgId);
  } catch (_) {
    return res.json({ error: 'Message not found' }, 404);
  }
  if (msg.convId !== convId) {
    return res.json({ error: 'convId mismatch' }, 400);
  }
  const orgId = msg.orgId;
  if (!orgId) {
    return res.json({ error: 'Message has no orgId' }, 400);
  }

  // Aufrufer muss Admin/Moderator DIESER Org sein.
  let role;
  try {
    const caller = await db.getDocument(DB_ID, COL_MEMBERS, `${orgId}_${callerId}`);
    role = caller.role;
  } catch (_) {
    return res.json({ error: 'Not a member of this org' }, 403);
  }
  if (role !== 'admin' && role !== 'moderator') {
    return res.json({ error: 'Insufficient role' }, 403);
  }

  // Moderation anwenden: Text ersetzen + als archiviert markieren.
  try {
    await db.updateDocument(DB_ID, COL_MESSAGES, msgId, {
      text: newText,
      editedAt: new Date().toISOString(),
      isArchived: true,
      archivedByUid: callerId,
      archivedByName: archivedByName || '',
    });
  } catch (e) {
    error(`Failed to moderate message ${msgId}: ${e.message}`);
    return res.json({ error: 'Update failed' }, 500);
  }

  log(`Message ${msgId} moderated by ${callerId} (${role}) in org ${orgId}`);
  return res.json({ ok: true });
};
