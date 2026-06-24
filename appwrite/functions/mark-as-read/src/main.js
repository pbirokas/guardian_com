const { Client, Databases, Permission, Role } = require('node-appwrite');
const crypto = require('crypto');

const DB_ID       = 'guardian';
const COL_CONVS   = 'conversations';
const COL_RECEIPTS = 'read_receipts';

const GET_TIMEOUT_MS    = 10_000;
const UPDATE_TIMEOUT_MS = 8_000;

// Deterministische Dokument-ID für ein (convId, uid)-Paar.
// Ein read_receipt ist pro Paar eindeutig — die ID muss daher nicht zufällig sein,
// sondern wird aus den Schlüsseln abgeleitet. Dadurch entfällt die teure
// listDocuments-Suche (Full-Collection-Scan) komplett: wir lesen/schreiben
// direkt per ID. Appwrite-IDs: max. 36 Zeichen, [a-zA-Z0-9._-], kein Sonderzeichen
// am Anfang — Hex aus SHA-256 (auf 36 Zeichen gekürzt) erfüllt das.
//
// WICHTIG: Muss byte-für-byte identisch zu receiptIdFor in
// appwrite/rekey-read-receipts.js bleiben. Weicht eine Kopie ab, re-keyt jeder
// Receipt still auf ein neues Dokument und die Ungelesen-Badges brechen.
function receiptIdFor(convId, uid) {
  return crypto.createHash('sha256').update(`${convId}:${uid}`).digest('hex').slice(0, 36);
}

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

async function withRetry(fn, label, attempts = 2) {
  let lastErr;
  for (let i = 0; i < attempts; i++) {
    try { return await fn(); }
    catch (e) {
      lastErr = e;
      const code = e?.code ?? e?.status ?? 0;
      if (e.isTimeout || (code !== 500 && code !== 503)) throw e;
      if (i < attempts - 1) await new Promise(r => setTimeout(r, 400));
    }
  }
  throw lastErr;
}

// Upsert eines read_receipts-Dokuments per bekannter ID.
// Reihenfolge: Update versuchen → bei 404 anlegen → bei 409 (paralleler Create
// hat das Dokument zwischenzeitlich erzeugt) erneut Update. So bleibt der Vorgang
// auch bei nebenläufigen Requests für dasselbe (convId, uid) korrekt (last-write-wins).
async function upsertReceipt(db, receiptId, convId, uid, readAt) {
  try {
    return await withTimeout(
      db.updateDocument(DB_ID, COL_RECEIPTS, receiptId, { readAt }),
      'updateDocument(receipt)',
      UPDATE_TIMEOUT_MS,
    );
  } catch (e) {
    const code = e?.code ?? e?.status ?? 0;
    if (e.isTimeout || code !== 404) throw e;
  }
  try {
    return await withTimeout(
      db.createDocument(DB_ID, COL_RECEIPTS, receiptId, { convId, uid, readAt }, [
        Permission.read(Role.user(uid)),
        Permission.update(Role.user(uid)),
        Permission.delete(Role.user(uid)),
      ]),
      'createDocument(receipt)',
      UPDATE_TIMEOUT_MS,
    );
  } catch (e) {
    const code = e?.code ?? e?.status ?? 0;
    if (e.isTimeout || code !== 409) throw e;
    // Race: parallel angelegt → jetzt nur noch den Timestamp aktualisieren.
    return await withTimeout(
      db.updateDocument(DB_ID, COL_RECEIPTS, receiptId, { readAt }),
      'updateDocument(receipt-after-409)',
      UPDATE_TIMEOUT_MS,
    );
  }
}

