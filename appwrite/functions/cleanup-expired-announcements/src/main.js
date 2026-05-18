const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_ANNOUNCEMENTS = 'announcements';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Ankündigungen die vor mehr als 24h abgelaufen sind löschen
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  let cursor = null;
  let totalDeleted = 0;

  do {
    const queries = [
      Query.lessThan('expiresAt', cutoff),
      Query.limit(100),
    ];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    const result = await db.listDocuments(DB_ID, COL_ANNOUNCEMENTS, queries);

    for (const doc of result.documents) {
      try {
        await db.deleteDocument(DB_ID, COL_ANNOUNCEMENTS, doc.$id);
        totalDeleted++;
      } catch (err) {
        error(`Failed to delete announcement ${doc.$id}: ${err.message}`);
      }
    }

    cursor = result.documents.length === 100
      ? result.documents[result.documents.length - 1].$id
      : null;
  } while (cursor);

  log(`cleanupExpiredAnnouncements: ${totalDeleted} announcement(s) deleted.`);
  return res.empty();
};
