const { Client, Databases } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_CONVS = 'conversations';

const GET_TIMEOUT_MS = 5_000;
// updateDocument-Timeout kürzer, damit im Retry-Fall noch Zeit bleibt
// (14s Gesamtlimit: ~5s getDoc + ~3s update + ~1s Jitter + ~3s Retry = ~12s)
const UPDATE_TIMEOUT_MS = 3_000;
const MAX_UPDATE_ATTEMPTS = 2;

function withTimeout(promise, label, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(
        () => reject(Object.assign(new Error(`${label} timed out`), { isTimeout: true })),
        ms,
      )
    ),
  ]);
}

// Retry bei transienten Write-Conflicts (500) und Timeouts mit Jitter,
// damit gleichzeitige Schreiber sich entzerren.
async function updateWithRetry(db, convId, data, logFn, errorFn) {
  for (let attempt = 1; attempt <= MAX_UPDATE_ATTEMPTS; attempt++) {
    try {
      await withTimeout(
        db.updateDocument(DB_ID, COL_CONVS, convId, data),
        'updateDocument',
        UPDATE_TIMEOUT_MS,
      );
      return;
    } catch (e) {
      const code = e?.code ?? e?.status ?? 0;
      const isRetryable = e.isTimeout || code === 500 || code === 429;

      if (attempt < MAX_UPDATE_ATTEMPTS && isRetryable) {
        // Jitter 100–600ms — verteilt simultane Schreiber über die Zeit
        const jitter = 100 + Math.random() * 500;
        logFn(`updateDocument attempt ${attempt} failed (${e.isTimeout ? 'timeout' : `code=${code}`}), retry in ${Math.round(jitter)}ms`);
        await new Promise(r => setTimeout(r, jitter));
        continue;
      }
      throw e;
    }
  }
}

module.exports = async ({ req, res, log, error }) => {
  const uid = req.headers['x-appwrite-user-id'];
  if (!uid) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const { convId, readAt } = body;
  if (!convId || typeof convId !== 'string') {
    return res.json({ error: 'convId required' }, 400);
  }

  // readAt muss ein gültiger ISO-8601-Timestamp sein und darf nicht mehr als
  // 60s in der Zukunft liegen (Toleranz für Clock-Drift zwischen Geräten).
  let effectiveReadAt;
  if (readAt != null) {
    const parsed = new Date(readAt);
    if (isNaN(parsed.getTime()) || parsed > new Date(Date.now() + 60_000)) {
      return res.json({ error: 'Invalid readAt' }, 400);
    }
    effectiveReadAt = parsed.toISOString();
  } else {
    effectiveReadAt = new Date().toISOString();
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  let conv;
  try {
    conv = await withTimeout(db.getDocument(DB_ID, COL_CONVS, convId), 'getDocument', GET_TIMEOUT_MS);
  } catch (e) {
    if (e.isTimeout) {
      error(`getDocument timed out for convId=${convId}`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`getDocument failed: code=${code} msg=${e?.message}`);
    if (code === 404) return res.json({ error: 'Conversation not found' }, 404);
    return res.json({ error: 'Internal server error' }, 500);
  }

  // Nur Teilnehmer, Guardians und berechtigte Approver dürfen als gelesen markieren.
  const allowed = [
    ...(conv.participantUids ?? []),
    ...(conv.guardianUids ?? []),
    ...(conv.canApproveUids ?? []),
  ];
  if (!allowed.includes(uid)) {
    return res.json({ error: 'Not a participant' }, 403);
  }

  // Nur den eigenen Eintrag aktualisieren — kein anderer UID wird berührt.
  let existing = {};
  try {
    existing = conv.lastReadAtJson ? JSON.parse(conv.lastReadAtJson) : {};
  } catch (_) { /* korrupter Wert → leere Map als Fallback */ }

  existing[uid] = effectiveReadAt;

  try {
    await updateWithRetry(db, convId, { lastReadAtJson: JSON.stringify(existing) }, log, error);
  } catch (e) {
    if (e.isTimeout) {
      error(`updateDocument timed out (all attempts exhausted) for convId=${convId}`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`updateDocument failed: code=${code} msg=${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }

  log(`mark-as-read: uid=${uid} convId=${convId} readAt=${effectiveReadAt}`);
  return res.json({ ok: true });
};
