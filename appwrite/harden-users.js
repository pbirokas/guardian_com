/**
 * Phase 3 der Collection-ACL-Härtung: users-Docs nur noch für den Eigentümer.
 *
 * Soll je Doc `users/{uid}`: genau `read("user:{uid}")` — kein read für andere
 * (Role.users/any/fremde user/team), kein update/delete (Selbst-Eskalation,
 * siehe self-escalation.md; schreiben nur Functions mit API-Key).
 * Die Collection-Ebene stellt fix-permissions.js um (`--phase3 --only=users`).
 *
 * Zusätzlich ein Audit (nur lesend) für die neuen serverseitigen Pfade:
 *  - doppelte/fehlende E-Mails (inviteByEmail/sendClaim nehmen den ersten Treffer)
 *  - einseitige Eltern-Kind-Verknüpfungen (listRelatives zeigt nur gegenseitige)
 *  - Konten ohne users-Doc ist kein Befund (ensureUserDoc legt beim Login an)
 *
 * Idempotent & wiederholbar. Standardmäßig Dry-Run.
 *
 * Nutzung (aus appwrite/, .env wie setup.js):
 *   node harden-users.js                                  Dry-Run: Ist vs. Soll + Audit
 *   node harden-users.js --confirm=<projectId>            umstellen; vorher Backup der
 *                                                         alten ACLs nach backups/users-acl-<ts>.json
 *   node harden-users.js --rollback=<backup.json> [--confirm=<projectId>]
 *                                                         alte ACLs aus dem Backup zurück
 *                                                         (öffnet die Lücke wieder — nur Notfall)
 *
 * Reihenfolge: docs/security/collection-acl-hardening.md §8.
 */

import { config } from 'dotenv';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client, Databases, Permission, Role, Query } from 'node-appwrite';

config();

const DB_ID = 'guardian';
const COL_USERS = 'users';

const projectId = process.env.APPWRITE_PROJECT_ID;
const args = process.argv.slice(2);
const argValue = (name) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const confirmArg = argValue('confirm');
const CONFIRMED = confirmArg !== undefined && confirmArg === projectId;
const DRY = !CONFIRMED;
const ROLLBACK_FILE = argValue('rollback');

if (confirmArg !== undefined && !CONFIRMED) {
  console.error(`✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`);
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);
const db = new Databases(client);

const userPerms = (uid) => [Permission.read(Role.user(uid))];

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

