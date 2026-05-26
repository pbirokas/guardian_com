const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_POLLS = 'polls';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Alle abgelaufenen, noch offenen Polls in einer Query — möglich weil
  // polls jetzt eine flache Collection ist (kein Subcollection-Iterate nötig)
  const now = new Date().toISOString();
  let cursor = null;
  let totalClosed = 0;

  do {
    const queries = [
      Query.lessThanEqual('expiresAt', now),
      Query.equal('isClosed', false),
      Query.limit(100),
    ];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    const result = await db.listDocuments(DB_ID, COL_POLLS, queries);

    for (const poll of result.documents) {
      try {
        await db.updateDocument(DB_ID, COL_POLLS, poll.$id, { isClosed: true });
        totalClosed++;
      } catch (err) {
        error(`Failed to close poll ${poll.$id}: ${err.message}`);
      }
    }

    cursor = result.documents.length === 100
      ? result.documents[result.documents.length - 1].$id
      : null;
  } while (cursor);

  log(`cleanupExpiredPolls: ${totalClosed} poll(s) closed.`);
  return res.empty();
};
