/**
 * Collection-Level-Berechtigungen der Datenbank `guardian` (Soll-Zustand).
 *
 * WARUM: Appwrite wertet Collection- und Dokument-Rechte ADDITIV aus — hat die
 * Collection `read("users")`, darf jeder eingeloggte Nutzer JEDES Dokument
 * lesen, egal was in der Dokument-ACL steht. Die Team-Härtung (ein Chat = ein
 * Team, ACL `team(convId)`) greift also erst, wenn die Collection-Ebene keine
 * breiten Rechte mehr vergibt. Soll: Collection-Ebene nur `create("users")`
 * (Clients legen Dokumente an), alles andere über Dokument-ACLs oder
 * Functions (API-Key).
 *
 * Realtime braucht KEIN Collection-read: Appwrite liefert ein Event an jeden
 * Subscriber, der das Dokument lesen darf (Collection-read ODER Dokument-read
 * bei documentSecurity=true). Vor dem Live-Umstellen trotzdem mit der
 * Testanleitung in docs/security/collection-acl-hardening.md verifizieren.
 *
 * Stand: Phase 1 (Chat-Daten) ist hier als Soll eingetragen. Die Collections
 * in LEGACY werden von diesem Skript NICHT angefasst, bis Phase 2/3 umgesetzt
 * ist (siehe Doku) — dort bleiben die alten breiten Rechte vorerst bestehen.
 *
 * Nutzung (aus appwrite/, .env wie setup.js):
 *   node fix-permissions.js                                   Dry-Run: Ist vs. Soll
 *   node fix-permissions.js --only=read_receipts,polls        Dry-Run, nur diese
 *   node fix-permissions.js --only=polls --confirm=<projectId>   umstellen
 *   node fix-permissions.js --only=polls --rollback --confirm=<projectId>
 *        → Notfall: alte (breite) Rechte aus LEGACY_BEFORE wiederherstellen
 *   (--after-app-n / --phase3: seit 2026-11-26 immer aktiv, Flags ohne Wirkung)
 *   Ohne --rollback fügt das Skript nie Rechte hinzu (sonst --allow-widen).
 *   node fix-permissions.js --bootstrap --confirm=<projectId>
 *        → einmalige Alt-Schritte (Media-Bucket, pendingReportsCount-Attribut)
 *
 * Reihenfolge/Rollout: siehe docs/security/collection-acl-hardening.md.
 */

import { config } from 'dotenv';
import { Client, Databases, Storage, Permission, Role } from 'node-appwrite';

config();

const projectId = process.env.APPWRITE_PROJECT_ID;
const args = process.argv.slice(2);
const argValue = (name) => args.find((a) => a.startsWith(`--${name}=`))?.split('=')[1];
const confirmArg = argValue('confirm');
const CONFIRMED = confirmArg !== undefined && confirmArg === projectId;
const DRY = !CONFIRMED;
const ROLLBACK = args.includes('--rollback');
const BOOTSTRAP = args.includes('--bootstrap');
const ONLY = argValue('only')?.split(',').map((s) => s.trim()).filter(Boolean);

if (confirmArg !== undefined && !CONFIRMED) {
  console.error(`✗ --confirm stimmt nicht mit APPWRITE_PROJECT_ID (${projectId}) überein. Abbruch.`);
  process.exit(1);
}

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(projectId)
  .setKey(process.env.APPWRITE_API_KEY);

const db = new Databases(client);
const storage = new Storage(client);
const DB_ID = 'guardian';
const BUCKET_MEDIA = '6a02e524000954c9f1de'; // Live-Bucket-ID (manuell erstellt)

const C = Permission.create(Role.users());
const R = Permission.read(Role.users());
const U = Permission.update(Role.users());
const D = Permission.delete(Role.users());

