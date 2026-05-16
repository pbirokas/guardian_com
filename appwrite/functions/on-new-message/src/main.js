const { Client, Databases, Query } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_ORGANIZATIONS = 'organizations';
const COL_MEMBERS = 'members';
const COL_CONVERSATIONS = 'conversations';

function cooldownElapsed(interval, lastAlertIso) {
  if (interval === 'always') return true;
  if (!lastAlertIso) return true;
  const cooldownMs = interval === 'hourly' ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
  return Date.now() - new Date(lastAlertIso).getTime() >= cooldownMs;
}

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const message = req.body;
  if (!message || !message.$id) {
    error('No document in payload');
    return res.empty();
  }

  // System-Nachrichten ignorieren
  if (message.type === 'system' || message.senderUid === 'system') {
    return res.empty();
  }

  const { convId, orgId, senderUid } = message;
  const text = message.text ?? '';

  // Conversation laden
  let conv;
  try {
    conv = await db.getDocument(DB_ID, COL_CONVERSATIONS, convId);
  } catch (_) {
    error(`Conversation ${convId} not found`);
    return res.empty();
  }
  if (conv.status !== 'approved') return res.empty();

  const participantUids = conv.participantUids ?? [];
  const recipientUids = participantUids.filter((uid) => uid !== senderUid);
  if (recipientUids.length === 0) return res.empty();

  // Alle Member-Docs für die Org laden (für alle 3 Blöcke benötigt)
  const memberMap = {}; // uid → member doc
  if (orgId) {
    let lastMemberId = null;
    while (true) {
      const queries = [Query.equal('orgId', orgId), Query.limit(500)];
      if (lastMemberId) queries.push(Query.cursorAfter(lastMemberId));
      const membersResult = await db.listDocuments(DB_ID, COL_MEMBERS, queries);
      membersResult.documents.forEach((doc) => { memberMap[doc.uid] = doc; });
      if (membersResult.documents.length < 500) break;
      lastMemberId = membersResult.documents[membersResult.documents.length - 1].$id;
    }
  }

  // User-Docs für Empfänger laden (FCM-Token + globale Einstellungen)
  const userSnaps = await Promise.all(
    recipientUids.map((uid) => db.getDocument(DB_ID, COL_USERS, uid).catch(() => null))
  );
  const userMap = {};
  userSnaps.forEach((snap) => { if (snap) userMap[snap.$id] = snap; });

  // Absender-Name ermitteln
  let senderName = userMap[senderUid]?.displayName;
  if (!senderName) {
    const senderSnap = await db.getDocument(DB_ID, COL_USERS, senderUid).catch(() => null);
    senderName = senderSnap?.displayName ?? 'Unbekannt';
  }

  const chatTitle = conv.name ?? senderName;
  const notifTitle = conv.name ? `${conv.name}: ${senderName}` : senderName;
  const notifBody = text.length > 100 ? text.substring(0, 100) + '…' : text;

  // ── Block 1: Standard-Nachrichten-Benachrichtigungen ─────────────────────────
  const tokensToNotify = [];
  const cooldownUpdateUids = [];

  for (const uid of recipientUids) {
    const memberData = memberMap[uid];
    const userData = userMap[uid];
    if (!userData?.fcmToken) continue;
    if (memberData?.notificationsEnabled === false) continue;

    const interval =
      memberData?.messageAlertInterval ??
      userData?.notificationSettings?.newMessagesInterval ??
      'always';
    if (interval === 'never') continue;

    if (interval !== 'always' && memberData) {
      const lastAlertMap = memberData.lastMessageAlertAtJson
        ? JSON.parse(memberData.lastMessageAlertAtJson)
        : {};
      if (!cooldownElapsed(interval, lastAlertMap[convId])) {
        log(`Skipping ${uid} (interval=${interval}, cooldown active)`);
        continue;
      }
    }

    tokensToNotify.push(uid);
    if (interval !== 'always' && orgId && memberData) cooldownUpdateUids.push(uid);
  }

  if (tokensToNotify.length > 0) {
    await sendToUsers(db, tokensToNotify, notifTitle, notifBody, { convId, chatTitle }, log, error);
    log(`Block1: sent ${tokensToNotify.length} message notification(s)`);
  }

  // Cooldown-Timestamps persistieren
  if (cooldownUpdateUids.length > 0) {
    await Promise.all(
      cooldownUpdateUids.map(async (uid) => {
        const memberId = `${orgId}_${uid}`;
        const memberData = memberMap[uid];
        const lastAlertMap = memberData?.lastMessageAlertAtJson
          ? JSON.parse(memberData.lastMessageAlertAtJson)
          : {};
        lastAlertMap[convId] = new Date().toISOString();
        try {
          await db.updateDocument(DB_ID, COL_MEMBERS, memberId, {
            lastMessageAlertAtJson: JSON.stringify(lastAlertMap),
          });
        } catch (err) {
          error(`Failed to update lastMessageAlertAtJson for ${uid}: ${err.message}`);
        }
      })
    );
  }

  // ── Block 2: Guardian-Kind-Aktivitäts-Benachrichtigung ───────────────────────
  if (orgId) {
    const childUids = participantUids.filter((uid) => memberMap[uid]?.role === 'child');

    for (const childUid of childUids) {
      const childData = memberMap[childUid];
      const guardianUidList = childData?.guardianUids ?? [];

      for (const guardianUid of guardianUidList) {
        if (guardianUid === senderUid) continue;
        const guardianData = memberMap[guardianUid];
        if (!guardianData) continue;

        const interval = guardianData.childAlertInterval ?? 'hourly';
        if (interval === 'never') continue;

        const lastAlertMap = guardianData.lastChildAlertAtJson
          ? JSON.parse(guardianData.lastChildAlertAtJson)
          : {};
        if (!cooldownElapsed(interval, lastAlertMap[childUid])) continue;

        const childName = memberMap[childUid]?.displayName ?? 'Kind';
        const action = senderUid === childUid
          ? 'hat eine Nachricht gesendet'
          : 'hat eine Nachricht erhalten';

        await sendToUsers(
          db,
          [guardianUid],
          `Kind-Aktivität: ${childName}`,
          `${childName} ${action} in ${chatTitle}`,
          { convId, chatTitle },
          log,
          error,
        );

        // Cooldown-Timestamp aktualisieren
        const guardianMemberId = `${orgId}_${guardianUid}`;
        lastAlertMap[childUid] = new Date().toISOString();
        try {
          await db.updateDocument(DB_ID, COL_MEMBERS, guardianMemberId, {
            lastChildAlertAtJson: JSON.stringify(lastAlertMap),
          });
        } catch (err) {
          error(`Failed to update lastChildAlertAtJson for ${guardianUid}: ${err.message}`);
        }
      }
    }
  }

  // ── Block 3: Keyword-Monitoring ───────────────────────────────────────────────
  if (!orgId) return res.empty();

  let org;
  try {
    org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
  } catch (_) {
    return res.empty();
  }

  const keywords = (org.keywords ?? [])
    .map((k) => k.toLowerCase().trim())
    .filter((k) => k.length > 0);
  if (keywords.length === 0) return res.empty();

  const textLower = text.toLowerCase();
  const matchedKeyword = keywords.find((kw) => textLower.includes(kw));
  if (!matchedKeyword) return res.empty();

  log(`Keyword "${matchedKeyword}" found in conv ${convId}`);

  const alertUids = Object.entries(memberMap)
    .filter(([uid, data]) => data.role === 'moderator' && uid !== senderUid)
    .map(([uid]) => uid);

  if (org.adminUid && org.adminUid !== senderUid && !alertUids.includes(org.adminUid)) {
    alertUids.push(org.adminUid);
  }
  if (alertUids.length === 0) return res.empty();

  await sendToUsers(
    db,
    alertUids,
    '⚠️ Keyword erkannt',
    `"${matchedKeyword}" in ${chatTitle}: ${notifBody}`,
    { convId, chatTitle, keyword: matchedKeyword },
    log,
    error,
  );

  log(`Block3: sent ${alertUids.length} keyword alert(s) for "${matchedKeyword}"`);
  return res.empty();
};
