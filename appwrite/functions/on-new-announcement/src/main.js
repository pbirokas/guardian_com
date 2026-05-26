const { Client, Databases, Query } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_ORGANIZATIONS = 'organizations';
const COL_MEMBERS = 'members';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const announcement = req.body;
  if (!announcement || !announcement.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { orgId, title, content, authorUid } = announcement;
  if (!orgId) {
    error('Missing orgId');
    return res.empty();
  }

  // Org-Name + memberUids laden
  let org;
  try {
    org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
  } catch (_) {
    error(`Org ${orgId} not found`);
    return res.empty();
  }

  const orgName = org.name ?? '';
  const memberUids = (org.memberUids ?? []).filter((uid) => uid !== authorUid);
  if (memberUids.length === 0) {
    log('No recipients');
    return res.empty();
  }

  // Nur Mitglieder mit aktivierten Benachrichtigungen
  const membersResult = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('notificationsEnabled', true),
    Query.limit(500),
  ]);
  const enabledUids = new Set(membersResult.documents.map((d) => d.uid));
  const eligibleUids = memberUids.filter((uid) => enabledUids.has(uid));

  if (eligibleUids.length === 0) {
    log('All notifications disabled, skipping');
    return res.empty();
  }

  const body = content && content.length > 100 ? content.substring(0, 100) + '…' : (content ?? '');

  await sendToUsers(
    db,
    eligibleUids,
    `📢 ${orgName}: ${title ?? ''}`,
    body,
    { type: 'new_announcement', orgId, announcementId: announcement.$id },
    log,
    error,
  );

  log(`on-new-announcement: sent to ${eligibleUids.length} recipient(s)`);
  return res.empty();
};