// ── Soll-Zustand (gehärtet) ──────────────────────────────────────────────────
// Jede Collection: documentSecurity=true, Collection-Ebene höchstens create.
// Kommentar = wer liest/schreibt stattdessen (Dokument-ACL bzw. Function).
const TARGET = {
  // Doc-ACL team(convId) (sync-conversation-permissions). Neu angelegt mit
  // user(self) read/update, bis die Function das Team-Modell setzt.
  conversations: { name: 'Conversations', permissions: [C] },
  // Doc-ACL read team(convId) + read/update/delete user(Autor) (_msgPerms).
  // Fremd-Moderation → moderate-message, Reaktionen → set-reaction,
  // Chat löschen → admin-member-action/deleteConversation.
  chat_messages: { name: 'ChatMessages', permissions: [C] },
  // Doc-ACL read/update team(convId), delete user(Ersteller) (_pollPerms).
  polls: { name: 'Polls', permissions: [C] },
  // Doc-ACL read/update/delete user(Autor) — privater Entwurf.
  scheduled_messages: { name: 'ScheduledMessages', permissions: [C] },
  // Client legt mit read user(self) an; on-new-report setzt read/update für
  // Admin+Mods. pendingReportsCount zählt on-new-report (create+update) neu.
  reports: { name: 'Reports', permissions: [C] },
  // Client legt an (Default-ACL: Ersteller); on-claim-request setzt
  // from/to-Rechte. Bestätigung verarbeitet on-claim-confirmed.
  claim_requests: { name: 'ClaimRequests', permissions: [C] },
  // Nur mark-as-read (API-Key) schreibt; Doc-ACL read/update/delete user(uid).
  read_receipts: { name: 'ReadReceipts', permissions: [] },
  // ── Phase 2a (Notfall, Release-Review 182) ──────────────────────────────
  // Einladungen legt nur noch admin-member-action/inviteByEmail an (App ≥ 167
  // = minVersionCode); lesen: Einladender + Guardians per Doc-ACL
  // (harden-invites.js), zurückziehen: Einladender per Doc-ACL.
  invitations: { name: 'Invitations', permissions: [] },
  // Eltern-Zustimmungen legt nur inviteByEmail an; Eltern lesen/stimmen per
  // Doc-ACL zu, der Einladende liest/löscht. Kein Collection-Recht.
  org_invite_consents: { name: 'OrgInviteConsents', permissions: [] },
  // Org gründen läuft über self-service, löschen über admin-member-action →
  // kein create/delete. read + update bleiben bis Phase 2 (die App schreibt
  // Einstellungen/Keywords/Archiv noch direkt; Functions werten adminUid
  // nicht mehr als Berechtigung).
  organizations: { name: 'Organizations', permissions: [R, U] },
};

// ── Selbst-Eskalations-Härtung: erst NACH App-Release N + minVersionCode ────
// (`--after-app-n`, siehe docs/security/self-escalation.md). Die neue App legt
// Conversations, Member- und users-Docs nur noch über Functions an
// (conversation-action, self-service). Mit Collection-`create` könnte jeder
// `members/{fremdeOrg}_{self}` mit `role: "admin"` anlegen (bis dahin fängt
// das der Guard in sync-supervisor-team ab). `read` auf users/members bleibt
// bis Phase 2/3 der Collection-Härtung.
// Seit 2026-11-26 live (minVersionCode 167) → immer Teil des Solls. Die Flags
// werden noch akzeptiert, ändern aber nichts mehr — ein Lauf ohne Flags darf
// den Live-Stand nie wieder lockern (Release-Review 182, H7).
const AFTER_APP_N = true;
if (AFTER_APP_N) {
  Object.assign(TARGET, {
    conversations: { name: 'Conversations', permissions: [] },
    members: { name: 'Members', permissions: [R] },
    users: { name: 'Users', permissions: [R] },
  });
}

// ── Phase 3 (users): Collection-read entziehen — mit derselben App N wie die
// Selbst-Eskalations-Stufe 4 (`--phase3`, siehe collection-acl-hardening.md
// §8). Die App liest fremde users-Docs dann nicht mehr (Functions
// self-service/listRelatives+sendClaim, admin-member-action/inviteByEmail,
// Anzeigenamen aus Member-Docs). Doc-ACLs vorher mit harden-users.js prüfen.
const PHASE3 = true; // live seit 2026-11-26, siehe AFTER_APP_N
if (PHASE3) {
  TARGET.users = { name: 'Users', permissions: [] };
}

// ── Noch NICHT gehärtet (Phase 2/3) — wird von diesem Skript nicht angefasst ──
// Werte = Live-Stand 2026-11-14 (auch Rollback-Ziel für TARGET-Collections).
const LEGACY_BEFORE = {
  users:               [R, C],
  organizations:       [R, C, U, D],
  members:             [R, C],
  conversations:       [R, C, U, D],
  chat_messages:       [R, C, U, D],
  polls:               [R, C, U, D],
  announcements:       [R, C, U, D],
  scheduled_messages:  [R, C, U, D],
  invitations:         [R, C, D],
  org_invite_consents: [R, C, U, D],
  claim_requests:      [R, C, U, D],
  reports:             [R, C, U, D],
  audit_log:           [R, C, D],
  read_receipts:       [R],
};