module.exports = async ({ req, res, log, error }) => {
  const startMs = Date.now();
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

  log(`[start] uid=${uid} convId=${convId} readAt=${readAt ?? 'now'}`);

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

  // Nur die Conversation lesen (direkter ID-Lookup, O(1)).
  // Die frühere listDocuments(receipts)-Suche entfällt — wir kennen die Dokument-ID
  // des Receipts deterministisch (siehe receiptIdFor) und schreiben direkt per ID.
  log(`[fetch-start] getDocument(conv) t=+${Date.now() - startMs}ms`);
  const fetchStart = Date.now();
  let conv;
  try {
    conv = await withTimeout(
      db.getDocument(DB_ID, COL_CONVS, convId),
      'getDocument(conv)',
      GET_TIMEOUT_MS,
    );
  } catch (e) {
    if (e.isTimeout) {
      error(`getDocument(conv) timed out for convId=${convId} elapsed=${Date.now() - startMs}ms`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`getDocument(conv) failed: code=${code} msg=${e?.message} elapsed=${Date.now() - startMs}ms`);
    if (code === 404) return res.json({ error: 'Conversation not found' }, 404);
    return res.json({ error: 'Internal server error' }, 500);
  }
  log(`[conv-ok] elapsed=${Date.now() - fetchStart}ms participants=${(conv.participantUids ?? []).length} guardians=${(conv.guardianUids ?? []).length} approvers=${(conv.canApproveUids ?? []).length} lastReadAtJsonLen=${(conv.lastReadAtJson ?? '').length}`);

  // Berechtigungscheck: nur Teilnehmer, Guardians und Approver dürfen markieren.
  const allowed = [
    ...(conv.participantUids ?? []),
    ...(conv.guardianUids ?? []),
    ...(conv.canApproveUids ?? []),
  ];
  if (!allowed.includes(uid)) {
    return res.json({ error: 'Not a participant' }, 403);
  }

  // Upsert per deterministischer ID: erst Update versuchen, bei 404 anlegen.
  // Kein listDocuments mehr → kein Full-Collection-Scan, keine doppelten Receipts.
  // withRetry fängt transiente 500/503-Fehler ab (max. 2 Versuche).
  const receiptId = receiptIdFor(convId, uid);
  const upsertStart = Date.now();
  log(`[upsert-start] receiptId=${receiptId}`);
  try {
    await withRetry(() => upsertReceipt(db, receiptId, convId, uid, effectiveReadAt), 'upsert(receipt)');
    log(`[upsert-ok] elapsed=${Date.now() - upsertStart}ms`);
  } catch (e) {
    if (e.isTimeout) {
      error(`upsert(receipt) timed out for convId=${convId} uid=${uid} elapsed=${Date.now() - upsertStart}ms total=${Date.now() - startMs}ms`);
      return res.json({ error: 'Service temporarily unavailable' }, 503);
    }
    const code = e?.code ?? e?.status ?? 0;
    error(`upsert(receipt) failed: code=${code} msg=${e?.message} elapsed=${Date.now() - upsertStart}ms`);
    return res.json({ error: 'Internal server error' }, 500);
  }

  // ÜBERGANGS-COMPAT: Alte App-Versionen lesen lastReadAtJson vom Conversation-Dokument.
  // Dieser Block kann nach vollständigem Play-Store-Rollout der neuen Version entfernt werden.
  const compatStart = Date.now();
  try {
    let existing = {};
    try { existing = conv.lastReadAtJson ? JSON.parse(conv.lastReadAtJson) : {}; } catch (_) {}
    existing[uid] = effectiveReadAt;
    const newJson = JSON.stringify(existing);
    log(`[compat-start] lastReadAtJsonLen=${newJson.length} keys=${Object.keys(existing).length}`);
    await withTimeout(
      db.updateDocument(DB_ID, COL_CONVS, convId, { lastReadAtJson: newJson }),
      'updateDocument(lastReadAtJson-compat)',
      UPDATE_TIMEOUT_MS,
    );
    log(`[compat-ok] elapsed=${Date.now() - compatStart}ms`);
  } catch (e) {
    // Fehler hier sind nicht fatal — read_receipts ist bereits geschrieben.
    // Alte App sieht Badge ggf. falsch, neue App funktioniert korrekt.
    const code = e?.code ?? e?.status ?? 0;
    error(`compat lastReadAtJson update failed (non-fatal): code=${code} msg=${e?.message} elapsed=${Date.now() - compatStart}ms`);
  }

  log(`[done] uid=${uid} convId=${convId} readAt=${effectiveReadAt} total=${Date.now() - startMs}ms`);
  return res.json({ ok: true });
};
