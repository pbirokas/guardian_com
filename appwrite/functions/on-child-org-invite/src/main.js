const { Client, Databases } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const consent = req.body;
  if (!consent || !consent.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { parentUids, childName, orgName } = consent;
  if (!parentUids || parentUids.length === 0) {
    log('No parentUids, skipping');
    return res.empty();
  }

  await sendToUsers(
    db,
    parentUids,
    'Einwilligung erforderlich',
    `${orgName ?? 'Eine Organisation'} möchte ${childName ?? 'dein Kind'} einladen. Tippe um zu entscheiden.`,
    { type: 'org_invite_consent', consentId: consent.$id },
    log,
    error,
  );

  log(`on-child-org-invite: notified ${parentUids.length} parent(s) for consent ${consent.$id}`);
  return res.empty();
};
