/**
 * self-service — Änderungen eines Nutzers an seinen EIGENEN Daten.
 *
 * Warum eine Function: Appwrite kennt keine Feld-Rechte. Solange
 * `users/{uid}` und `members/{orgId}_{uid}` `update user(uid)` trugen, konnte
 * jeder per API `role: "admin"` in sein Member-Doc schreiben (→ Aufsicht über
 * alle Chats der Org, `admin-member-action`/`moderate-message`/
 * `sync-supervisor-team` vertrauen dem Feld) und ein Kind `guardianUids`,
 * `isChild` oder `verifiedParentUids` ändern. Jetzt sind diese Docs für
 * Clients nur noch lesbar; hier wird je Aktion eine feste Feld-Whitelist
 * geschrieben.
 *
 * Aktionen (body.action):
 *  - ensureUserDoc                         → eigenes users-Doc anlegen (falls fehlt) und zurückgeben
 *  - updateProfile     { displayName, photoUrl? }  → users + alle eigenen Member-Docs
 *  - setHideEmail      { hideEmail }               → users + alle eigenen Member-Docs
 *  - setNotificationSettings { settings }          → users.notificationSettingsJson
 *  - setFcmToken       { token }                   → users.fcmToken
 *  - setChildAlertInterval { orgId, interval }     → eigenes Member-Doc
 *  - setMessageInterval    { orgId, interval }     → eigenes Member-Doc (+ notificationsEnabled)
 *  - createOrganization    { name, tag }           → Org + eigenes Admin-Member-Doc + membershipsJson
 *  - respondClaim      { requestId, response }     → Eltern-Kind-Anfrage: confirmed/rejected (Kind),
 *                                                    cancelled (Elternteil)
 *
 * Sicherheit: Aufrufer über x-appwrite-user-id; geschrieben werden nur Docs
 * des Aufrufers (bzw. Claims, an denen er beteiligt ist).
 */

const { Client, Databases, Users, Query, ID, Permission, Role } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_MEMBERS = 'members';
const COL_ORGS = 'organizations';
const COL_CLAIMS = 'claim_requests';

const INTERVALS = new Set(['always', 'hourly', 'daily', 'never']);
const ORG_TAGS = new Set(['familie', 'freunde', 'schule', 'vereine', 'sonstiges']);
const PHOTO_URL_RE = /^https:\/\/[^\s"]+\/storage\/buckets\/[^/\s]+\/files\/[^/\s]+\/view(\?[^\s"]*)?$/;
const RETENTION_DEFAULT = 90;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

module.exports = async ({ req, res, log, error }) => {
  const callerId = req.headers['x-appwrite-user-id'];
  if (!callerId) return res.json({ error: 'Unauthenticated' }, 401);

  let body = req.body ?? {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (_) { body = {}; }
  }

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
  const ctx = { db: new Databases(client), users: new Users(client), callerId, body, log };

  const handler = ACTIONS[body.action];
  if (!handler) return res.json({ error: `Unknown action: ${body.action}` }, 400);

  try {
    const result = await handler(ctx);
    return res.json({ ok: true, ...result });
  } catch (e) {
    if (e instanceof HttpError) return res.json({ error: e.message }, e.status);
    error(`self-service ${body.action} failed: ${e?.message}`);
    return res.json({ error: 'Internal server error' }, 500);
  }
};

// ── Aktionen ────────────────────────────────────────────────────────────────

