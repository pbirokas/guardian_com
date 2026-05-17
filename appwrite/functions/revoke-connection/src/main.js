const { Client, Databases } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_USERS = 'users';

module.exports = async ({ req, res, log, error }) => {
  const callerUid = req.headers['x-appwrite-user-id'];
  if (!callerUid) return res.json({ error: 'Unauthenticated' }, 401);

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Child accounts cannot revoke parental connections
  let callerDoc;
  try {
    callerDoc = await db.getDocument(DB_ID, COL_USERS, callerUid);
  } catch (e) {
    return res.json({ error: 'User not found' }, 404);
  }
  if (callerDoc.isChild === true) {
    return res.json({ error: 'Child accounts cannot revoke connections' }, 403);
  }

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }
  const { otherUid } = body;

  if (!otherUid || typeof otherUid !== 'string') {
    return res.json({ error: 'otherUid required' }, 400);
  }
  if (otherUid === callerUid) {
    return res.json({ error: 'Cannot revoke self' }, 400);
  }

  async function removeFromBothFields(docId, removeUid) {
    const doc = await db.getDocument(DB_ID, COL_USERS, docId);
    const parentUids = (doc.verifiedParentUids ?? []).filter((u) => u !== removeUid);
    const childUids = (doc.verifiedChildUids ?? []).filter((u) => u !== removeUid);
    await db.updateDocument(DB_ID, COL_USERS, docId, {
      verifiedParentUids: parentUids,
      verifiedChildUids: childUids,
    });
  }

  await Promise.all([
    removeFromBothFields(callerUid, otherUid),
    removeFromBothFields(otherUid, callerUid),
  ]);

  log(`revoke-connection: caller=${callerUid} other=${otherUid}`);
  return res.json({ ok: true });
};
