const { Client, Databases, Permission, Role } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const claimRequest = req.body;
  if (!claimRequest || !claimRequest.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { fromUid, fromName, toUid } = claimRequest;
  if (!toUid || !fromUid) {
    error('Missing toUid or fromUid in claim request');
    return res.empty();
  }

  // Document-Level-Permissions setzen, damit Realtime für beide Seiten feuert.
  // Client kann keine fremden User-IDs in Permissions setzen → hier via Admin-Key.
  try {
    await db.updateDocument(DB_ID, 'claim_requests', claimRequest.$id, {}, [
      Permission.read(Role.user(fromUid)),
      Permission.update(Role.user(fromUid)),
      Permission.delete(Role.user(fromUid)),
      Permission.read(Role.user(toUid)),
      Permission.update(Role.user(toUid)),
    ]);
    log(`Permissions set for claim ${claimRequest.$id}`);
  } catch (e) {
    error(`Failed to set permissions on claim ${claimRequest.$id}: ${e.message}`);
  }

  await sendToUsers(
    db,
    [toUid],
    'Neue Verknüpfungsanfrage',
    `${fromName} möchte dein Elternteil sein. Tippe um zu antworten.`,
    { type: 'claim_request', requestId: claimRequest.$id },
    log,
    error,
  );

  log(`on-claim-request done: notified toUid=${toUid}`);
  return res.empty();
};
