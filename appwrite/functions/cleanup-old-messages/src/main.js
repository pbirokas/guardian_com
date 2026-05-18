const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_ORGANIZATIONS = 'organizations';
const COL_MESSAGES = 'chat_messages';
const COL_POLLS = 'polls';

const RETENTION_MIN = 30;
const RETENTION_MAX = 365;
const RETENTION_DEFAULT = 90;

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint((process.env.APPWRITE_FUNCTION_API_ENDPOINT || "").replace(/^http:\/\//, "https://"))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);
  const now = Date.now();
  let totalMessages = 0;
  let totalPolls = 0;

  // Alle Orgs laden (paginiert)
  let orgCursor = null;
  do {
    const orgQueries = [Query.limit(100)];
    if (orgCursor) orgQueries.push(Query.cursorAfter(orgCursor));
    const orgs = await db.listDocuments(DB_ID, COL_ORGANIZATIONS, orgQueries);

    for (const org of orgs.documents) {
      const retention = Math.min(
        Math.max(org.messageRetentionDays ?? RETENTION_DEFAULT, RETENTION_MIN),
        RETENTION_MAX
      );
      const cutoff = new Date(now - retention * 24 * 60 * 60 * 1000).toISOString();

      // Alte Nachrichten dieser Org löschen (paginiert)
      let msgCursor = null;
      do {
        const msgQueries = [
          Query.equal('orgId', org.$id),
          Query.lessThan('sentAt', cutoff),
          Query.limit(100),
        ];
        if (msgCursor) msgQueries.push(Query.cursorAfter(msgCursor));

        const msgs = await db.listDocuments(DB_ID, COL_MESSAGES, msgQueries);

        for (const msg of msgs.documents) {
          try {
            await db.deleteDocument(DB_ID, COL_MESSAGES, msg.$id);
            totalMessages++;
          } catch (err) {
            error(`Failed to delete message ${msg.$id}: ${err.message}`);
          }
        }

        // TODO (Phase 3): Storage-Anhänge löschen wenn Flutter-Migration abgeschlossen
        // msg.imageUrl / msg.audioUrl / msg.fileUrl werden dann Appwrite File-IDs sein

        msgCursor = msgs.documents.length === 100
          ? msgs.documents[msgs.documents.length - 1].$id
          : null;
      } while (msgCursor);

      // Alte Polls dieser Org löschen
      let pollCursor = null;
      do {
        const pollQueries = [
          Query.equal('orgId', org.$id),
          Query.lessThan('createdAt', cutoff),
          Query.limit(100),
        ];
        if (pollCursor) pollQueries.push(Query.cursorAfter(pollCursor));

        const polls = await db.listDocuments(DB_ID, COL_POLLS, pollQueries);

        for (const poll of polls.documents) {
          try {
            await db.deleteDocument(DB_ID, COL_POLLS, poll.$id);
            totalPolls++;
          } catch (err) {
            error(`Failed to delete poll ${poll.$id}: ${err.message}`);
          }
        }

        pollCursor = polls.documents.length === 100
          ? polls.documents[polls.documents.length - 1].$id
          : null;
      } while (pollCursor);
    }

    orgCursor = orgs.documents.length === 100
      ? orgs.documents[orgs.documents.length - 1].$id
      : null;
  } while (orgCursor);

  log(`cleanupOldMessages: ${totalMessages} message(s) and ${totalPolls} poll(s) deleted.`);
  return res.empty();
};
