/**
 * Einmalige Migration: Chat-Berechtigungen vom offenen Modell (Role.users())
 * auf das Team-Modell umstellen.
 *
 * Modell (deckungsgleich mit Client + sync-* Functions):
 *   - Conversation-Team   id = convId           → Teilnehmer + Guardians
 *   - Org-Supervisor-Team id = `sup_<orgId>`    → Admin + Moderatoren
 *   - Conversation-ACL: read/update/delete = [team(convId), team(sup_orgId)]
 *   - Message-ACL:      read = [team(convId), team(sup_orgId), user(sender)]
 *                       update/delete = [user(sender), team(sup_orgId)]
 *   - Scheduled:        read/update/delete = user(sender)  (privater Entwurf)
 *   - Read-Receipts:    read/update/delete = user(uid)     (wie mark-as-read)
 *   - Claim-Requests:   read/update/delete = user(from), read/update = user(to)
 *                       (wie on-claim-request)
 *
 * Zusätzlich zählt jede Phase Dokumente mit BREITEN Rechten (`users`/`any`/
 * `guests`) in der ACL — die müssen vor dem Entzug der Collection-Rechte
 * (fix-permissions.js) auf 0 stehen, sonst bleiben sie trotzdem offen —
 * sowie Dokumente OHNE read-Recht (danach für Clients unsichtbar).
 *
 * Reihenfolge im Rollout (WICHTIG):
 *   1. Neue App mit erzwungenem Update veröffentlichen (minVersionCode).
 *   2. sync-* Functions deployen.
 *   3. ERST DANN dieses Skript ausführen (verschärft die ACLs rückwirkend).
 * Andernfalls verlieren noch laufende Alt-Clients (breite Reads) den Zugriff.
 *
 * Idempotent & wiederholbar. Standardmäßig Dry-Run.
 *
 * Nutzung:
 *   node harden-permissions.js                       (Dry-Run, nur zählen)
 *   node harden-permissions.js --confirm=<projectId> (führt die Migration aus)
 */

import { config } from 'dotenv';
import { Client, Databases, Teams, Permission, Role, Query } from 'node-appwrite';

config();

const DB_ID = 'guardian';
const COL_ORGS = 'organizations';
const COL_MEMBERS = 'members';
const COL_CONVERSATIONS = 'conversations';
const COL_MESSAGES = 'chat_messages';
const COL_SCHEDULED = 'scheduled_messages';
const COL_POLLS = 'polls';
const COL_REPORTS = 'reports';
const COL_RECEIPTS = 'read_receipts';
const COL_CLAIMS = 'claim_requests';

const projectId = process.env.APPWRITE_PROJECT_ID;
const confirmArg = process.argv.find((a) => a.startsWith('--confirm='));
const CONFIRMED = confirmArg && confirmArg.split('=')[1] === projectId;
const DRY = !CONFIRMED;