const ACTIONS = {
  async ensureUserDoc({ db, users, callerId, log }) {
    try {
      return { user: await db.getDocument(DB_ID, COL_USERS, callerId) };
    } catch (e) {
      if (e?.code !== 404) throw e;
    }
    const account = await users.get(callerId);
    const email = String(account.email ?? '').toLowerCase();
    const displayName = (account.name || email || callerId).substring(0, 100);
    try {
      const doc = await db.createDocument(DB_ID, COL_USERS, callerId, {
        email,
        displayName,
        membershipsJson: '[]',
        createdAt: new Date().toISOString(),
        isChild: false,
        verifiedParentUids: [],
        verifiedChildUids: [],
        hideEmail: false,
      }, userDocPerms(callerId));
      log(`ensureUserDoc: created users/${callerId}`);
      return { user: doc };
    } catch (e) {
      // Paralleler Aufruf hat das Doc gerade angelegt.
      if (e?.code === 409) return { user: await db.getDocument(DB_ID, COL_USERS, callerId) };
      throw e;
    }
  },

  async updateProfile({ db, callerId, body }) {
    const displayName = cleanName(body.displayName);
    const updates = { displayName };
    if (body.photoUrl !== undefined && body.photoUrl !== null) {
      if (typeof body.photoUrl !== 'string' || body.photoUrl.length > 512 ||
          !PHOTO_URL_RE.test(body.photoUrl)) {
        throw new HttpError(400, 'Invalid photoUrl');
      }
      updates.photoUrl = body.photoUrl;
    }
    await db.updateDocument(DB_ID, COL_USERS, callerId, updates);
    await updateOwnMemberDocs(db, callerId, updates);
    return {};
  },

  async setHideEmail({ db, callerId, body }) {
    if (typeof body.hideEmail !== 'boolean') throw new HttpError(400, 'hideEmail must be boolean');
    const updates = { hideEmail: body.hideEmail };
    await db.updateDocument(DB_ID, COL_USERS, callerId, updates);
    await updateOwnMemberDocs(db, callerId, updates);
    return {};
  },

  async setNotificationSettings({ db, callerId, body }) {
    const s = body.settings;
    if (!s || typeof s !== 'object' || Array.isArray(s)) throw new HttpError(400, 'settings object required');
    // Nur flache Werte (bool/string/number) — die App speichert dort Schalter/Intervalle.
    for (const v of Object.values(s)) {
      if (!['boolean', 'string', 'number'].includes(typeof v)) throw new HttpError(400, 'Invalid settings value');
    }
    const json = JSON.stringify(s);
    if (json.length > 1024) throw new HttpError(400, 'settings too large');
    await db.updateDocument(DB_ID, COL_USERS, callerId, { notificationSettingsJson: json });
    return {};
  },

  async setFcmToken({ db, callerId, body }) {
    const token = body.token;
    if (token !== null && (typeof token !== 'string' || token.length === 0 || token.length > 512)) {
      throw new HttpError(400, 'Invalid token');
    }
    await db.updateDocument(DB_ID, COL_USERS, callerId, { fcmToken: token });
    return {};
  },

  async setChildAlertInterval({ db, callerId, body }) {
    const interval = requireInterval(body.interval);
    const memberId = await ownMemberId(db, body.orgId, callerId);
    await db.updateDocument(DB_ID, COL_MEMBERS, memberId, { childAlertInterval: interval });
    return {};
  },

  async setMessageInterval({ db, callerId, body }) {
    const interval = requireInterval(body.interval);
    const memberId = await ownMemberId(db, body.orgId, callerId);
    await db.updateDocument(DB_ID, COL_MEMBERS, memberId, {
      messageAlertInterval: interval,
      notificationsEnabled: interval !== 'never',
    });
    return {};
  },

  async createOrganization({ db, callerId, body, log }) {
    const name = cleanName(body.name);
    if (!ORG_TAGS.has(body.tag)) throw new HttpError(400, 'Invalid tag');

    const user = await db.getDocument(DB_ID, COL_USERS, callerId);
    // Kind-Konten dürfen nie eine andere Rolle als `child` haben.
    if (user.isChild) throw new HttpError(403, 'child_account_role_locked');

    const orgId = ID.unique();
    const now = new Date().toISOString();
    const org = await db.createDocument(DB_ID, COL_ORGS, orgId, {
      name,
      adminUid: callerId,
      tag: body.tag,
      memberUids: [callerId],
      createdAt: now,
      isArchived: false,
      keywords: [],
      messageRetentionDays: RETENTION_DEFAULT,
    }, [
      // Wie bisher beim Client-Anlegen (Phase 2 der Collection-Härtung
      // stellt Org-Docs auf ein Org-Team um).
      Permission.read(Role.users()),
      Permission.update(Role.user(callerId)),
      Permission.delete(Role.user(callerId)),
    ]);

    await db.createDocument(DB_ID, COL_MEMBERS, `${orgId}_${callerId}`, {
      orgId,
      uid: callerId,
      displayName: user.displayName,
      email: user.email ?? '',
      ...(user.photoUrl ? { photoUrl: user.photoUrl } : {}),
      role: 'admin',
      joinedAt: now,
      guardianUids: [],
      status: 'active',
      childAlertInterval: 'hourly',
      notificationsEnabled: true,
      messageAlertInterval: 'always',
      hideEmail: user.hideEmail ?? false,
      lastChildAlertAtJson: '{}',
    }, memberDocPerms());

    const memberships = parseJsonArray(user.membershipsJson);
    if (!memberships.some((m) => m.orgId === orgId)) memberships.push({ orgId, role: 'admin' });
    await db.updateDocument(DB_ID, COL_USERS, callerId, { membershipsJson: JSON.stringify(memberships) });

    log(`createOrganization: ${orgId} by ${callerId}`);
    return { organization: org };
  },

  async respondClaim({ db, callerId, body, log }) {
    const { requestId, response } = body;
    if (typeof requestId !== 'string' || !requestId) throw new HttpError(400, 'requestId required');
    if (!['confirmed', 'rejected', 'cancelled'].includes(response)) {
      throw new HttpError(400, 'Invalid response');
    }
    let claim;
    try {
      claim = await db.getDocument(DB_ID, COL_CLAIMS, requestId);
    } catch (_) {
      throw new HttpError(404, 'Claim not found');
    }
    // Bestätigen/Ablehnen nur das angefragte Kind, Zurückziehen nur der
    // Anfragende — sonst könnte sich ein Elternteil selbst bestätigen und
    // würde verifizierter Elternteil eines beliebigen Kontos.
    const allowed = response === 'cancelled' ? claim.fromUid === callerId : claim.toUid === callerId;
    if (!allowed) throw new HttpError(403, 'Forbidden');
    if (claim.status !== 'pending') throw new HttpError(409, `Claim is ${claim.status}`);
    if (response === 'confirmed' && claim.expiresAt && new Date(claim.expiresAt) < new Date()) {
      throw new HttpError(410, 'expired');
    }
    // on-claim-confirmed reagiert auf das Update-Event.
    await db.updateDocument(DB_ID, COL_CLAIMS, requestId, { status: response });
    log(`respondClaim: ${requestId} → ${response} by ${callerId}`);
    return {};
  },
};

