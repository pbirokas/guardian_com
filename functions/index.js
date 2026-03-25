const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();

/**
 * Sends an FCM push notification to a list of FCM tokens.
 */
async function sendToTokens(tokens, title, body, data) {
  const sendPromises = tokens.map((token) =>
    getMessaging()
      .send({
        token,
        notification: { title, body },
        data,
        android: {
          notification: { channelId: 'guardian_messages', priority: 'high' },
        },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      })
      .catch((err) => {
        console.error(`Failed to send to token ${token.substring(0, 10)}...:`, err.message);
      })
  );
  await Promise.all(sendPromises);
}

/**
 * Loads FCM tokens for a list of UIDs.
 */
async function getTokensForUids(uids) {
  if (uids.length === 0) return [];
  const snaps = await Promise.all(uids.map((uid) => db.collection('users').doc(uid).get()));
  return snaps
    .map((snap) => (snap.exists ? snap.data().fcmToken : null))
    .filter((t) => t != null && t !== '');
}

/**
 * Triggered when a new message is created in any conversation.
 * 1. Sends FCM push notification to all participants except the sender.
 * 2. If the org has keywords configured, checks the message text and notifies
 *    guardians + moderators when a keyword is found.
 */
exports.onNewMessage = onDocumentCreated(
  'conversations/{convId}/messages/{msgId}',
  async (event) => {
    const message = event.data.data();
    const { convId } = event.params;

    const senderId = message.senderUid;
    const text = message.text ?? '';

    // Load conversation
    const convSnap = await db.collection('conversations').doc(convId).get();
    if (!convSnap.exists) return;
    const conv = convSnap.data();

    // Only process approved conversations
    if (conv.status !== 'approved') return;

    // Load sender display name
    const senderSnap = await db.collection('users').doc(senderId).get();
    const senderName = senderSnap.exists
      ? (senderSnap.data().displayName ?? 'Unbekannt')
      : 'Unbekannt';

    const chatTitle = conv.name ?? senderName;
    const notifTitle = conv.name ? `${conv.name}: ${senderName}` : senderName;
    const notifBody = text.length > 100 ? text.substring(0, 100) + '…' : text;

    // --- 1. Standard message notification to participants ---
    const participantUids = conv.participantUids ?? [];
    const recipientUids = participantUids.filter((uid) => uid !== senderId);

    if (recipientUids.length > 0) {
      const tokens = await getTokensForUids(recipientUids);
      if (tokens.length > 0) {
        await sendToTokens(tokens, notifTitle, notifBody, { convId, chatTitle });
        console.log(`Sent ${tokens.length} message notification(s) for conv ${convId}`);
      }
    }

    // --- 2. Guardian child-activity notification ---
    const orgId = conv.orgId;
    if (orgId) {
      const membersSnap = await db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .get();

      const memberMap = {};
      membersSnap.docs.forEach((doc) => { memberMap[doc.id] = doc.data(); });

      // Find children involved in this conversation
      const childUids = participantUids.filter((uid) => memberMap[uid]?.role === 'child');

      for (const childUid of childUids) {
        const childData = memberMap[childUid];
        const guardianUid = childData?.guardianUid;
        if (!guardianUid || guardianUid === senderId) continue;

        const guardianData = memberMap[guardianUid];
        if (!guardianUid || !guardianData) continue;

        const interval = guardianData.childAlertInterval ?? 'hourly';
        if (interval === 'never') continue;

        // Check cooldown
        const lastAlertTs = guardianData.lastChildAlertAt?.[childUid];
        if (interval !== 'always' && lastAlertTs) {
          const lastAlertMs = lastAlertTs.toMillis();
          const nowMs = Date.now();
          const cooldownMs = interval === 'hourly' ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
          if (nowMs - lastAlertMs < cooldownMs) continue;
        }

        // Send notification to guardian
        const guardianUserSnap = await db.collection('users').doc(guardianUid).get();
        const guardianToken = guardianUserSnap.exists ? guardianUserSnap.data().fcmToken : null;
        if (guardianToken) {
          const childName = memberMap[childUid]?.displayName ?? 'Kind';
          const action = senderId === childUid ? 'hat eine Nachricht gesendet' : 'hat eine Nachricht erhalten';
          await sendToTokens(
            [guardianToken],
            `Kind-Aktivität: ${childName}`,
            `${childName} ${action} in ${chatTitle}`,
            { convId, chatTitle }
          );
        }

        // Update lastChildAlertAt on guardian member doc
        await db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(guardianUid)
          .update({ [`lastChildAlertAt.${childUid}`]: new Date() });
      }
    }

    // --- 3. Keyword monitoring ---
    if (!orgId) return;

    const orgSnap = await db.collection('organizations').doc(orgId).get();
    if (!orgSnap.exists) return;
    const org = orgSnap.data();

    const keywords = (org.keywords ?? []).map((k) => k.toLowerCase().trim()).filter((k) => k.length > 0);
    if (keywords.length === 0) return;

    const textLower = text.toLowerCase();
    const matchedKeyword = keywords.find((kw) => textLower.includes(kw));
    if (!matchedKeyword) return;

    console.log(`Keyword "${matchedKeyword}" found in conv ${convId}`);

    // Collect UIDs to notify: guardians + moderators (excluding the sender)
    const membersSnap = await db
      .collection('organizations')
      .doc(orgId)
      .collection('members')
      .get();

    const alertUids = membersSnap.docs
      .filter((doc) => {
        const role = doc.data().role;
        return (role === 'moderator' || role === 'guardian') && doc.id !== senderId;
      })
      .map((doc) => doc.id);

    // Also include the org admin
    if (org.adminUid && org.adminUid !== senderId && !alertUids.includes(org.adminUid)) {
      alertUids.push(org.adminUid);
    }

    if (alertUids.length === 0) return;

    const alertTokens = await getTokensForUids(alertUids);
    if (alertTokens.length === 0) return;

    const alertTitle = '⚠️ Keyword erkannt';
    const alertBody = `"${matchedKeyword}" in ${chatTitle}: ${notifBody}`;

    await sendToTokens(alertTokens, alertTitle, alertBody, { convId, chatTitle, keyword: matchedKeyword });
    console.log(`Sent ${alertTokens.length} keyword alert(s) for keyword "${matchedKeyword}"`);
  }
);

/**
 * Triggered when a new report is created.
 * Sends FCM push notification to the org admin and all moderators.
 */
exports.onNewReport = onDocumentCreated('reports/{reportId}', async (event) => {
  const report = event.data.data();
  const { orgId, orgAdminUid, messageSenderName, messageText, convId } = report;

  if (!orgId || !orgAdminUid) return;

  // Collect admin + moderator UIDs
  const membersSnap = await db
    .collection('organizations')
    .doc(orgId)
    .collection('members')
    .get();

  const alertUids = [orgAdminUid];
  membersSnap.docs.forEach((doc) => {
    if (doc.data().role === 'moderator' && !alertUids.includes(doc.id)) {
      alertUids.push(doc.id);
    }
  });

  const tokens = await getTokensForUids(alertUids);
  if (tokens.length === 0) return;

  const body = messageText.length > 80 ? messageText.substring(0, 80) + '…' : messageText;
  await sendToTokens(
    tokens,
    '🚩 Nachricht gemeldet',
    `${messageSenderName}: ${body}`,
    { convId: convId ?? '', reportId: event.params.reportId }
  );
  console.log(`Sent ${tokens.length} report notification(s) for report ${event.params.reportId}`);
});
