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
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
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

      // Alte Nachrichten dieser Org löschen. KEIN cursorAfter: beim Löschen aller
      // Treffer würde der Cursor auf ein gerade gelöschtes Dokument zeigen
      // ("Document for the 'cursor' value not found"). Stattdessen wiederholt die
      // erste Seite holen, bis nichts mehr übrig ist.
      while (true) {
        const msgs = await db.listDocuments(DB_ID, COL_MESSAGES, [
          Query.equal('orgId', org.$id),
          Query.lessThan('sentAt', cutoff),
          Query.limit(100),
        ]);
        if (msgs.documents.length === 0) break;

        let deletedInPage = 0;
        for (const msg of msgs.documents) {
          try {
            await db.deleteDocument(DB_ID, COL_MESSAGES, msg.$id);
            totalMessages++;
            deletedInPage++;
          } catch (err) {
            error(`Failed to delete message ${msg.$id}: ${err.message}`);
          }
        }

        // TODO (Phase 3): Storage-Anhänge löschen wenn Flutter-Migration abgeschlossen
        // msg.imageUrl / msg.audioUrl / msg.fileUrl werden dann Appwrite File-IDs sein

        // Guard: schlagen alle Löschungen einer Seite fehl, sonst Endlosschleife.
        if (deletedInPage === 0) {
          error(`cleanup: keine Nachricht in org ${org.$id} löschbar — Schleife abgebrochen`);
          break;
        }
      }

      // Alte Polls dieser Org löschen (gleiches Muster ohne Cursor wie oben).
      while (true) {
        const polls = await db.listDocuments(DB_ID, COL_POLLS, [
          Query.equal('orgId', org.$id),
          Query.lessThan('createdAt', cutoff),
          Query.limit(100),
        ]);
        if (polls.documents.length === 0) break;

        let deletedInPage = 0;
        for (const poll of polls.documents) {
          try {
            await db.deleteDocument(DB_ID, COL_POLLS, poll.$id);
            totalPolls++;
            deletedInPage++;
          } catch (err) {
            error(`Failed to delete poll ${poll.$id}: ${err.message}`);
          }
        }

        if (deletedInPage === 0) {
          error(`cleanup: keine Poll in org ${org.$id} löschbar — Schleife abgebrochen`);
          break;
        }
      }
    }

    orgCursor = orgs.documents.length === 100
      ? orgs.documents[orgs.documents.length - 1].$id
      : null;
  } while (orgCursor);

  log(`cleanupOldMessages: ${totalMessages} message(s) and ${totalPolls} poll(s) deleted.`);
  return res.empty();
};
