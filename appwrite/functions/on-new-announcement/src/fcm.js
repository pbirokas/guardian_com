/**
 * FCM v1 Helper für Appwrite Functions (node-16.0 / CommonJS)
 *
 * Benötigte Env-Vars:
 *   FCM_SERVICE_ACCOUNT_B64  Base64-kodiertes Firebase Service-Account-JSON
 *   FCM_PROJECT_ID           Firebase-Projekt-ID (z.B. guardian-app-b0f6c)
 *
 * Verwendung:
 *   const { sendToUsers } = require('./fcm');
 *   await sendToUsers(db, ['uid1', 'uid2'], 'Titel', 'Text', { convId: '...' }, log, error);
 */

const https = require('https');
const { GoogleAuth } = require('google-auth-library');

let _auth = null;

function getAuth() {
  if (_auth) return _auth;
  const raw = Buffer.from(process.env.FCM_SERVICE_ACCOUNT_B64, 'base64').toString('utf8');
  const credentials = JSON.parse(raw);
  _auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  return _auth;
}

async function fcmSend(token, title, notifBody, data) {
  const accessToken = await getAuth().getAccessToken();
  const projectId = process.env.FCM_PROJECT_ID;

  const payload = JSON.stringify({
    message: {
      token,
      notification: { title, body: notifBody },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: 'high',
        notification: { channel_id: 'guardian_messages' },
      },
    },
  });

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'fcm.googleapis.com',
      path: `/v1/projects/${projectId}/messages:send`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    };

    const req = https.request(options, (res) => {
      let responseData = '';
      res.on('data', (chunk) => { responseData += chunk; });
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(responseData) });
        } catch (e) {
          reject(new Error(`FCM parse error: ${responseData}`));
        }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

/**
 * Sendet FCM-Notifications an eine Liste von User-UIDs.
 * Liest fcmToken direkt vom User-Doc. Entfernt abgelaufene Tokens automatisch.
 *
 * @param {Databases} db      Initialisiertes node-appwrite Databases-Objekt
 * @param {string[]}  uids    Liste von User-UIDs
 * @param {string}    title
 * @param {string}    body
 * @param {object}    data    Zusätzliche Payload-Felder (werden zu Strings konvertiert)
 * @param {Function}  log     Appwrite log-Funktion
 * @param {Function}  error   Appwrite error-Funktion
 */
async function sendToUsers(db, uids, title, body, data, log, error) {
  if (!uids || uids.length === 0) return;

  const DB_ID = 'guardian';
  const COL_USERS = 'users';

  for (const uid of uids) {
    let userData;
    try {
      userData = await db.getDocument(DB_ID, COL_USERS, uid);
    } catch (_) {
      continue;
    }

    const token = userData?.fcmToken;
    if (!token) continue;

    try {
      const result = await fcmSend(token, title, body, data);

      if (result.statusCode === 200) {
        log?.(`FCM OK uid=${uid}`);
      } else {
        const errCode = result.body?.error?.details?.[0]?.errorCode;
        if (errCode === 'UNREGISTERED' || result.statusCode === 404) {
          await db.updateDocument(DB_ID, COL_USERS, uid, { fcmToken: null });
          log?.(`Stale FCM token removed for uid=${uid}`);
        } else {
          error?.(`FCM failed uid=${uid} code=${errCode}: ${JSON.stringify(result.body?.error)}`);
        }
      }
    } catch (err) {
      error?.(`FCM request error uid=${uid}: ${err.message}`);
    }
  }
}

module.exports = { sendToUsers };
