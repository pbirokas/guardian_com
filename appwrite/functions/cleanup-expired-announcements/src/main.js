const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL = 'announcements';

// Transiente Serverfehler (500/503) kurz wiederholen. Andere Fehler (z.B. 400
// wegen fehlendem Index) sofort durchreichen — die wiederholen sich ohnehin.
async function withRetry(fn, attempts = 3) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const code = e?.code ?? e?.status ?? 0;
      if (code !== 500 && code !== 503) throw e;
      if (i < attempts - 1) {
        await new Promise(r => setTimeout(r, 500 * (i + 1)));
      }
    }
  }
  throw lastErr;
}

async function collectIds(db, queries) {
  const ids = [];
  let cursor = null;
  do {
    const q = [...queries, Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const result = await withRetry(() => db.listDocuments(DB_ID, COL, q));
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

  // Drei disjunkte Sets:
  // Pass 1: Nicht-Events mit explizitem Ablaufdatum
  // Pass 2: Events deren Enddatum abgelaufen ist
  // Pass 3: Events ohne Enddatum deren Startdatum abgelaufen ist
  const passes = [
    {
      label: 'announcement',
      queries: [
        Query.notEqual('type', 'event'),
        Query.lessThan('expiresAt', cutoff),
      ],
    },
    {
      label: 'event(eventEndDate)',
      queries: [
        Query.equal('type', 'event'),
        Query.lessThan('eventEndDate', cutoff),
      ],
    },
    {
      label: 'event(eventDate)',
      queries: [
        Query.equal('type', 'event'),
        Query.isNull('eventEndDate'),
        Query.lessThan('eventDate', cutoff),
      ],
    },
  ];

  // allSettled statt all: ein fehlgeschlagener Durchlauf darf die anderen beiden
  // nicht mitreißen — sonst wird bei einem einzigen Query-Fehler gar nichts
  // aufgeräumt und abgelaufene Einträge sammeln sich an.
  const collected = await Promise.allSettled(
    passes.map(p => collectIds(db, p.queries)),
  );

  let total = 0;
  const failed = [];
  for (let i = 0; i < passes.length; i++) {
    const { label } = passes[i];
    const result = collected[i];
    if (result.status === 'rejected') {
      failed.push(label);
      error(`collectIds failed for ${label}: ${result.reason?.message ?? result.reason}`);
      continue;
    }
    total += await deleteAll(db, result.value, label, error);
  }

  log(`cleanupExpiredAnnouncements: ${total} deleted, ${failed.length}/${passes.length} pass(es) failed`);

  // Teilerfolge sind gelöscht — aber die Execution trotzdem als fehlgeschlagen
  // markieren, damit der tägliche Fehler-Report das Problem weiter sichtbar macht.
  if (failed.length > 0) {
    throw new Error(`cleanupExpiredAnnouncements: pass(es) failed: ${failed.join(', ')}`);
  }

  return res.empty();
};
