/**
 * Phase 2a (Notfall, Release-Review 182): Doc-ACLs von Einladungen und
 * Eltern-Zustimmungen auf das Server-Modell bringen, damit danach die
 * Collection-Rechte (fix-permissions.js: invitations/org_invite_consents → [])
 * entzogen werden können, ohne dass Berechtigte etwas verlieren.
 *
 * Soll:
 *  - invitations/{id}:  read/update/delete user(invitedByUid)
 *                       + read user(g) für jeden Guardian (Liste „ausstehende
 *                         Kind-Einladungen“ beim Guardian)
 *  - org_invite_consents/{id}: read/delete user(invitedByUid)  (KEIN update —
 *                         sonst genehmigt der Einladende selbst)
 *                       + read/update user(p) für jedes Elternteil in parentUids
 *
 * Standardmäßig nur offene (pending) Docs, mit --all alle.
 *
 * Docs ohne gültigen Einladenden (fehlendes invitedByUid oder ACL-Ersteller ≠
 * invitedByUid → vermutlich gefälscht) werden nur gemeldet, nicht geändert;
 * offene davon mit --invalidate auf status `invalid` setzen.
 *
 * Idempotent & wiederholbar. Standardmäßig Dry-Run.
 *
 * Nutzung (aus appwrite/, .env wie setup.js):
 *   node harden-invites.js                              Dry-Run: Ist vs. Soll
 *   node harden-invites.js --confirm=<projectId>        umstellen; vorher Backup der
 *                                                       alten ACLs nach backups/invites-acl-<ts>.json
 *   node harden-invites.js --invalidate --confirm=<projectId>
 *                                                       zusätzlich verdächtige offene Docs → invalid
 *   node harden-invites.js --rollback=<backup.json> --confirm=<projectId>
 *                                                       alte ACLs aus dem Backup zurück (nur Notfall)
 *
 * Reihenfolge: Functions deployen → dieses Skript → fix-permissions.js
 * (siehe docs/security/release-review-182.md).
 */

import { config } from 'dotenv';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client, Databases, Permission, Role, Query } from 'node-appwrite';

config();

const DB_ID = 'guardian';
const COL_INVITATIONS = 'invitations';
const COL_CONSENTS = 'org_invite_consents';

const projectId = process.env.APPWRITE_PROJECT_ID;
const args = process.argv.slice(2);
const argValue = (name) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const confirmArg = argValue('confirm');
const CONFIRMED = confirmArg !== undefined && confirmArg === projectId;
const DRY = !CONFIRMED;
const ROLLBACK_FILE = argValue('rollback');
const INVALIDATE = args.includes('--invalidate');
const ALL = args.includes('--all');

if (confirmArg !== undefined && !CONFIRMED) {
  console.error(`✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`);
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);
const db = new Databases(client);

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

function aclUsers(perms) {
  const uids = new Set();
  for (const p of perms ?? []) {
    const m = /^\w+\("user:([^"/]+)"\)$/.exec(p);
    if (m) uids.add(m[1]);
  }
  return [...uids];
}

const uniq = (arr) => [...new Set((arr ?? []).filter((u) => typeof u === 'string' && u))];

function invitationPerms(doc) {
  const inviter = doc.invitedByUid;
  return [
    Permission.read(Role.user(inviter)),
    Permission.update(Role.user(inviter)),
    Permission.delete(Role.user(inviter)),
    ...uniq(doc.guardianUids).filter((g) => g !== inviter).map((g) => Permission.read(Role.user(g))),
  ];
}

function consentPerms(doc) {
  const inviter = doc.invitedByUid;
  const parents = uniq(doc.parentUids).filter((p) => p !== inviter);
  return [
    Permission.read(Role.user(inviter)),
    Permission.delete(Role.user(inviter)),
    ...parents.flatMap((p) => [Permission.read(Role.user(p)), Permission.update(Role.user(p))]),
  ];
}

/**
 * Gilt der Einladende als echt? Server-Docs (inviteByEmail) tragen den
 * Einladenden in der ACL; Alt-Docs aus Client-Zeiten tragen nur den Ersteller.
 * Verdächtig: kein invitedByUid oder ein anderer `user:`-Eintrag als
 * Einladender + (bei Consents) Eltern bzw. (bei Einladungen) Guardians.
 */
function suspicious(doc, allowedExtra) {
  if (!doc.invitedByUid) return 'kein invitedByUid';
  const owners = aclUsers(doc.$permissions);
  if (!owners.includes(doc.invitedByUid)) return `ACL-Ersteller ${owners.join(',') || '-'} ≠ invitedByUid`;
  const foreign = owners.filter((u) => u !== doc.invitedByUid && !allowedExtra.includes(u));
  if (foreign.length) return `fremde ACL-Einträge ${foreign.join(',')}`;
  return null;
}

