const { Client, Databases, Query } = require('node-appwrite');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const COL_CONVERSATIONS = 'conversations';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  // Appwrite liefert nur den After-State — kein Before-After-Vergleich möglich.
  // Stattdessen: guardianUids für alle betroffenen Conversations neu berechnen.
  const member = req.body;
  if (!member || !member.$id) {
    error('No document in payload');
    return res.empty();
  }

  const orgId = member.orgId;
  const memberUid = member.uid;

  if (!orgId || !memberUid) {
    error(`Missing orgId or uid in member doc ${member.$id}`);
    return res.empty();
  }

  // Alle Conversations finden wo dieses Mitglied Teilnehmer ist
  const convsResult = await db.listDocuments(DB_ID, COL_CONVERSATIONS, [
    Query.equal('orgId', orgId),
    Query.contains('participantUids', memberUid),
    Query.limit(100),
  ]);

  if (convsResult.total === 0) {
    log(`No conversations found for member ${memberUid} in org ${orgId}`);
    return res.empty();
  }

  log(`Found ${convsResult.total} conversation(s) for member ${memberUid}`);

  for (const conv of convsResult.documents) {
    const participantUids = conv.participantUids ?? [];

    // Alle Member-Docs der Teilnehmer laden
    const memberDocs = await Promise.all(
      participantUids.map((uid) =>
        db.listDocuments(DB_ID, COL_MEMBERS, [
          Query.equal('orgId', orgId),
          Query.equal('uid', uid),
          Query.limit(1),
        ]).then((r) => r.documents[0] ?? null)
      )
    );

    // guardianUids aller Teilnehmer zusammenführen (Duplikate entfernen)
    const recomputedGuardianUids = [...new Set(
      memberDocs
        .filter(Boolean)
        .flatMap((m) => m.guardianUids ?? [])
    )];

    // Nur updaten wenn sich etwas geändert hat
    const current = conv.guardianUids ?? [];
    const changed =
      recomputedGuardianUids.length !== current.length ||
      recomputedGuardianUids.some((uid) => !current.includes(uid)) ||
      current.some((uid) => !recomputedGuardianUids.includes(uid));

    if (!changed) {
      log(`Conv ${conv.$id}: guardianUids unchanged, skipping`);
      continue;
    }

    try {
      await db.updateDocument(DB_ID, COL_CONVERSATIONS, conv.$id, {
        guardianUids: recomputedGuardianUids,
      });
      log(`Conv ${conv.$id}: guardianUids updated to [${recomputedGuardianUids.join(', ')}]`);
    } catch (err) {
      error(`Failed to update conv ${conv.$id}: ${err.message}`);
    }
  }

  return res.empty();
};
