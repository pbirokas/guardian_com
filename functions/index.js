const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getAuth } = require('firebase-admin/auth');
const nodemailer = require('nodemailer');

const gmailAppPassword = defineSecret('GMAIL_APP_PASSWORD');

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
 * Checks whether the cooldown for a given interval has passed.
 * Returns true if notification should be sent (cooldown elapsed or no prior timestamp).
 */
function cooldownElapsed(interval, lastAlertTs) {
  if (interval === 'always') return true;
  if (!lastAlertTs) return true; // no prior timestamp → always send first one
  const cooldownMs = interval === 'hourly' ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
  return Date.now() - lastAlertTs.toMillis() >= cooldownMs;
}

/**
 * Triggered when a new message is created in any conversation.
 *
 * Block 1 – Standard message notification:
 *   Respects notificationsEnabled (per-org) and messageAlertInterval
 *   (per-org override, falls back to global notificationSettings.newMessagesInterval).
 *   Tracks lastMessageAlertAt.{convId} in the member doc for cooldown enforcement.
 *
 * Block 2 – Guardian child-activity notification:
 *   Unchanged logic; reuses already-loaded memberMap.
 *
 * Block 3 – Keyword monitoring:
 *   Reuses memberMap; loads tokens for non-participant alertees on demand.
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
    if (conv.status !== 'approved') return;

    const orgId = conv.orgId;
    const participantUids = conv.participantUids ?? [];
    const recipientUids = participantUids.filter((uid) => uid !== senderId);

    // ── Load member docs for the whole org upfront ──────────────────────────
    // Used by all three blocks. Avoids redundant Firestore reads.
    const memberMap = {};
    if (orgId) {
      const membersSnap = await db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .get();
      membersSnap.docs.forEach((doc) => { memberMap[doc.id] = doc.data(); });
    }

    // ── Load user docs for all recipients in one batch ───────────────────────
    // Provides FCM tokens + global notification settings.
    const userSnaps = await Promise.all(
      recipientUids.map((uid) => db.collection('users').doc(uid).get())
    );
    const userMap = {};
    userSnaps.forEach((snap) => { if (snap.exists) userMap[snap.id] = snap.data(); });

    const senderName = userMap[senderId]
      ? (userMap[senderId].displayName ?? 'Unbekannt')
      : (await db.collection('users').doc(senderId).get().then((s) =>
          s.exists ? (s.data().displayName ?? 'Unbekannt') : 'Unbekannt'
        ));

    const chatTitle = conv.name ?? senderName;
    const notifTitle = conv.name ? `${conv.name}: ${senderName}` : senderName;
    const notifBody = text.length > 100 ? text.substring(0, 100) + '…' : text;

    // ── Block 1: Standard message notifications ──────────────────────────────
    const tokensToNotify = [];
    const cooldownUpdateUids = []; // UIDs whose lastMessageAlertAt needs updating

    for (const uid of recipientUids) {
      const memberData = memberMap[uid];
      const userData = userMap[uid];
      if (!userData?.fcmToken) continue;

      // Per-org mute (bell toggle)
      if (memberData?.notificationsEnabled === false) continue;

      // Effective interval: per-org override → global setting → default 'always'
      const interval =
        memberData?.messageAlertInterval ??
        userData?.notificationSettings?.newMessagesInterval ??
        'always';

      if (interval === 'never') continue;

      // Cooldown check (only for throttled intervals with an org member doc)
      if (interval !== 'always' && memberData) {
        const lastAlertTs = memberData.lastMessageAlertAt?.[convId];
        if (!cooldownElapsed(interval, lastAlertTs)) {
          console.log(`Skipping notification for ${uid} (interval=${interval}, cooldown active)`);
          continue;
        }
      }

      tokensToNotify.push(userData.fcmToken);

      if (interval !== 'always' && orgId && memberData) {
        cooldownUpdateUids.push(uid);
      }
    }

    if (tokensToNotify.length > 0) {
      await sendToTokens(tokensToNotify, notifTitle, notifBody, { convId, chatTitle });
      console.log(`Sent ${tokensToNotify.length} message notification(s) for conv ${convId}`);
    }

    // Persist lastMessageAlertAt for throttled recipients
    if (cooldownUpdateUids.length > 0) {
      await Promise.all(
        cooldownUpdateUids.map((uid) =>
          db
            .collection('organizations')
            .doc(orgId)
            .collection('members')
            .doc(uid)
            .update({ [`lastMessageAlertAt.${convId}`]: new Date() })
        )
      );
    }

    // ── Block 2: Guardian child-activity notification ────────────────────────
    if (orgId) {
      const childUids = participantUids.filter((uid) => memberMap[uid]?.role === 'child');

      for (const childUid of childUids) {
        const childData = memberMap[childUid];
        const guardianUidList = childData?.guardianUids ?? [];
        if (guardianUidList.length === 0) continue;

        for (const guardianUid of guardianUidList) {
          if (guardianUid === senderId) continue;
          const guardianData = memberMap[guardianUid];
          if (!guardianData) continue;

          const interval = guardianData.childAlertInterval ?? 'hourly';
          if (interval === 'never') continue;

          const lastAlertTs = guardianData.lastChildAlertAt?.[childUid];
          if (!cooldownElapsed(interval, lastAlertTs)) continue;

          // Token: use userMap if guardian is a participant, else load on demand
          let guardianToken = userMap[guardianUid]?.fcmToken;
          if (!guardianToken) {
            const snap = await db.collection('users').doc(guardianUid).get();
            guardianToken = snap.exists ? snap.data().fcmToken : null;
          }

          if (guardianToken) {
            const childName = memberMap[childUid]?.displayName ?? 'Kind';
            const action =
              senderId === childUid
                ? 'hat eine Nachricht gesendet'
                : 'hat eine Nachricht erhalten';
            await sendToTokens(
              [guardianToken],
              `Kind-Aktivität: ${childName}`,
              `${childName} ${action} in ${chatTitle}`,
              { convId, chatTitle }
            );
          }

          await db
            .collection('organizations')
            .doc(orgId)
            .collection('members')
            .doc(guardianUid)
            .update({ [`lastChildAlertAt.${childUid}`]: new Date() });
        }
      }
    }

    // ── Block 3: Keyword monitoring ──────────────────────────────────────────
    if (!orgId) return;

    const orgSnap = await db.collection('organizations').doc(orgId).get();
    if (!orgSnap.exists) return;
    const org = orgSnap.data();

    const keywords = (org.keywords ?? [])
      .map((k) => k.toLowerCase().trim())
      .filter((k) => k.length > 0);
    if (keywords.length === 0) return;

    const textLower = text.toLowerCase();
    const matchedKeyword = keywords.find((kw) => textLower.includes(kw));
    if (!matchedKeyword) return;

    console.log(`Keyword "${matchedKeyword}" found in conv ${convId}`);

    // Collect moderators + guardians + admin (excluding sender)
    const alertUids = Object.entries(memberMap)
      .filter(([uid, data]) =>
        (data.role === 'moderator' || data.role === 'guardian') && uid !== senderId
      )
      .map(([uid]) => uid);

    if (org.adminUid && org.adminUid !== senderId && !alertUids.includes(org.adminUid)) {
      alertUids.push(org.adminUid);
    }
    if (alertUids.length === 0) return;

    // Build token list, using userMap cache first, loading missing on demand
    const cachedTokens = alertUids
      .filter((uid) => userMap[uid]?.fcmToken)
      .map((uid) => userMap[uid].fcmToken);

    const missingUids = alertUids.filter((uid) => !userMap[uid]);
    const loadedTokens = missingUids.length > 0 ? await getTokensForUids(missingUids) : [];

    const alertTokens = [...cachedTokens, ...loadedTokens];
    if (alertTokens.length === 0) return;

    await sendToTokens(
      alertTokens,
      '⚠️ Keyword erkannt',
      `"${matchedKeyword}" in ${chatTitle}: ${notifBody}`,
      { convId, chatTitle, keyword: matchedKeyword }
    );
    console.log(`Sent ${alertTokens.length} keyword alert(s) for keyword "${matchedKeyword}"`);
  }
);

/**
 * Triggered when a new invitation is created.
 *
 * - If the invited email is NOT yet registered: sends an invitation email via Gmail SMTP.
 * - If the role is 'child': additionally notifies all listed guardians via push.
 */