async function eachDocument(col, fn) {
  let cursor = null;
  for (;;) {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const page = await db.listDocuments(DB_ID, col, q);
    for (const d of page.documents) await fn(d);
    if (page.documents.length < 100) break;
    cursor = page.documents[page.documents.length - 1].$id;
  }
}

async function rollback(file) {
  const backup = JSON.parse(readFileSync(file, 'utf8'));
  if (backup.projectId !== projectId) {
    console.error(`✗ Backup gehört zu Projekt ${backup.projectId}, nicht ${projectId}. Abbruch.`);
    process.exit(1);
  }
  console.log(`Rollback aus ${file}: ${backup.entries.length} Docs (${DRY ? 'DRY RUN' : 'LIVE'})`);
  for (const e of backup.entries) {
    console.log(`  ${e.col}/${e.id}`);
    if (!DRY) await db.updateDocument(DB_ID, e.col, e.id, {}, e.permissions);
  }
}

async function main() {
  console.log(`=== harden-invites — Projekt ${projectId} — ${DRY ? 'DRY RUN' : 'LIVE'} ===\n`);
  if (ROLLBACK_FILE) return rollback(ROLLBACK_FILE);

  const plan = [];
  const flagged = [];
  let total = 0;

  for (const [col, permsFor, extraOf] of [
    [COL_INVITATIONS, invitationPerms, (d) => uniq(d.guardianUids)],
    [COL_CONSENTS, consentPerms, (d) => uniq(d.parentUids)],
  ]) {
    let n = 0;
    await eachDocument(col, async (doc) => {
      n++;
      const why = suspicious(doc, extraOf(doc));
      if (why) {
        flagged.push({ col, doc, why });
        return;
      }
      // Nur offene Docs: jede ACL-Änderung löst ein update-Event aus — bei
      // erledigten Zustimmungen würde on-parent-consent sonst erneut Pushes
      // („genehmigt“/„abgelehnt“) an den Einladenden schicken. Erledigte Docs
      // braucht niemand mehr zu lesen (mit --all trotzdem).
      if (doc.status !== 'pending' && !ALL) return;
      const desired = permsFor(doc);
      if (!samePerms(doc.$permissions ?? [], desired)) {
        plan.push({ col, id: doc.$id, from: doc.$permissions ?? [], to: desired, status: doc.status });
      }
    });
    total += n;
    console.log(`${col}: ${n} Docs geprüft`);
  }

  console.log(`\n${plan.length} ACL(s) abweichend:`);
  for (const p of plan) {
    console.log(`~ ${p.col}/${p.id} [${p.status}]`);
    console.log(`    ist:  ${JSON.stringify(p.from)}`);
    console.log(`    soll: ${JSON.stringify(p.to)}`);
  }
  console.log(`\n${flagged.length} verdächtige(s) Doc(s) (nicht geändert):`);
  for (const f of flagged) {
    console.log(`! ${f.col}/${f.doc.$id} [${f.doc.status}] org=${f.doc.orgId} — ${f.why}`);
  }

  if (DRY) {
    console.log(`\nDry-Run — nichts geändert (${total} Docs). Ausführen: node harden-invites.js${INVALIDATE ? ' --invalidate' : ''} --confirm=${projectId}`);
    return;
  }

  const dir = join(dirname(fileURLToPath(import.meta.url)), 'backups');
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `invites-acl-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  writeFileSync(file, JSON.stringify({
    projectId,
    createdAt: new Date().toISOString(),
    entries: plan.map((p) => ({ col: p.col, id: p.id, permissions: p.from })),
  }, null, 2));
  console.log(`\nBackup: ${file}`);

  let ok = 0;
  for (const p of plan) {
    try {
      await db.updateDocument(DB_ID, p.col, p.id, {}, p.to);
      ok++;
    } catch (e) {
      console.error(`✗ ${p.col}/${p.id}: ${e.message}`);
    }
  }
  console.log(`✓ ${ok}/${plan.length} ACLs umgestellt`);

  if (INVALIDATE) {
    let inv = 0;
    for (const f of flagged.filter((x) => x.doc.status === 'pending')) {
      try {
        await db.updateDocument(DB_ID, f.col, f.doc.$id, { status: 'invalid' });
        inv++;
      } catch (e) {
        console.error(`✗ invalidate ${f.col}/${f.doc.$id}: ${e.message}`);
      }
    }
    console.log(`✓ ${inv} verdächtige offene Docs auf invalid gesetzt`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
