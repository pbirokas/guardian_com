const { Client, Databases, Query } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const COL_ORGANIZATIONS = 'organizations';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const report = req.body;
  if (!report || !report.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { orgId, orgAdminUid, messageSenderName, messageText, convId } = report;
  if (!orgId || !orgAdminUid) {
    error('Missing orgId or orgAdminUid');
    return res.empty();
  }

  // Admin + alle Moderatoren ermitteln
  const alertUids = [orgAdminUid];

  const membersResult = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', 'moderator'),
    Query.limit(200),
  ]);
  membersResult.documents.forEach((doc) => {
    if (!alertUids.includes(doc.uid)) alertUids.push(doc.uid);
  });

  const body = messageText && messageText.length > 80
    ? messageText.substring(0, 80) + '…'
    : (messageText ?? '');

  await sendToUsers(
    db,
    alertUids,
    '🚩 Nachricht gemeldet',
    `${messageSenderName ?? 'Unbekannt'}: ${body}`,
    { convId: convId ?? '', reportId: report.$id },
    log,
    error,
  );

  log(`on-new-report: sent to ${alertUids.length} recipient(s) for report ${report.$id}`);

  // Increment pendingReportsCount on org so the badge updates via org Realtime
  try {
    const org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
    await db.updateDocument(DB_ID, COL_ORGANIZATIONS, orgId, {
      pendingReportsCount: (org.pendingReportsCount ?? 0) + 1,
    });
  } catch (e) {
    error(`Failed to increment pendingReportsCount: ${e.message}`);
  }

  return res.empty();
};