exports.onNewInvitation = onDocumentCreated(
  { document: 'invitations/{inviteId}', secrets: [gmailAppPassword] },
  async (event) => {
    const invite = event.data.data();
    const { email, orgName, role, guardianUids, inviterName } = invite;

    // ── Check whether the invited email is already registered ───────────────
    let userExists = false;
    try {
      await getAuth().getUserByEmail(email);
      userExists = true;
    } catch (err) {
      // auth/user-not-found is expected for unregistered users
      if (err.code !== 'auth/user-not-found') {
        console.error('Error looking up user by email:', err);
      }
    }

    // ── Send invitation email to unregistered users ──────────────────────────
    if (!userExists) {
      const password = gmailAppPassword.value();
      if (password) {
        const transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: { user: 'savespacedev@gmail.com', pass: password },
        });

        const roleLabel = {
          admin: 'Administrator',
          moderator: 'Moderator',
          member: 'Mitglied',
          child: 'Kind',
        }[role] ?? role;

        const inviterLine = inviterName
          ? `<p>${inviterName} hat dich eingeladen.</p>`
          : '';

        const html = `
<!DOCTYPE html>
<html lang="de">
<head><meta charset="UTF-8" /></head>
<body style="font-family:sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1a1a1a">
  <h2 style="color:#1565C0">Einladung zu Guardian Com</h2>
  ${inviterLine}
  <p>Du wurdest als <strong>${roleLabel}</strong> zur Organisation <strong>${orgName}</strong> eingeladen.</p>
  <p>Lade die <strong>Guardian Com</strong>-App herunter und melde dich mit dieser E-Mail-Adresse an, um die Einladung anzunehmen:</p>
  <p style="margin:24px 0">
    <a href="https://play.google.com/store/apps/details?id=com.guardianapp.guardian_app"
       style="background:#1565C0;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:bold">
      App herunterladen
    </a>
  </p>
  <p style="font-size:0.85rem;color:#666">
    Wenn du diese Einladung nicht erwartet hast, kannst du diese E-Mail ignorieren.
  </p>
</body>
</html>`;

        try {
          await transporter.sendMail({
            from: '"Guardian Com" <savespacedev@gmail.com>',
            to: email,
            subject: `Einladung zu "${orgName}" auf Guardian Com`,
            html,
          });
          console.log(`Invitation email sent to ${email} for org "${orgName}"`);
        } catch (mailErr) {
          console.error('Failed to send invitation email:', mailErr);
        }
      } else {
        console.warn('GMAIL_APP_PASSWORD secret not available — skipping invitation email');
      }
    }

    // ── Notify guardians for child invitations ───────────────────────────────
    if (role !== 'child' || !guardianUids || guardianUids.length === 0) return;

    const tokens = await getTokensForUids(guardianUids);
    if (tokens.length === 0) return;

    await sendToTokens(
      tokens,
      '👶 Kind-Einladung ausstehend',
      `${email} wurde als Kind in "${orgName}" eingeladen. Bitte stimme zu.`,
      { inviteId: event.params.inviteId }
    );
    console.log(`Sent ${tokens.length} guardian invitation notification(s) for ${email}`);
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

