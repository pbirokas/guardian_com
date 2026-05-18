const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVERSATIONS = 'conversations';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const org = req.body;
  if (!org || !org.$id) {
    error('No document in payload');
    return res.empty();
  }

  const orgId = org.$id;
  const newAdminUid = org.adminUid;

  if (!newAdminUid) {
    error('No adminUid in payload');
    return res.empty();
  }

  // Appwrite liefert nur After-State → wir lesen orgAdminUid aus den Conversations,
  // das ist der bisherige Admin. Idempotent: überspringen wenn bereits aktuell.
  let total = 0;
  let lastId = null;

  while (true) {
    const queries = [
      Query.equal('orgId', orgId),
      Query.limit(200),
    ];
    if (lastId) queries.push(Query.cursorAfter(lastId));

    const convsResult = await db.listDocuments(DB_ID, COL_CONVERSATIONS, queries);
    if (convsResult.documents.length === 0) break;

    for (const conv of convsResult.documents) {
      const oldAdminUid = conv.orgAdminUid;
      if (!oldAdminUid || oldAdminUid === newAdminUid) continue;

      const canApproveUids = (conv.canApproveUids ?? []).filter((uid) => uid !== oldAdminUid);
      if (!canApproveUids.includes(newAdminUid)) canApproveUids.push(newAdminUid);

      try {
        await db.updateDocument(DB_ID, COL_CONVERSATIONS, conv.$id, {
          orgAdminUid: newAdminUid,
          canApproveUids,
        });
        total++;
      } catch (err) {
        error(`Failed to update conv ${conv.$id}: ${err.message}`);
      }
    }

    if (convsResult.documents.length < 200) break;
    lastId = convsResult.documents[convsResult.documents.length - 1].$id;
  }

  log(`on-org-admin-transferred: org=${orgId} newAdmin=${newAdminUid} conversations updated=${total}`);
  return res.empty();
};
