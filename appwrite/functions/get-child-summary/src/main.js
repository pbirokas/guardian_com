const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_USERS = 'users';
const COL_ORGANIZATIONS = 'organizations';
const COL_CONVERSATIONS = 'conversations';
const COL_MESSAGES = 'chat_messages';

module.exports = async ({ req, res, log, error }) => {
  const uid = req.headers['x-appwrite-user-id'];
  if (!uid) return res.json({ error: 'Unauthenticated' }, 401);

  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const body = req.body ?? {};
  const { childUid, period } = body;

  if (!childUid || typeof childUid !== 'string') {
    return res.json({ error: 'childUid required' }, 400);
  }
  if (!['24h', '7d'].includes(period)) {
    return res.json({ error: 'period must be 24h or 7d' }, 400);
  }

  // Kind-Doc laden und Eltern-Kind-Beziehung prüfen
  let childData;
  try {
    childData = await db.getDocument(DB_ID, COL_USERS, childUid);
  } catch (_) {
    return res.json({ error: 'Child not found' }, 404);
  }

  if (!(childData.verifiedParentUids ?? []).includes(uid)) {
    return res.json({ error: 'Not a verified parent of this child' }, 403);
  }

  // Cutoff berechnen
  const cutoff = new Date();
  if (period === '24h') cutoff.setHours(cutoff.getHours() - 24);
  else cutoff.setDate(cutoff.getDate() - 7);
  const cutoffIso = cutoff.toISOString();

  // Alle Conversations des Kindes laden (kein Index auf participantUids → Query.contains)
  const convsResult = await db.listDocuments(DB_ID, COL_CONVERSATIONS, [
    Query.contains('participantUids', childUid),
    Query.limit(200),
  ]);

  if (convsResult.documents.length === 0) {
    return res.json({
      childUid,
      childName: childData.displayName || childData.email || '',
      period,
      generatedAt: Date.now(),
      orgs: [],
    });
  }

  // Nach orgId gruppieren
  const orgConvMap = {};
  for (const conv of convsResult.documents) {
    if (!conv.orgId) continue;
    (orgConvMap[conv.orgId] ??= []).push(conv);
  }

  const orgIds = Object.keys(orgConvMap);

  // Org-Namen laden
  const orgDocs = await Promise.all(
    orgIds.map((id) => db.getDocument(DB_ID, COL_ORGANIZATIONS, id).catch(() => null))
  );
  const orgNameMap = Object.fromEntries(
    orgIds.map((id, i) => [id, orgDocs[i]?.name || id])
  );

  // User-Namen für 1:1-Chat-Fallback vorbereiten
  const unresolvedUids = [...new Set(
    convsResult.documents
      .filter((d) => {
        if (d.isGroup) return false;
        const names = d.personalNamesJson ? JSON.parse(d.personalNamesJson) : {};
        return !names[childUid];
      })
      .map((d) => (d.participantUids ?? []).find((u) => u !== childUid))
      .filter(Boolean),
  )];
  const peerDocs = await Promise.all(
    unresolvedUids.map((id) => db.getDocument(DB_ID, COL_USERS, id).catch(() => null))
  );
  const userNameCache = Object.fromEntries(
    unresolvedUids.map((id, i) => [
      id,
      peerDocs[i]?.displayName || peerDocs[i]?.email || id,
    ])
  );

  // Pro Org: Nachrichten zählen
  const orgResultsRaw = await Promise.all(
    orgIds.map(async (orgId) => {
      const convDocs = orgConvMap[orgId];

      const msgSnaps = await Promise.all(
        convDocs.map((c) =>
          db.listDocuments(DB_ID, COL_MESSAGES, [
            Query.equal('convId', c.$id),
            Query.greaterThanEqual('sentAt', cutoffIso),
            Query.limit(1000),
          ])
        )
      );

      let orgSent = 0, orgReceived = 0, orgLastActive = null;
      const chatResults = [];

      for (let i = 0; i < convDocs.length; i++) {
        const convData = convDocs[i];
        const messages = msgSnaps[i].documents.filter((m) => !m.deletedAt);
        if (messages.length === 0) continue;

        const sent = messages.filter((m) => m.senderUid === childUid).length;
        const received = messages.length - sent;

        let lastActive = null;
        for (const m of messages) {
          const ms = m.sentAt ? new Date(m.sentAt).getTime() : 0;
          if (lastActive === null || ms > lastActive) lastActive = ms;
        }

        orgSent += sent;
        orgReceived += received;
        if (orgLastActive === null || lastActive > orgLastActive) orgLastActive = lastActive;

        // Chat-Name aus Sicht des Kindes
        let chatName = '';
        if (convData.isGroup) {
          chatName = convData.name || 'Gruppenchat';
        } else {
          const personalNames = convData.personalNamesJson
            ? JSON.parse(convData.personalNamesJson)
            : {};
          chatName = personalNames[childUid] || '';
          if (!chatName) {
            const otherUid = (convData.participantUids ?? []).find((u) => u !== childUid);
            if (otherUid) chatName = userNameCache[otherUid] || otherUid;
          }
        }

        chatResults.push({
          convId: convData.$id,
          chatName: chatName || '?',
          isGroup: convData.isGroup || false,
          sentCount: sent,
          receivedCount: received,
          lastActive,
        });
      }

      if (chatResults.length === 0) return null;

      chatResults.sort((a, b) => (b.lastActive ?? 0) - (a.lastActive ?? 0));
      return {
        orgId,
        orgName: orgNameMap[orgId],
        sentCount: orgSent,
        receivedCount: orgReceived,
        lastActive: orgLastActive,
        chats: chatResults,
      };
    })
  );

  const orgResults = orgResultsRaw.filter(Boolean);
  orgResults.sort((a, b) => (b.lastActive ?? 0) - (a.lastActive ?? 0));

  log(`get-child-summary: uid=${uid} childUid=${childUid} period=${period} orgs=${orgResults.length}`);

  return res.json({
    childUid,
    childName: childData.displayName || childData.email || '',
    period,
    generatedAt: Date.now(),
    orgs: orgResults,
  });
};