/**
 * Callable function: processes all pending invitations for the calling user.
 * Runs with Admin SDK — bypasses Security Rules.
 * Called from the Flutter app on every login.
 */
exports.processMyInvitations = onCall(async (request) => {
  const uid = request.auth?.uid;
  const email = request.auth?.token?.email;

  if (!uid || !email) {
    throw new Error('Unauthenticated');
  }

  const normalizedEmail = email.toLowerCase().trim();
  console.log(`processMyInvitations: uid=${uid} email=${normalizedEmail}`);

  const invitesSnap = await db
    .collection('invitations')
    .where('email', '==', normalizedEmail)
    .where('status', '==', 'pending')
    .get();

  console.log(`Found ${invitesSnap.docs.length} pending invitation(s)`);

  for (const invite of invitesSnap.docs) {
    const data = invite.data();
    const orgId = data.orgId;
    const role = data.role ?? 'member';
    const guardianUids = data.guardianUids ?? [];
    const isChild = role === 'child';

    const orgDoc = await db.collection('organizations').doc(orgId).get();
    if (!orgDoc.exists) {
      await invite.ref.update({ status: 'invalid' });
      console.log(`Org ${orgId} not found, invite ${invite.id} marked invalid`);
      continue;
    }

    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data();

    const memberRef = db
      .collection('organizations')
      .doc(orgId)
      .collection('members')
      .doc(uid);
    const existingMember = await memberRef.get();

    if (existingMember.exists) {
      await invite.ref.update({ status: 'accepted' });
      console.log(`Already member, invite ${invite.id} marked accepted`);
      continue;
    }

    const memberStatus = isChild ? 'pending' : 'active';

    const batch = db.batch();
    batch.set(memberRef, {
      displayName: userData.displayName ?? normalizedEmail,
      email: userData.email ?? normalizedEmail,
      ...(userData.photoUrl ? { photoUrl: userData.photoUrl } : {}),
      role,
      joinedAt: Timestamp.now(),
      guardianUids: isChild ? guardianUids : [],
      status: memberStatus,
      childAlertInterval: 'hourly',
    });

    if (!isChild) {
      batch.update(db.collection('organizations').doc(orgId), {
        memberUids: FieldValue.arrayUnion(uid),
      });
      batch.update(db.collection('users').doc(uid), {
        memberships: FieldValue.arrayUnion({ orgId, role }),
      });
    } else {
      batch.update(db.collection('users').doc(uid), { isChild: true });
    }

    batch.update(invite.ref, { status: 'accepted' });
    await batch.commit();
    console.log(`Invite ${invite.id} processed (role=${role})`);
  }

  return { processed: invitesSnap.docs.length };
});
