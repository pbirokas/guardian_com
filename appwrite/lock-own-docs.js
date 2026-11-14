/**
 * Migration: Selbst-Eskalation auf Dokument-Ebene schließen.
 *
 * Appwrite kennt keine Feld-Rechte. Bisher trugen
 *   - members/{orgId}_{uid}   update/delete user(uid)   → `role: "admin"` selbst setzen
 *   - users/{uid}             update/delete user(uid)   → `isChild`/`verifiedParentUids` ändern
 *   - conversations/{convId}  update/delete team(convId)→ status/participantUids/guardianUids ändern, Chat löschen
 *   - claim_requests          update user(fromUid)      → eigene Eltern-Anfrage selbst bestätigen
 * Soll (deckungsgleich mit self-service / conversation-action / sync-* / on-claim-request):
 *   - members        read("users")            (Phase 2 der Collection-Härtung engt read ein)
 *   - users          read(user(uid))
 *   - conversations  read(team(convId))
 *   - claim_requests read+delete user(from), read+update user(to)
 *
 * Zusätzlich ein Audit (nur lesend) auf Spuren früherer Ausnutzung.
 *
 * Idempotent & wiederholbar. Standardmäßig Dry-Run.
 *
 * Nutzung:
 *   node lock-own-docs.js                                   (Dry-Run, alle Teile)
 *   node lock-own-docs.js --only=members,claims             (Dry-Run, Auswahl)
 *   node lock-own-docs.js --only=members --confirm=<projectId>
 *   Teile: members, users, conversations, claims
 *
 * Reihenfolge: siehe docs/security/self-escalation.md §4 (members/claims nach
 * dem Function-Deploy; users/conversations erst nach minVersionCode).
 */

import { config } from 'dotenv';
import { Client, Databases, Teams, Permission, Role, Query } from 'node-appwrite';

config();

const DB_ID = 'guardian';
const COL_ORGS = 'organizations';
const COL_MEMBERS = 'members';
const COL_USERS = 'users';
const COL_CONVERSATIONS = 'conversations';
const COL_CLAIMS = 'claim_requests';

const PARTS = ['members', 'users', 'conversations', 'claims'];

const projectId = process.env.APPWRITE_PROJECT_ID;
const confirmArg = process.argv.find((a) => a.startsWith('--confirm='));
const CONFIRMED = confirmArg && confirmArg.split('=')[1] === projectId;
const DRY = !CONFIRMED;
const onlyArg = process.argv.find((a) => a.startsWith('--only='));
const ONLY = onlyArg ? onlyArg.split('=')[1].split(',').map((s) => s.trim()).filter(Boolean) : PARTS;

if (confirmArg && !CONFIRMED) {
  console.error(`✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`);
  process.exit(1);
}
const unknown = ONLY.filter((p) => !PARTS.includes(p));
if (unknown.length > 0) {
  console.error(`✗ Unbekannte Teile in --only: ${unknown.join(', ')} (erlaubt: ${PARTS.join(', ')})`);
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);
const db = new Databases(client);
const teams = new Teams(client);

// ── Soll-ACLs ─────────────────────────────────────────────────────────────────

const memberPerms = () => [Permission.read(Role.users())];
const userPerms = (uid) => [Permission.read(Role.user(uid))];
const convPerms = (convId) => [Permission.read(Role.team(convId))];
function claimPerms(fromUid, toUid) {
  if (!fromUid || !toUid) return [];
  return [
    Permission.read(Role.user(fromUid)), Permission.delete(Role.user(fromUid)),
    Permission.read(Role.user(toUid)), Permission.update(Role.user(toUid)),
  ];
}

// ── Helfer ────────────────────────────────────────────────────────────────────

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

