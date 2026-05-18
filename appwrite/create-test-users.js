/**
 * Guardian App — Testuser-Setup
 *
 * Legt folgende Accounts + eine Test-Org an:
 *   admin@test.guardian      → Admin der Org
 *   moderator@test.guardian  → Moderator
 *   member@test.guardian     → normales Mitglied
 *   guardian@test.guardian   → Guardian des Kindes
 *   parent@test.guardian     → Elternteil (verifiedParentUid des Kindes)
 *   child@test.guardian      → Kind-Account (isChild: true)
 *
 * Passwort aller Accounts: Test1234!
 *
 * Usage:
 *   node create-test-users.js             — erstellt alles
 *   node create-test-users.js --clean     — löscht alle Testuser + Test-Org vorher
 *
 * Benötigt: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY in .env
 */

import { config } from 'dotenv';
import { Client, Databases, Users, ID, Permission, Role, Query } from 'node-appwrite';

config();

const CLEAN = process.argv.includes('--clean');

const client = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT)
  .setProject(process.env.APPWRITE_PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY);

const db    = new Databases(client);
const users = new Users(client);

const DB_ID   = 'guardian';
const TEST_PW = 'Test1234!';
const ORG_ID  = 'test-org-001';
const ORG_NAME = 'Test-Organisation';

const TEST_USERS = [
  { id: 'test-admin',     email: 'admin@test.guardian',     name: 'Test Admin',     role: 'admin',     isChild: false },
  { id: 'test-moderator', email: 'moderator@test.guardian', name: 'Test Moderator', role: 'moderator', isChild: false },
  { id: 'test-member',    email: 'member@test.guardian',    name: 'Test Member',    role: 'member',    isChild: false },
  { id: 'test-guardian',  email: 'guardian@test.guardian',  name: 'Test Guardian',  role: 'member',    isChild: false },
  { id: 'test-parent',    email: 'parent@test.guardian',    name: 'Test Parent',    role: 'member',    isChild: false },
  { id: 'test-child',     email: 'child@test.guardian',     name: 'Test Kind',      role: 'child',     isChild: true  },
];

// ── Hilfsfunktionen ───────────────────────────────────────────────────────────

async function upsertAuthUser({ id, email, name }) {
  try {
    await users.get(id);
    console.log(`  ~ Auth-Account existiert bereits: ${email}`);
  } catch {
    await users.create(id, email, undefined, TEST_PW, name);
    console.log(`  ✓ Auth-Account erstellt: ${email}`);
  }
}

async function upsertUserDoc({ id, email, name, isChild }, extraData = {}) {
  const data = {
    email,
    displayName: name,
    isChild,
    membershipsJson: '[]',
    verifiedParentUids: [],
    createdAt: new Date().toISOString(),
    notificationSettingsJson: '{}',
    ...extraData,
  };
  try {
    await db.createDocument(DB_ID, 'users', id, data, [
      Permission.read(Role.users()),
      Permission.update(Role.user(id)),
    ]);
    console.log(`  ✓ User-Doc erstellt: ${name}`);
  } catch (e) {
    if (e.code === 409) {
      console.log(`  ~ User-Doc existiert bereits: ${name}`);
    } else {
      throw e;
    }
  }
}

async function updateMembershipsJson(userId, orgId, role) {
  try {
    const doc = await db.getDocument(DB_ID, 'users', userId);
    const memberships = JSON.parse(doc.data.membershipsJson || '[]');
    if (!memberships.find(m => m.orgId === orgId)) {
      memberships.push({ orgId, role });
      await db.updateDocument(DB_ID, 'users', userId, {
        membershipsJson: JSON.stringify(memberships),
      });
    }
  } catch (e) {
    console.error(`  ✗ membershipsJson update für ${userId}: ${e.message}`);
  }
}

async function upsertMemberDoc(userId, userData, orgId, role, extra = {}) {
  const memberId = `${orgId}_${userId}`;
  const data = {
    uid: userId,
    displayName: userData.name,
    email: userData.email,
    role,
    orgId,
    joinedAt: new Date().toISOString(),
    guardianUids: [],
    status: 'active',
    childAlertInterval: 'hourly',
    notificationsEnabled: true,
    messageAlertInterval: 'always',
    hideEmail: false,
    lastChildAlertAtJson: '{}',
    ...extra,
  };
  try {
    await db.createDocument(DB_ID, 'members', memberId, data);
    console.log(`  ✓ Member-Doc: ${userData.name} (${role})`);
  } catch (e) {
    if (e.code === 409) {
      console.log(`  ~ Member-Doc existiert bereits: ${userData.name}`);
    } else {
      throw e;
    }
  }
}

// ── Clean-up ──────────────────────────────────────────────────────────────────

async function clean() {
  console.log('\n── Clean: Lösche Testdaten ──────────────────────────────────');

  // Org-Dokument
  try {
    await db.deleteDocument(DB_ID, 'organizations', ORG_ID);
    console.log('  ✓ Test-Org gelöscht');
  } catch { console.log('  ~ Test-Org nicht gefunden'); }

  // Members der Test-Org
  try {
    const result = await db.listDocuments(DB_ID, 'members', [
      Query.equal('orgId', ORG_ID), Query.limit(50),
    ]);
    for (const doc of result.documents) {
      await db.deleteDocument(DB_ID, 'members', doc.$id);
    }
    console.log(`  ✓ ${result.documents.length} Member-Docs gelöscht`);
  } catch (e) { console.log(`  ~ Members: ${e.message}`); }

  // Auth-Accounts + User-Docs
  for (const u of TEST_USERS) {
    try {
      await users.delete(u.id);
      console.log(`  ✓ Auth-Account gelöscht: ${u.email}`);
    } catch { console.log(`  ~ Auth-Account nicht gefunden: ${u.email}`); }

    try {
      await db.deleteDocument(DB_ID, 'users', u.id);
      console.log(`  ✓ User-Doc gelöscht: ${u.email}`);
    } catch { console.log(`  ~ User-Doc nicht gefunden: ${u.email}`); }
  }
}

