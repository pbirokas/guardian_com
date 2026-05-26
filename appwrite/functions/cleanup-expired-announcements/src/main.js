const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL = 'announcements';

async function collectIds(db, queries) {
  const ids = [];
  let cursor = null;
  do {
    const q = [...queries, Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, COL, q);
    ids.push(...result.documents.map(d => d.$id));
    cursor = result.documents.length === 100 ? result.documents.at(-1).$id : null;
  } while (cursor);
  return ids;
}

async function deleteAll(db, ids, label, error) {
  let deleted = 0;
  for (const id of ids) {
    try {
      await db.deleteDocument(DB_ID, COL, id);
      deleted++;
    } catch (err) {
      error(`Failed to delete ${label} ${id}: ${err.message}`);
    }
  }
  return deleted;
}

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // 24h Karenzzeit: erst nach 24h löschen
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  // Alle drei disjunkten Sets parallel einsammeln, dann löschen
  // Pass 1: Nicht-Events mit explizitem Ablaufdatum
  // Pass 2: Events deren Enddatum abgelaufen ist
  // Pass 3: Events ohne Enddatum deren Startdatum abgelaufen ist
  const [announcementIds, eventByEndDateIds, eventByDateIds] = await Promise.all([
    collectIds(db, [
      Query.notEqual('type', 'event'),
      Query.lessThan('expiresAt', cutoff),
    ]),
    collectIds(db, [
      Query.equal('type', 'event'),
      Query.lessThan('eventEndDate', cutoff),
    ]),
    collectIds(db, [
      Query.equal('type', 'event'),
      Query.isNull('eventEndDate'),
      Query.lessThan('eventDate', cutoff),
    ]),
  ]);

  const [deletedAnnouncements, deletedByEndDate, deletedByDate] = await Promise.all([
    deleteAll(db, announcementIds, 'announcement', error),
    deleteAll(db, eventByEndDateIds, 'event(eventEndDate)', error),
    deleteAll(db, eventByDateIds, 'event(eventDate)', error),
  ]);

  const total = deletedAnnouncements + deletedByEndDate + deletedByDate;
  log(
    `cleanupExpiredAnnouncements: ${total} deleted` +
    ` (announcements: ${deletedAnnouncements},` +
    ` eventEndDate: ${deletedByEndDate},` +
    ` eventDate: ${deletedByDate})`,
  );
  return res.empty();
};