function samePerms(a, b) {
  if ((a?.length ?? 0) !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((v, i) => v === sb[i]);
}

async function applyCollections() {
  const ids = ONLY ?? Object.keys(TARGET);
  const unknown = ids.filter((id) => !TARGET[id]);
  if (unknown.length) {
    console.error(`✗ Nicht in TARGET (Phase 2/3, noch nicht freigegeben): ${unknown.join(', ')}`);
    process.exit(1);
  }

  console.log(`Modus: ${DRY ? 'DRY RUN (keine Änderungen)' : 'LIVE'}${ROLLBACK ? ' — ROLLBACK' : ''}\n`);
  let changes = 0;
  for (const id of ids) {
    const { name } = TARGET[id];
    const desired = ROLLBACK ? LEGACY_BEFORE[id] : TARGET[id].permissions;
    let current;
    try {
      current = await db.getCollection(DB_ID, id);
    } catch (e) {
      console.error(`✗ ${id}: ${e.message}`);
      continue;
    }
    const permsOk = samePerms(current.$permissions, desired);
    const docSecOk = current.documentSecurity === true;
    if (permsOk && docSecOk) {
      console.log(`= ${id}: bereits ${JSON.stringify(desired)}`);
      continue;
    }
    // Schutz: ohne --rollback nie Rechte HINZUFÜGEN (das Soll kann veraltet
    // sein; ein Lauf darf den Live-Stand nur verengen).
    const widen = desired.filter((p) => !(current.$permissions ?? []).includes(p));
    if (widen.length && !ROLLBACK && !args.includes('--allow-widen')) {
      console.log(`! ${id}: Soll würde Rechte hinzufügen ${JSON.stringify(widen)} — übersprungen (nur mit --allow-widen)`);
      continue;
    }
    changes++;
    console.log(`~ ${id}`);
    console.log(`    ist:  ${JSON.stringify(current.$permissions)} documentSecurity=${current.documentSecurity}`);
    console.log(`    soll: ${JSON.stringify(desired)} documentSecurity=true`);
    if (!DRY) {
      try {
        await db.updateCollection(DB_ID, id, name, desired, true, current.enabled);
        console.log('    ✓ aktualisiert');
      } catch (e) {
        console.error(`    ✗ ${e.message}`);
      }
    }
  }
  console.log(`\n${changes} Collection(s) ${DRY ? 'würden geändert' : 'geändert'}.`);
  if (DRY && changes) {
    const only = ONLY ? ` --only=${ONLY.join(',')}` : '';
    console.log(`Ausführen: node fix-permissions.js${only}${ROLLBACK ? ' --rollback' : ''} --confirm=${projectId}`);
  }
}

// Einmalige Alt-Schritte (früher bei jedem Lauf): Media-Bucket-Rechte und
// fehlendes Attribut. Nur noch explizit mit --bootstrap.
async function bootstrap() {
  console.log('\nBootstrap: Media-Bucket + Attribute');
  if (DRY) {
    console.log('  (Dry-Run — nichts geändert)');
    return;
  }
  try {
    await storage.updateBucket(BUCKET_MEDIA, 'Media', [
      Permission.read(Role.any()), // CachedNetworkImage braucht keine Auth-Header
      Permission.create(Role.users()),
    ], true);
    console.log('  ✓ media bucket');
  } catch (e) {
    console.error(`  ✗ media bucket: ${e.message}`);
  }
  try {
    await db.createIntegerAttribute(DB_ID, 'organizations', 'pendingReportsCount', false, 0);
    console.log('  ✓ organizations.pendingReportsCount');
  } catch (e) {
    if (e.code === 409) console.log('  ~ organizations.pendingReportsCount existiert');
    else console.error(`  ✗ organizations.pendingReportsCount: ${e.message}`);
  }
}

async function main() {
  console.log(`=== fix-permissions — Projekt ${projectId} ===`);
  if (BOOTSTRAP) {
    await bootstrap();
    return;
  }
  await applyCollections();
}

main().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
