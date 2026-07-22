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
  let existing = new Set();
  if (!DRY) {
    try {
      const cur = await teams.listMemberships(teamId);
      for (const m of cur.memberships ?? []) if (m.userId) existing.add(m.userId);
    } catch {
      /* Team existiert im Dry-Run evtl. noch nicht */
    }
  }
  let added = 0;
  for (const uid of new Set(uids.filter(Boolean))) {
    if (existing.has(uid)) continue;
    added++;
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
