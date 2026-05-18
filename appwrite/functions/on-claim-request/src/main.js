const { Client, Databases } = require('node-appwrite');
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

  const { fromName, toUid } = claimRequest;
  if (!toUid) {
    error('Missing toUid in claim request');
    return res.empty();
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
