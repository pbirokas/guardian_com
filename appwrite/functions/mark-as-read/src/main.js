const { Client, Databases, Query, ID, Permission, Role } = require('node-appwrite');

const DB_ID       = 'guardian';
const COL_CONVS   = 'conversations';
const COL_RECEIPTS = 'read_receipts';

const GET_TIMEOUT_MS    = 5_000;
const UPDATE_TIMEOUT_MS = 3_000;

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
    .setEndpoint((process.env.APPWRITE_ENDPOINT || '').replace(/^http:\/\//, 'https://'))
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Berechtigungscheck: nur Teilnehmer, Guardians und Approver dürfen markieren.
  let conv;
  try {
    conv = await withTimeout(
      db.getDocument(DB_ID, COL_CONVS, convId),
      'getDocument(conv)',
      GET_TIMEOUT_MS,
    );
  } catch (e) {
    if (e.isTimeout) {
      error(`getDocument(conv) timed out for convId=${convId}`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`getDocument(conv) failed: code=${code} msg=${e?.message}`);
    if (code === 404) return res.json({ error: 'Conversation not found' }, 404);
    return res.json({ error: 'Internal server error' }, 500);
  }

  const allowed = [
    ...(conv.participantUids ?? []),
    ...(conv.guardianUids ?? []),
    ...(conv.canApproveUids ?? []),
  ];
  if (!allowed.includes(uid)) {
    return res.json({ error: 'Not a participant' }, 403);
  }

  // Vorhandenes read_receipts-Dokument für diesen Nutzer + Konversation suchen.
  let existingDocId = null;
  try {
    const result = await withTimeout(
      db.listDocuments(DB_ID, COL_RECEIPTS, [
        Query.equal('convId', convId),
        Query.equal('uid', uid),
        Query.limit(1),
      ]),
      'listDocuments(receipts)',
      GET_TIMEOUT_MS,
    );
    if (result.documents.length > 0) {
      existingDocId = result.documents[0].$id;
    }
  } catch (e) {
    if (e.isTimeout) {
      error(`listDocuments(receipts) timed out for convId=${convId} uid=${uid}`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`listDocuments(receipts) failed: code=${code} msg=${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }

  // Upsert: Update wenn vorhanden, sonst Create.
  // Jeder Nutzer schreibt nur in sein eigenes Dokument → keine Write-Konflikte.
  try {
    if (existingDocId) {
      await withTimeout(
        db.updateDocument(DB_ID, COL_RECEIPTS, existingDocId, { readAt: effectiveReadAt }),
        'updateDocument(receipt)',
        UPDATE_TIMEOUT_MS,
      );
    } else {
      await withTimeout(
        db.createDocument(DB_ID, COL_RECEIPTS, ID.unique(), {
          convId,
          uid,
          readAt: effectiveReadAt,
        }, [
          Permission.read(Role.user(uid)),
          Permission.update(Role.user(uid)),
          Permission.delete(Role.user(uid)),
        ]),
        'createDocument(receipt)',
        UPDATE_TIMEOUT_MS,
      );
    }
  } catch (e) {
    if (e.isTimeout) {
      error(`upsert(receipt) timed out for convId=${convId} uid=${uid}`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`upsert(receipt) failed: code=${code} msg=${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }

  // ÜBERGANGS-COMPAT: Alte App-Versionen lesen lastReadAtJson vom Conversation-Dokument.
  // Dieser Block kann nach vollständigem Play-Store-Rollout der neuen Version entfernt werden.
  try {
    let existing = {};
    try { existing = conv.lastReadAtJson ? JSON.parse(conv.lastReadAtJson) : {}; } catch (_) {}
    existing[uid] = effectiveReadAt;
    await withTimeout(
      db.updateDocument(DB_ID, COL_CONVS, convId, { lastReadAtJson: JSON.stringify(existing) }),
      'updateDocument(lastReadAtJson-compat)',
      UPDATE_TIMEOUT_MS,
    );
  } catch (e) {
    // Fehler hier sind nicht fatal — read_receipts ist bereits geschrieben.
    // Alte App sieht Badge ggf. falsch, neue App funktioniert korrekt.
    const code = e?.code ?? e?.status ?? 0;
    error(`compat lastReadAtJson update failed (non-fatal): code=${code} msg=${e?.message}`);
  }

  log(`mark-as-read: uid=${uid} convId=${convId} readAt=${effectiveReadAt}`);
  return res.json({ ok: true });
};