const writable = (perms) => (perms ?? []).filter((p) => /^(update|delete)\(/.test(p));

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

async function setPerms(col, doc, desired, label) {
  if (samePerms(doc.$permissions, desired)) return false;
  if (DRY) {
    const w = writable(doc.$permissions);
    if (w.length > 0) console.log(`  ~ ${label}: entziehe ${w.join(' ')}`);
  } else {
    try {
      await db.updateDocument(DB_ID, col, doc.$id, {}, desired);
    } catch (e) {
      console.error(`  ✗ ${label}: ${e.message}`);
    }
  }
  return true;
}

const findings = [];
const finding = (msg) => findings.push(msg);

// ── Teile ─────────────────────────────────────────────────────────────────────

async function lockMembers(orgAdmins, childUids) {
  console.log('Teil members');
  let total = 0;
  let changed = 0;
  await eachDocument(COL_MEMBERS, [], async (m) => {
    total++;
    // Audit: Spuren von Selbst-Eskalation
    if (m.role === 'admin' && orgAdmins.get(m.orgId) !== m.uid) {
      finding(`members/${m.$id}: role=admin, aber organizations/${m.orgId}.adminUid=${orgAdmins.get(m.orgId) ?? '–'}`);
    }
    if (m.role !== 'child' && childUids.has(m.uid)) {
      finding(`members/${m.$id}: Kind-Konto mit role=${m.role}`);
    }
    if (m.role === 'child' && (m.guardianUids ?? []).length === 0) {
      finding(`members/${m.$id}: Kind ohne guardianUids`);
    }
    if (m.$id !== `${m.orgId}_${m.uid}`) {
      finding(`members/${m.$id}: Doc-ID passt nicht zu orgId/uid (${m.orgId}/${m.uid})`);
    }
    if (await setPerms(COL_MEMBERS, m, memberPerms(), `members/${m.$id}`)) changed++;
  });
  console.log(`  Member-Docs: ${total}  ACL geändert: ${changed}\n`);
}

async function lockUsers() {
  console.log('Teil users');
  let total = 0;
  let changed = 0;
  await eachDocument(COL_USERS, [], async (u) => {
    total++;
    if (!u.isChild && (u.verifiedParentUids ?? []).length > 0) {
      finding(`users/${u.$id}: isChild=false, aber verifiedParentUids=[${u.verifiedParentUids.join(',')}]`);
    }
    if (await setPerms(COL_USERS, u, userPerms(u.$id), `users/${u.$id}`)) changed++;
  });
  console.log(`  User-Docs: ${total}  ACL geändert: ${changed}\n`);
}

async function lockConversations() {
  console.log('Teil conversations');
  let total = 0;
  let changed = 0;
  let skipped = 0;
  await eachDocument(COL_CONVERSATIONS, [], async (c) => {
    total++;
    // Voraussetzung: Conv-Team existiert (harden-permissions.js / Sync-Function).
    // Ohne Team würde read(team) niemanden einschließen → Chat unsichtbar.
    try {
      await teams.get(c.$id);
    } catch (e) {
      if (e.code === 404) {
        skipped++;
        console.error(`  ✗ conversations/${c.$id}: Team fehlt — übersprungen (erst harden-permissions.js)`);
        return;
      }
      throw e;
    }
    if (await setPerms(COL_CONVERSATIONS, c, convPerms(c.$id), `conversations/${c.$id}`)) changed++;
  });
  console.log(`  Convs: ${total}  ACL geändert: ${changed}  übersprungen: ${skipped}\n`);
}

async function lockClaims() {
  console.log('Teil claims');
  let total = 0;
  let changed = 0;
  await eachDocument(COL_CLAIMS, [], async (cl) => {
    total++;
    const desired = claimPerms(cl.fromUid, cl.toUid);
    if (desired.length === 0) {
      console.error(`  ✗ claim_requests/${cl.$id} ohne fromUid/toUid — übersprungen`);
      return;
    }
    if (await setPerms(COL_CLAIMS, cl, desired, `claim_requests/${cl.$id}`)) changed++;
  });
  console.log(`  Claims: ${total}  ACL geändert: ${changed}\n`);
}

async function main() {
  console.log('=== lock-own-docs ===');
  console.log(`Projekt: ${projectId}`);
  console.log(`Modus:   ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'}`);
  console.log(`Teile:   ${ONLY.join(', ')}\n`);

  // Audit-Grundlagen (nur lesend)
  const orgAdmins = new Map();
  await eachDocument(COL_ORGS, [], async (o) => orgAdmins.set(o.$id, o.adminUid));
  const childUids = new Set();
  await eachDocument(COL_USERS, [Query.equal('isChild', true)], async (u) => childUids.add(u.$id));

  if (ONLY.includes('members')) await lockMembers(orgAdmins, childUids);
  if (ONLY.includes('users')) await lockUsers();
  if (ONLY.includes('conversations')) await lockConversations();
  if (ONLY.includes('claims')) await lockClaims();

  console.log(`Audit (${findings.length} Auffälligkeiten — manuell prüfen, nichts automatisch geändert):`);
  for (const f of findings) console.log(`  ! ${f}`);
  if (DRY) console.log(`\nDry-Run. Ausführen mit --confirm=${projectId}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
