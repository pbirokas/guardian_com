const { Client, Databases, Query, Permission, Role } = require('node-appwrite');
const { sendToUsers } = require('./fcm');

const DB_ID = 'guardian';
const COL_MEMBERS = 'members';
const COL_ORGANIZATIONS = 'organizations';
const COL_REPORTS = 'reports';

module.exports = async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const db = new Databases(client);

  const report = req.body;
  if (!report || !report.$id) {
    error('No document in payload');
    return res.empty();
  }

  const { orgId, orgAdminUid, messageSenderName, messageText, convId } = report;
  if (!orgId || !orgAdminUid) {
    error('Missing orgId or orgAdminUid');
    return res.empty();
  }

  // Update-Event (z. B. „als geprüft markiert"): nur den Zähler neu berechnen.
  // Der Client darf das Org-Dokument nicht mehr selbst schreiben (keine
  // Collection-Level-Update-Rechte). Recount statt ±1 → idempotent, heilt Drift.
  // Unsere eigene ACL-Änderung unten löst ebenfalls ein Update-Event aus —
  // harmlos, da nur der Zähler (Org-Doc) geschrieben wird, nie der Report.
  const event = req.headers['x-appwrite-event'] || '';
  if (event.endsWith('.update')) {
    await recountPendingReports(db, orgId, log, error);
    return res.empty();
  }

  // Admin + alle Moderatoren ermitteln
  const alertUids = [orgAdminUid];

  const membersResult = await db.listDocuments(DB_ID, COL_MEMBERS, [
    Query.equal('orgId', orgId),
    Query.equal('role', 'moderator'),
    Query.limit(200),
  ]);
  membersResult.documents.forEach((doc) => {
    if (!alertUids.includes(doc.uid)) alertUids.push(doc.uid);
  });

  // Report-ACL auf die Aufsicht (Admin + Moderatoren) beschränken. Der Melder
  // kann diese Rollen selbst nicht setzen (Appwrite: Client darf nur eigene
  // Rollen granten), daher überschreiben wir die client-gesetzte ACL hier
  // serverseitig. Zusätzlich darf der Melder seine eigene Meldung lesen.
  const perms = [];
  for (const uid of alertUids) {
    perms.push(Permission.read(Role.user(uid)));
    perms.push(Permission.update(Role.user(uid)));
  }
  if (report.reportedByUid) {
    perms.push(Permission.read(Role.user(report.reportedByUid)));
  }
  try {
    await db.updateDocument(DB_ID, COL_REPORTS, report.$id, {}, perms);
    log(`Report ${report.$id}: ACL auf ${alertUids.length} Aufsicht(en) gesetzt`);
  } catch (e) {
    error(`Report ${report.$id}: ACL konnte nicht gesetzt werden: ${e.message}`);
  }

  const body = messageText && messageText.length > 80
    ? messageText.substring(0, 80) + '…'
    : (messageText ?? '');

  await sendToUsers(
    db,
    alertUids,
    '🚩 Nachricht gemeldet',
    `${messageSenderName ?? 'Unbekannt'}: ${body}`,
    { convId: convId ?? '', reportId: report.$id },
    log,
    error,
  );

  log(`on-new-report: sent to ${alertUids.length} recipient(s) for report ${report.$id}`);

  // pendingReportsCount auf der Org neu berechnen → Badge aktualisiert sich per Org-Realtime.
  await recountPendingReports(db, orgId, log, error);

  return res.empty();
};

async function recountPendingReports(db, orgId, log, error) {
  try {
    const pending = await db.listDocuments(DB_ID, COL_REPORTS, [
      Query.equal('orgId', orgId),
      Query.equal('status', 'pending'),
      Query.limit(1),
    ]);
    const count = pending.total ?? 0;
    const org = await db.getDocument(DB_ID, COL_ORGANIZATIONS, orgId);
    if ((org.pendingReportsCount ?? 0) === count) return;
    await db.updateDocument(DB_ID, COL_ORGANIZATIONS, orgId, { pendingReportsCount: count });
    log(`Org ${orgId}: pendingReportsCount = ${count}`);
  } catch (e) {
    error(`Failed to recount pendingReportsCount: ${e.message}`);
  }
}