// ── Hilfsfunktionen ─────────────────────────────────────────────────────────

/** users-Doc: nur der Eigentümer liest; schreiben nur Server-Functions. */
function userDocPerms(uid) {
  return [Permission.read(Role.user(uid))];
}

/**
 * Member-Doc: org-weit lesbar wie bisher (Phase 2 der Collection-Härtung
 * engt das auf ein Org-Team ein); schreiben nur Server-Functions.
 */
function memberDocPerms() {
  return [Permission.read(Role.users())];
}

function cleanName(raw) {
  if (typeof raw !== 'string') throw new HttpError(400, 'Invalid name');
  const name = raw.trim();
  if (name.length === 0) throw new HttpError(400, 'Name required');
  if (name.length > 100) throw new HttpError(400, 'Name too long');
  return name;
}

function requireInterval(v) {
  if (!INTERVALS.has(v)) throw new HttpError(400, 'Invalid interval');
  return v;
}

async function ownMemberId(db, orgId, uid) {
  if (typeof orgId !== 'string' || !orgId) throw new HttpError(400, 'orgId required');
  const memberId = `${orgId}_${uid}`;
  try {
    const m = await db.getDocument(DB_ID, COL_MEMBERS, memberId);
    if (m.uid !== uid) throw new Error('uid mismatch');
  } catch (_) {
    throw new HttpError(404, 'Not a member of this organization');
  }
  return memberId;
}

/**
 * Alle eigenen Member-Docs (Index `uid_idx`) — auch die von Kindern, deren
 * membershipsJson nicht jede Org enthält.
 */
async function updateOwnMemberDocs(db, uid, updates) {
  let cursor = null;
  while (true) {
    const q = [Query.equal('uid', uid), Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const { documents } = await db.listDocuments(DB_ID, COL_MEMBERS, q);
    await Promise.allSettled(
      documents.map((m) => db.updateDocument(DB_ID, COL_MEMBERS, m.$id, updates)),
    );
    if (documents.length < 100) break;
    cursor = documents[documents.length - 1].$id;
  }
}

function parseJsonArray(raw) {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v : [];
  } catch (_) {
    return [];
  }
}