/** Was an der Ist-ACL zu viel ist, gruppiert für die Ausgabe. */
function classify(uid, perms) {
  const own = `read("user:${uid}")`;
  const extra = (perms ?? []).filter((p) => p !== own);
  return {
    missingOwnRead: !(perms ?? []).includes(own),
    foreignRead: extra.filter((p) => p.startsWith('read(')),
    write: extra.filter((p) => /^(update|delete|write)\(/.test(p)),
  };
}

async function eachDocument(col, fn) {
  let cursor = null;
  do {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const result = await db.listDocuments(DB_ID, col, q);
    for (const doc of result.documents) await fn(doc);
    cursor = result.documents.length === 100 ? result.documents.at(-1).$id : null;
  } while (cursor);
}

async function harden() {
  console.log(`Modus: ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'}\n`);

  const users = [];
  await eachDocument(COL_USERS, async (u) => users.push(u));

  // ── ACL ──
  const toChange = [];
  const stats = { foreignRead: 0, write: 0, missingOwnRead: 0 };
  for (const u of users) {
    const desired = userPerms(u.$id);
    if (samePerms(u.$permissions, desired)) continue;
    const c = classify(u.$id, u.$permissions);
    if (c.foreignRead.length) stats.foreignRead++;
    if (c.write.length) stats.write++;
    if (c.missingOwnRead) stats.missingOwnRead++;
    toChange.push({ id: u.$id, before: u.$permissions ?? [], desired, c });
  }
  console.log(`users-Docs: ${users.length}  abweichend: ${toChange.length}`);
  console.log(`  mit fremdem read: ${stats.foreignRead}  mit update/delete: ${stats.write}  ohne eigenes read: ${stats.missingOwnRead}`);
  for (const t of toChange) {
    const parts = [];
    if (t.c.foreignRead.length) parts.push(`entziehe ${t.c.foreignRead.join(' ')}`);
    if (t.c.write.length) parts.push(`entziehe ${t.c.write.join(' ')}`);
    if (t.c.missingOwnRead) parts.push('ergänze eigenes read');
    console.log(`  ~ users/${t.id}: ${parts.join('; ')}`);
  }

  if (!DRY && toChange.length) {
    const dir = join(dirname(fileURLToPath(import.meta.url)), 'backups');
    mkdirSync(dir, { recursive: true });
    const file = join(dir, `users-acl-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
    writeFileSync(file, JSON.stringify({
      projectId,
      createdAt: new Date().toISOString(),
      docs: toChange.map((t) => ({ id: t.id, permissions: t.before })),
    }, null, 2));
    console.log(`\nBackup: ${file}`);
    let ok = 0;
    for (const t of toChange) {
      try {
        await db.updateDocument(DB_ID, COL_USERS, t.id, {}, t.desired);
        ok++;
      } catch (e) {
        console.error(`  ✗ users/${t.id}: ${e.message}`);
      }
    }
    console.log(`✓ ${ok}/${toChange.length} ACLs gesetzt`);
  }

  // ── Audit (nur lesend) ──
  const findings = [];
  const byEmail = new Map();
  for (const u of users) {
    const email = String(u.email ?? '').toLowerCase().trim();
    if (!email) { findings.push(`users/${u.$id}: keine E-Mail (per Einladung/Anfrage nicht auffindbar)`); continue; }
    if (email !== u.email) findings.push(`users/${u.$id}: E-Mail nicht normalisiert (Groß-/Leerzeichen) — Lookup sucht klein geschrieben`);
    byEmail.set(email, [...(byEmail.get(email) ?? []), u.$id]);
  }
  for (const [email, ids] of byEmail) {
    if (ids.length > 1) findings.push(`E-Mail doppelt (${ids.length}×, Lookup nimmt den ersten): ${ids.join(', ')} [${email.replace(/^(.).*@/, '$1…@')}]`);
  }
  const byId = new Map(users.map((u) => [u.$id, u]));
  for (const u of users) {
    for (const c of u.verifiedChildUids ?? []) {
      if (!(byId.get(c)?.verifiedParentUids ?? []).includes(u.$id)) {
        findings.push(`users/${u.$id}: Kind ${c} ohne Gegenstück verifiedParentUids (listRelatives blendet aus)`);
      }
    }
    for (const p of u.verifiedParentUids ?? []) {
      if (!(byId.get(p)?.verifiedChildUids ?? []).includes(u.$id)) {
        findings.push(`users/${u.$id}: Elternteil ${p} ohne Gegenstück verifiedChildUids (listRelatives blendet aus)`);
      }
    }
  }
  console.log(`\nAudit (${findings.length} Auffälligkeiten — manuell prüfen, nichts automatisch geändert):`);
  for (const f of findings) console.log(`  ! ${f}`);

  if (DRY && toChange.length) console.log(`\nDry-Run. Ausführen mit: node harden-users.js --confirm=${projectId}`);
}

async function rollback() {
  const backup = JSON.parse(readFileSync(ROLLBACK_FILE, 'utf8'));
  if (backup.projectId !== projectId) {
    console.error(`✗ Backup gehört zu Projekt ${backup.projectId}, nicht ${projectId}. Abbruch.`);
    process.exit(1);
  }
  console.log(`Modus: ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'} — ROLLBACK aus ${ROLLBACK_FILE} (${backup.docs.length} Docs)\n`);
  let ok = 0;
  for (const d of backup.docs) {
    console.log(`  ~ users/${d.id}: setze ${d.permissions.join(' ') || '[]'}`);
    if (DRY) continue;
    try {
      await db.updateDocument(DB_ID, COL_USERS, d.id, {}, d.permissions);
      ok++;
    } catch (e) {
      console.error(`  ✗ users/${d.id}: ${e.message}`);
    }
  }
  if (DRY) console.log(`\nDry-Run. Ausführen mit: node harden-users.js --rollback=${ROLLBACK_FILE} --confirm=${projectId}`);
  else console.log(`✓ ${ok}/${backup.docs.length} ACLs zurückgesetzt`);
}

console.log(`=== harden-users — Projekt ${projectId} ===`);
(ROLLBACK_FILE ? rollback() : harden()).catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
