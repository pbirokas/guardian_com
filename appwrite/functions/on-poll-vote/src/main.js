const { Client, Databases } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_POLLS = 'polls';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const poll = req.body;
  if (!poll || !poll.$id) {
    error('No document in payload');
    return res.empty();
  }

  // Anonyme oder geschlossene Umfragen überspringen
  if (poll.isAnonymous || poll.isClosed) {
    log('Anonymous or closed poll, skipping');
    return res.empty();
  }

  const creatorUid = poll.createdBy;
  if (!creatorUid) return res.empty();

  // Aktuelle Stimmanzahl aus votesJson berechnen
  const votesMap = poll.votesJson ? JSON.parse(poll.votesJson) : {};
  const currentVoterCount = new Set(Object.values(votesMap).flat()).size;

  // Mit lastNotifiedVoterCount vergleichen — nur benachrichtigen wenn neue Stimme
  const lastNotified = poll.lastNotifiedVoterCount ?? 0;
  if (currentVoterCount <= lastNotified) {
    log(`No new voters (current=${currentVoterCount} lastNotified=${lastNotified}), skipping`);
    return res.empty();
  }

  const question = poll.question ?? '';
  const body = question.length > 80
    ? `Jemand hat an deiner Abstimmung abgestimmt: "${question.substring(0, 80)}…"`
    : `Jemand hat an deiner Abstimmung abgestimmt: "${question}"`;

  await sendToUsers(
    db,
    [creatorUid],
    '📊 Neue Abstimmungsteilnahme',
    body,
    { convId: poll.convId ?? '', pollId: poll.$id },
    log,
    error,
  );

  // lastNotifiedVoterCount aktualisieren (Best-Effort)
  try {
    await db.updateDocument(DB_ID, COL_POLLS, poll.$id, {
      lastNotifiedVoterCount: currentVoterCount,
    });
  } catch (err) {
    error(`Failed to update lastNotifiedVoterCount: ${err.message}`);
  }

  log(`on-poll-vote: notified creator ${creatorUid} for poll ${poll.$id}`);
  return res.empty();
};