if (confirmArg && !CONFIRMED) {
  console.error(
    `✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`
  );
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const teams = new Teams(client);

const supTeamId = (orgId) => `sup_${orgId}`;

function convPerms(convId) {
  const c = Role.team(convId);
  return [Permission.read(c), Permission.update(c), Permission.delete(c)];
}

function msgPerms(convId, senderUid) {
  const perms = [Permission.read(Role.team(convId))];
  if (senderUid && senderUid !== 'system') {
    perms.push(Permission.read(Role.user(senderUid)));
    perms.push(Permission.update(Role.user(senderUid)));
    perms.push(Permission.delete(Role.user(senderUid)));
  }
  return perms;
}

function scheduledPerms(senderUid) {
  if (!senderUid) return [];
  const u = Role.user(senderUid);
  return [Permission.read(u), Permission.update(u), Permission.delete(u)];
}

function pollPerms(convId, createdBy) {
  const c = Role.team(convId);
  const perms = [Permission.read(c), Permission.update(c)];
  if (createdBy) perms.push(Permission.delete(Role.user(createdBy)));
  return perms;
}

function reportPerms(supervisorUids, reportedByUid) {
  const perms = [];
  for (const uid of supervisorUids) {
    perms.push(Permission.read(Role.user(uid)));
    perms.push(Permission.update(Role.user(uid)));
  }
  if (reportedByUid) perms.push(Permission.read(Role.user(reportedByUid)));
  return perms;
}

function receiptPerms(uid) {
  if (!uid) return [];
  const u = Role.user(uid);
  return [Permission.read(u), Permission.update(u), Permission.delete(u)];
}

function claimPerms(fromUid, toUid) {
  if (!fromUid || !toUid) return [];
  const f = Role.user(fromUid);
  const t = Role.user(toUid);
  return [
    Permission.read(f), Permission.update(f), Permission.delete(f),
    Permission.read(t), Permission.update(t),
  ];
}

// Statistik je Collection (Ist-Zustand VOR der Migration).
const stats = {};
function inspect(col, perms) {
  const s = (stats[col] ??= { total: 0, broad: 0, noRead: 0 });
  s.total++;
  const list = perms ?? [];
  if (list.some((p) => /\("(users|any|guests)(\/[^"]*)?"\)/.test(p))) s.broad++;
  if (!list.some((p) => p.startsWith('read('))) s.noRead++;
}

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

async function ensureTeam(teamId, name) {
  try {
    await teams.get(teamId);
    return false;
  } catch (e) {
    if (e.code !== 404) throw e;
    if (!DRY) await teams.create(teamId, name);
    return true;
  }
}

/** Fügt fehlende Mitglieder hinzu (add-only; entfernt in der Migration nichts). */
async function addTeamMembers(teamId, uids) {
  // Auch im Dry-Run lesen (nur lesend) — sonst zählt der Dry-Run jeden
  // Teilnehmer als „fehlt" und man sieht nicht, ob Teams wirklich lückenhaft
  // sind (genau das entscheidet, ob nach dem Entzug der Collection-Rechte
  // jemand den Zugriff verliert).
  let existing = new Set();
  try {
    const cur = await teams.listMemberships(teamId, [Query.limit(500)]);
    for (const m of cur.memberships ?? []) if (m.userId) existing.add(m.userId);
  } catch {
    /* Team existiert (im Dry-Run) evtl. noch nicht */
  }
  let added = 0;
  for (const uid of new Set(uids.filter(Boolean))) {
    if (existing.has(uid)) continue;
    added++;
    if (DRY) console.log(`  + ${teamId}: ${uid} fehlt`);
    if (!DRY) {
      try {
        await teams.createMembership(teamId, ['member'], undefined, uid);
      } catch (e) {
        if (e.code !== 409) console.error(`  ✗ ${teamId} +${uid}: ${e.message}`);
      }
    }
  }
  return added;
}

async function eachDocument(col, queries, fn) {
  let cursor = null;
  do {
    const q = [...queries, Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, col, q);
    for (const doc of result.documents) await fn(doc);
    cursor = result.documents.length === 100 ? result.documents.at(-1).$id : null;
  } while (cursor);
}

async function main() {
  console.log('=== harden-permissions ===');
  console.log(`Projekt: ${projectId}`);
  console.log(`Modus:   ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'}\n`);

  // ── Phase 1: Supervisor-Cache je Org ─────────────────────────────────────
  // `sup_<orgId>` ist kein ACL-Team mehr, sondern der Änderungs-Detektor für
  // sync-supervisor-team. Wir seeden ihn mit dem aktuellen Supervisor-Satz und
  // merken ihn für Phase 2 (dort kommen die Supervisoren in jedes Conv-Team).
  console.log('Phase 1: Org-Supervisor-Cache');
  const supervisorsByOrg = new Map();
  let orgCount = 0;
  let supTeamsCreated = 0;
  let supMembersAdded = 0;
  await eachDocument(COL_ORGS, [], async (org) => {
    orgCount++;
    const mods = await db.listDocuments(DB_ID, COL_MEMBERS, [
      Query.equal('orgId', org.$id),
      Query.equal('role', ['admin', 'moderator']),
      Query.limit(200),
    ]);
    const uids = mods.documents.map((d) => d.uid).filter(Boolean);
    supervisorsByOrg.set(org.$id, uids);
    if (await ensureTeam(supTeamId(org.$id), `Supervisors ${org.$id}`)) supTeamsCreated++;
    supMembersAdded += await addTeamMembers(supTeamId(org.$id), uids);
  });
  console.log(
    `  Orgs: ${orgCount}  Teams neu: ${supTeamsCreated}  Mitglieder +: ${supMembersAdded}\n`
  );

  // ── Phase 2: Conversation-Teams + Conv-ACL ───────────────────────────────
  console.log('Phase 2: Conversations');
  let convCount = 0;
  let convTeamsCreated = 0;
  let convMembersAdded = 0;
  let convAclUpdated = 0;
  await eachDocument(COL_CONVERSATIONS, [], async (conv) => {
    convCount++;
    inspect(COL_CONVERSATIONS, conv.$permissions);
    const orgId = conv.orgId;
    if (!orgId) {
      console.error(`  ✗ Conv ${conv.$id} ohne orgId — übersprungen`);
      return;
    }
    const members = [
      ...(conv.participantUids ?? []),
      ...(conv.guardianUids ?? []),
      ...(supervisorsByOrg.get(orgId) ?? []),
    ];
    if (await ensureTeam(conv.$id, `Conversation ${conv.$id}`)) convTeamsCreated++;
    convMembersAdded += await addTeamMembers(conv.$id, members);

    const desired = convPerms(conv.$id);
    if (!samePerms(conv.$permissions, desired)) {
      convAclUpdated++;
      if (!DRY) {
        try {
          await db.updateDocument(DB_ID, COL_CONVERSATIONS, conv.$id, {}, desired);
        } catch (e) {
          console.error(`  ✗ Conv-ACL ${conv.$id}: ${e.message}`);
        }
      }
    }
  });
  console.log(
    `  Convs: ${convCount}  Teams neu: ${convTeamsCreated}  Mitglieder +: ${convMembersAdded}  ACL geändert: ${convAclUpdated}\n`
  );

  // ── Phase 3: Nachrichten-ACL ─────────────────────────────────────────────
  console.log('Phase 3: Nachrichten (chat_messages)');
  let msgCount = 0;
  let msgUpdated = 0;
  await eachDocument(COL_MESSAGES, [], async (msg) => {
    msgCount++;
    inspect(COL_MESSAGES, msg.$permissions);
    const convId = msg.convId;
    if (!convId) {
      console.error(`  ✗ Msg ${msg.$id} ohne convId — übersprungen`);
      return;
    }
    const desired = msgPerms(convId, msg.senderUid);
    if (samePerms(msg.$permissions, desired)) return;
    msgUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_MESSAGES, msg.$id, {}, desired);
        if (msgUpdated % 100 === 0) process.stdout.write('.');
      } catch (e) {
        console.error(`\n  ✗ Msg-ACL ${msg.$id}: ${e.message}`);
      }
    }
  });
  console.log(`\n  Nachrichten: ${msgCount}  ACL geändert: ${msgUpdated}\n`);

  // ── Phase 4: Geplante Nachrichten (Autor-only) ───────────────────────────
  console.log('Phase 4: Geplante Nachrichten (scheduled_messages)');
  let schedCount = 0;
  let schedUpdated = 0;
  await eachDocument(COL_SCHEDULED, [], async (sm) => {
    schedCount++;
    inspect(COL_SCHEDULED, sm.$permissions);
    const desired = scheduledPerms(sm.senderUid);
    if (desired.length === 0 || samePerms(sm.$permissions, desired)) return;
    schedUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_SCHEDULED, sm.$id, {}, desired);
      } catch (e) {
        console.error(`  ✗ Sched-ACL ${sm.$id}: ${e.message}`);
      }
    }
  });
  console.log(`  Geplant: ${schedCount}  ACL geändert: ${schedUpdated}\n`);

  // ── Phase 5: Polls (Team-Modell wie Nachrichten) ─────────────────────────
  console.log('Phase 5: Polls');
  let pollCount = 0;
  let pollUpdated = 0;
  await eachDocument(COL_POLLS, [], async (poll) => {
    pollCount++;
    inspect(COL_POLLS, poll.$permissions);
    const convId = poll.convId;
    if (!convId) {
      console.error(`  ✗ Poll ${poll.$id} ohne convId — übersprungen`);
      return;
    }
    const desired = pollPerms(convId, poll.createdBy);
    if (samePerms(poll.$permissions, desired)) return;
    pollUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_POLLS, poll.$id, {}, desired);
      } catch (e) {
        console.error(`  ✗ Poll-ACL ${poll.$id}: ${e.message}`);
      }
    }
  });
  console.log(`  Polls: ${pollCount}  ACL geändert: ${pollUpdated}\n`);

  // ── Phase 6: Reports (nur Aufsicht + Melder) ─────────────────────────────
  console.log('Phase 6: Reports');
  let reportCount = 0;
  let reportUpdated = 0;
  await eachDocument(COL_REPORTS, [], async (report) => {
    reportCount++;
    inspect(COL_REPORTS, report.$permissions);
    const orgId = report.orgId;
    if (!orgId) {
      console.error(`  ✗ Report ${report.$id} ohne orgId — übersprungen`);
      return;
    }
    const supervisors = [
      ...new Set([
        ...(report.orgAdminUid ? [report.orgAdminUid] : []),
        ...(supervisorsByOrg.get(orgId) ?? []),
      ]),
    ].filter(Boolean);
    const desired = reportPerms(supervisors, report.reportedByUid);
    if (samePerms(report.$permissions, desired)) return;
    reportUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_REPORTS, report.$id, {}, desired);
      } catch (e) {
        console.error(`  ✗ Report-ACL ${report.$id}: ${e.message}`);
      }
    }
  });
  console.log(`  Reports: ${reportCount}  ACL geändert: ${reportUpdated}\n`);

  // ── Phase 7: Read-Receipts (nur Eigentümer) ──────────────────────────────
  console.log('Phase 7: Read-Receipts');
  let rrCount = 0;
  let rrUpdated = 0;
  await eachDocument(COL_RECEIPTS, [], async (rr) => {
    rrCount++;
    inspect(COL_RECEIPTS, rr.$permissions);
    const desired = receiptPerms(rr.uid);
    if (desired.length === 0) {
      console.error(`  ✗ Receipt ${rr.$id} ohne uid — übersprungen`);
      return;
    }
    if (samePerms(rr.$permissions, desired)) return;
    rrUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_RECEIPTS, rr.$id, {}, desired);
      } catch (e) {
        console.error(`  ✗ Receipt-ACL ${rr.$id}: ${e.message}`);
      }
    }
  });
  console.log(`  Receipts: ${rrCount}  ACL geändert: ${rrUpdated}\n`);

  // ── Phase 8: Claim-Requests (Antragsteller + Kind) ───────────────────────
  console.log('Phase 8: Claim-Requests');
  let claimCount = 0;
  let claimUpdated = 0;
  await eachDocument(COL_CLAIMS, [], async (claim) => {
    claimCount++;
    inspect(COL_CLAIMS, claim.$permissions);
    const desired = claimPerms(claim.fromUid, claim.toUid);
    if (desired.length === 0) {
      console.error(`  ✗ Claim ${claim.$id} ohne fromUid/toUid — übersprungen`);
      return;
    }
    if (samePerms(claim.$permissions, desired)) return;
    claimUpdated++;
    if (!DRY) {
      try {
        await db.updateDocument(DB_ID, COL_CLAIMS, claim.$id, {}, desired);
      } catch (e) {
        console.error(`  ✗ Claim-ACL ${claim.$id}: ${e.message}`);
      }
    }
  });
  console.log(`  Claims: ${claimCount}  ACL geändert: ${claimUpdated}\n`);

  // ── Zusammenfassung: Ist-Zustand VOR dieser Migration ────────────────────
  console.log('Ist-Zustand der Dokument-ACLs (vor Migration):');
  for (const [col, s] of Object.entries(stats)) {
    console.log(
      `  ${col.padEnd(20)} gesamt ${String(s.total).padStart(6)}  breit ${String(s.broad).padStart(6)}  ohne read ${String(s.noRead).padStart(6)}`
    );
  }
  console.log('  („breit" = users/any/guests in der Doc-ACL; nach der Migration 0.)\n');

  console.log('=== Fertig ===');
  if (DRY) {
    console.log('DRY RUN — keine Änderungen. Zum Ausführen:');
    console.log(`  node harden-permissions.js --confirm=${projectId}`);
  }
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
