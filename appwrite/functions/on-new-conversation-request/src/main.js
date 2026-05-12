const { Client, Databases } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_ORGANIZATIONS = 'organizations';
const COL_USERS = 'users';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const conv = req.body;
  if (!conv || !conv.$id) {
    error('No document in payload');
    return res.empty();
  }

  // Nur pending-Anfragen im Guardian-Modus
  if (conv.status !== 'pending') {
    log(`Status is "${conv.status}", skipping`);
    return res.empty();
  }

  const { orgId, requestedBy, participantUids, canApproveUids, guardianUids } = conv;
  const convId = conv.$id;

  // Angefragter Teilnehmer (nicht der Antragsteller)
  const targetUid = (participantUids ?? []).find((uid) => uid !== requestedBy) ?? null;

  const notifyUidSet = new Set([
    ...(canApproveUids ?? []),
    ...(guardianUids ?? []),
    ...(targetUid ? [targetUid] : []),
  ]);
  notifyUidSet.delete(requestedBy);

  if (notifyUidSet.size === 0) {
    log('No recipients, skipping');
    return res.empty();
  }

  // Org-Name + Antragsteller-Name parallel laden
  const [orgSnap, requesterSnap] = await Promise.all([
    db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId).catch(() => null),
    db.getDocument(DB_ID, COL_USERS, requestedBy).catch(() => null),
  ]);
  const orgName = orgSnap?.name ?? orgId;
  const requesterName = requesterSnap?.displayName ?? 'Unbekannt';

  // Pro Empfänger individuelle Nachricht senden
  const sends = [];
  for (const uid of notifyUidSet) {
    const isApprover = (canApproveUids ?? []).includes(uid);
    const isTarget = uid === targetUid;

    let title, body, data;
    if (isTarget) {
      title = `💬 Chat-Anfrage von ${requesterName}`;
      body = `${requesterName} möchte in "${orgName}" einen Chat mit dir starten.`;
      data = { convId, chatTitle: orgName };
    } else if (isApprover) {
      title = `💬 Chat-Anfrage in "${orgName}"`;
      body = `${requesterName} möchte einen Chat starten. Bitte genehmige oder lehne die Anfrage ab.`;
      data = { chatTitle: orgName };
    } else {
      // Guardian (nicht Approver, nicht Target)
      title = '💬 Chat-Anfrage (Kind-Aktivität)';
      body = `${requesterName} hat in "${orgName}" eine Chat-Anfrage gestellt.`;
      data = { chatTitle: orgName };
    }

    sends.push(sendToUsers(db, [uid], title, body, data, log, error));
  }

  await Promise.all(sends);
  log(`on-new-conversation-request: sent ${sends.length} notification(s) for conv ${convId}`);
  return res.empty();
};