// ── Haupt-Setup ───────────────────────────────────────────────────────────────

async function main() {
  if (CLEAN) {
    await clean();
    console.log('\nClean abgeschlossen.\n');
    return;
  }

  const adminUser     = TEST_USERS.find(u => u.id === 'test-admin');
  const moderatorUser = TEST_USERS.find(u => u.id === 'test-moderator');
  const memberUser    = TEST_USERS.find(u => u.id === 'test-member');
  const guardianUser  = TEST_USERS.find(u => u.id === 'test-guardian');
  const parentUser    = TEST_USERS.find(u => u.id === 'test-parent');
  const childUser     = TEST_USERS.find(u => u.id === 'test-child');

  // 1. Auth-Accounts anlegen
  console.log('\n── Schritt 1: Auth-Accounts ─────────────────────────────────');
  for (const u of TEST_USERS) {
    await upsertAuthUser(u);
  }

  // 2. User-Dokumente in der users-Collection anlegen
  console.log('\n── Schritt 2: User-Dokumente ────────────────────────────────');
  await upsertUserDoc(adminUser);
  await upsertUserDoc(moderatorUser);
  await upsertUserDoc(memberUser);
  // Guardian: ebenfalls als Erziehungsberechtigter des Kindes
  await upsertUserDoc(guardianUser, {
    verifiedChildUids: [childUser.id],
  });
  // Parent: verifiedChildUids enthält das Kind
  await upsertUserDoc(parentUser, {
    verifiedChildUids: [childUser.id],
  });
  // Kind: isChild=true, verifiedParentUids enthält Parent + Guardian
  await upsertUserDoc(childUser, {
    isChild: true,
    verifiedParentUids: [parentUser.id, guardianUser.id],
  });

  // 3. Test-Organisation anlegen
  console.log('\n── Schritt 3: Test-Organisation ─────────────────────────────');
  const memberUids = TEST_USERS
    .filter(u => !u.isChild)  // Kind wird erst nach Zustimmung Vollmitglied
    .map(u => u.id);

  const orgData = {
    name: ORG_NAME,
    adminUid: adminUser.id,
    tag: 'schule',
    memberUids,
    createdAt: new Date().toISOString(),
    isArchived: false,
  };

  try {
    await db.createDocument(DB_ID, 'organizations', ORG_ID, orgData, [
      Permission.read(Role.users()),
      Permission.update(Role.user(adminUser.id)),
      Permission.delete(Role.user(adminUser.id)),
    ]);
    console.log(`  ✓ Org erstellt: ${ORG_NAME} (ID: ${ORG_ID})`);
  } catch (e) {
    if (e.code === 409) {
      console.log(`  ~ Org existiert bereits: ${ORG_NAME}`);
    } else {
      throw e;
    }
  }

  // 4. Member-Dokumente anlegen
  console.log('\n── Schritt 4: Member-Dokumente ──────────────────────────────');
  await upsertMemberDoc(adminUser.id,     adminUser,     ORG_ID, 'admin');
  await upsertMemberDoc(moderatorUser.id, moderatorUser, ORG_ID, 'moderator');
  await upsertMemberDoc(memberUser.id,    memberUser,    ORG_ID, 'member');
  await upsertMemberDoc(guardianUser.id,  guardianUser,  ORG_ID, 'member');
  await upsertMemberDoc(parentUser.id,    parentUser,    ORG_ID, 'member');
  // Kind: status=pending, guardianUid = guardian + parent
  await upsertMemberDoc(childUser.id, childUser, ORG_ID, 'child', {
    status: 'pending',
    guardianUids: [guardianUser.id, parentUser.id],
  });

  // 5. membershipsJson in User-Docs aktualisieren
  console.log('\n── Schritt 5: membershipsJson aktualisieren ─────────────────');
  await updateMembershipsJson(adminUser.id,     ORG_ID, 'admin');
  await updateMembershipsJson(moderatorUser.id, ORG_ID, 'moderator');
  await updateMembershipsJson(memberUser.id,    ORG_ID, 'member');
  await updateMembershipsJson(guardianUser.id,  ORG_ID, 'member');
  await updateMembershipsJson(parentUser.id,    ORG_ID, 'member');
  await updateMembershipsJson(childUser.id,     ORG_ID, 'child');
  console.log('  ✓ alle membershipsJson aktualisiert');

  // 6. Zusammenfassung
  console.log('\n── Fertig! ───────────────────────────────────────────────────');
  console.log('\nTestuser (Passwort für alle: Test1234!):\n');
  console.log('  Rolle       | E-Mail');
  console.log('  ------------|-----------------------------');
  console.log('  Admin       | admin@test.guardian');
  console.log('  Moderator   | moderator@test.guardian');
  console.log('  Mitglied    | member@test.guardian');
  console.log('  Guardian    | guardian@test.guardian');
  console.log('  Elternteil  | parent@test.guardian');
  console.log('  Kind        | child@test.guardian');
  console.log(`\nOrg: "${ORG_NAME}" (ID: ${ORG_ID})`);
  console.log('Das Kind hat Status "pending" — ein Guardian muss es noch freischalten.\n');
}

main().catch(console.error);
